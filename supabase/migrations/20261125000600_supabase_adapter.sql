-- 0006: Supabase adapter. Plain PostgreSQL ignores the Supabase-only parts, so the same
-- migrations and tests run in both places.
--
--   * Identity: on Supabase, the caller is the account whose auth_subject equals auth.uid()
--     from the verified JWT. Requests arriving through the Supabase API (roles anon or
--     authenticated) MUST carry a JWT; the app.account_id setting is honoured only for trusted
--     server-side sessions (tests, maintenance), never for API traffic.
--   * Accounts are created and kept in step with auth.users by a trigger (email and
--     verification come from Supabase Auth, never from the client).
--   * The app reaches only schema api, through the Supabase role `authenticated`. anon gets nothing.
--   * Event photos live in the private Storage bucket `event-photos` under events/<event id>/.
--     Storage policies: upload by that chapter's admin; read by approved members once the photo
--     is registered and visible; delete by that chapter's admin or a global admin.

-- ------------------------------------------------------------------ identity

create or replace function app.current_account_id() returns uuid language plpgsql stable as $$
declare
    sub text;
    acc uuid;
    v text;
    api_role text := current_setting('role', true);
begin
    if to_regprocedure('auth.uid()') is not null then
        execute 'select auth.uid()::text' into sub;
    end if;
    if sub is not null then
        select id into acc from app.accounts where auth_subject = sub;
        if acc is null then
            raise exception 'account not provisioned' using errcode = '28000';
        end if;
        return acc;
    end if;
    if api_role in ('anon', 'authenticated') then
        raise exception 'not authenticated' using errcode = '28000';
    end if;
    v := current_setting('app.account_id', true);
    if v is null or v = '' then
        raise exception 'not authenticated' using errcode = '28000';
    end if;
    return v::uuid;
end $$;

-- Audit actor now comes from the same identity function (JWT on Supabase).
create or replace function app.audit(p_action text, p_entity text, p_id uuid, p_chapter uuid, p_detail jsonb default '{}')
returns void language plpgsql as $$
declare actor uuid;
begin
    begin
        actor := app.current_account_id();
    exception when others then
        actor := null;   -- operator actions (e.g. bootstrap) have no caller
    end;
    insert into app.audit_events (actor, action, entity, entity_id, chapter_id, detail)
    values (actor, p_action, p_entity, p_id, p_chapter, p_detail);
end $$;

revoke all on function app.current_account_id() from public;
revoke all on function app.audit(text, text, uuid, uuid, jsonb) from public;

-- New api functions in later migrations are never executable by PUBLIC by default.
alter default privileges in schema api revoke execute on functions from public;
alter default privileges in schema api grant execute on functions to bbg_api;

-- ------------------------------------------------------------------ Supabase roles

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant usage on schema api to authenticated;
        grant execute on all functions in schema api to authenticated;
        alter default privileges in schema api grant execute on functions to authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke all on schema api from anon;
        revoke all on all functions in schema api from anon;
        revoke all on schema app from anon;
    end if;
end $$;

-- ------------------------------------------------------------------ auth.users -> app.accounts

create function app.sync_auth_user() returns trigger
language plpgsql security definer set search_path = app, pg_temp as $$
begin
    if tg_op = 'DELETE' then
        update accounts set status = 'disabled' where auth_subject = old.id::text;
        return old;
    end if;
    if new.email is null then
        return new;   -- only email sign-up is used
    end if;
    perform app.upsert_account(new.id::text, new.email, new.email_confirmed_at is not null);
    return new;
end $$;
revoke all on function app.sync_auth_user() from public;

do $$
begin
    if to_regclass('auth.users') is not null then
        execute 'drop trigger if exists bbg_sync_account on auth.users';
        execute 'create trigger bbg_sync_account
                 after insert or update of email, email_confirmed_at or delete on auth.users
                 for each row execute function app.sync_auth_user()';
    end if;
end $$;

-- ------------------------------------------------------------------ storage policy helpers

create function app.photo_event_id(p_name text) returns uuid language plpgsql immutable as $$
begin
    if p_name !~ '^events/[0-9a-f-]{36}/[a-z0-9][a-z0-9_\-.]*$' or p_name ~ '\.\.' then
        return null;
    end if;
    return split_part(p_name, '/', 2)::uuid;
exception when others then
    return null;
end $$;

create function app.can_upload_event_photo(p_name text) returns boolean
language plpgsql stable security definer set search_path = app, pg_temp as $$
declare me uuid; ev uuid := app.photo_event_id(p_name); ch uuid;
begin
    begin me := app.require_verified_caller(); exception when others then return false; end;
    select chapter_id into ch from events where id = ev;
    return ch is not null and app.has_role(me, 'chapter_admin', ch);
end $$;

create function app.can_read_event_photo(p_name text) returns boolean
language plpgsql stable security definer set search_path = app, pg_temp as $$
declare me uuid;
begin
    begin me := app.require_verified_caller(); exception when others then return false; end;
    return app.is_approved_member(me) and exists (
        select 1 from media m join events e on e.id = m.event_id
        where m.storage_key = p_name and m.status = 'visible' and e.status in ('published', 'cancelled'));
end $$;

create function app.can_delete_event_photo(p_name text) returns boolean
language plpgsql stable security definer set search_path = app, pg_temp as $$
declare me uuid; ch uuid;
begin
    begin me := app.require_verified_caller(); exception when others then return false; end;
    select chapter_id into ch from events where id = app.photo_event_id(p_name);
    return (ch is not null and app.has_role(me, 'chapter_admin', ch)) or app.has_role(me, 'global_admin', null);
end $$;

revoke all on function app.photo_event_id(text), app.can_upload_event_photo(text),
                       app.can_read_event_photo(text), app.can_delete_event_photo(text) from public;

do $$
begin
    if to_regclass('storage.objects') is null or not exists (select 1 from pg_roles where rolname = 'authenticated') then
        return;
    end if;
    -- Policies call these three helpers as the requesting role; nothing else in app is granted.
    grant usage on schema app to authenticated;
    grant execute on function app.can_upload_event_photo(text), app.can_read_event_photo(text),
                              app.can_delete_event_photo(text) to authenticated;

    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('event-photos', 'event-photos', false, 2000000, array['image/jpeg', 'image/webp'])
    on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
                                   allowed_mime_types = excluded.allowed_mime_types;

    execute 'drop policy if exists bbg_event_photos_read on storage.objects';
    execute 'drop policy if exists bbg_event_photos_upload on storage.objects';
    execute 'drop policy if exists bbg_event_photos_delete on storage.objects';
    execute $p$create policy bbg_event_photos_read on storage.objects for select to authenticated
             using (bucket_id = 'event-photos' and app.can_read_event_photo(name))$p$;
    execute $p$create policy bbg_event_photos_upload on storage.objects for insert to authenticated
             with check (bucket_id = 'event-photos' and app.can_upload_event_photo(name))$p$;
    execute $p$create policy bbg_event_photos_delete on storage.objects for delete to authenticated
             using (bucket_id = 'event-photos' and app.can_delete_event_photo(name))$p$;
    -- No update policy: photos are never overwritten in place.
end $$;
