-- Supabase-only tests for migration 0006 (runs inside `supabase start` in CI; skipped elsewhere).
-- Checks: accounts follow auth.users; identity comes from the JWT, never from a client-settable
-- value; anon has no access; storage policies for event photos.
\set ON_ERROR_STOP on
set client_min_messages = warning;
select (to_regclass('auth.users') is not null and to_regclass('storage.objects') is not null) as has_supabase \gset
\if :has_supabase
\o /dev/null
\ir _harness.sql

-- Simulate a request from the app: role authenticated with a JWT for the given auth user.
create function t.as_jwt(p_uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims',
        case when p_uid is null then '' else json_build_object('sub', p_uid, 'role', 'authenticated')::text end, false);
    perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), false);
end $$;
create table t.uids (name text primary key, uid uuid not null);
grant usage on schema t to authenticated, anon;
grant all on all tables in schema t to authenticated, anon;
grant all on all sequences in schema t to authenticated, anon;
grant execute on all functions in schema t to authenticated, anon;
create function t.uid(p text) returns uuid language sql stable as $$ select uid from t.uids where name = p $$;
grant select on t.uids to authenticated, anon;
grant execute on function t.uid(text) to authenticated, anon, bbg_api;

create function t.new_auth_user(p_name text, p_email text, p_confirmed boolean) returns uuid language plpgsql as $$
declare u uuid := gen_random_uuid();
begin
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                            raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    values ('00000000-0000-0000-0000-000000000000', u, 'authenticated', 'authenticated', p_email, '',
            case when p_confirmed then now() end, '{}', '{}', now(), now());
    insert into t.uids values (p_name, u);
    return u;
end $$;

-- ---------------------------------------------------------------- accounts follow auth.users
select t.new_auth_user('admin',  'sb-admin@example.test',  true);
select t.new_auth_user('chadm',  'sb-chadm@example.test',  true);
select t.new_auth_user('member', 'sb-member@example.test', true);
select t.new_auth_user('other',  'sb-other@example.test',  true);
select t.new_auth_user('unconf', 'sb-unconf@example.test', false);

select t.ok('sign-up creates an account keyed by the auth user id, not the email',
    (select count(*) = 5 from app.accounts a join t.uids u on a.auth_subject = u.uid::text));
select t.ok('unconfirmed email is recorded as unverified',
    (select not email_verified from app.accounts where auth_subject = t.uid('unconf')::text));
update auth.users set email_confirmed_at = now() where id = t.uid('unconf');
select t.ok('confirming the email in Supabase Auth verifies the account',
    (select email_verified from app.accounts where auth_subject = t.uid('unconf')::text));

insert into t.ids select name, a.id from t.uids u join app.accounts a on a.auth_subject = u.uid::text;
insert into app.chapters (id, parent_id, level, name_en, name_gu, accepts_applications) values
 ('00000000-0000-0000-0000-00000000f0a0', null, 'global', 'Global', 'વૈશ્વિક', false);
insert into app.chapters (id, parent_id, level, name_en, name_gu, country_code) values
 ('00000000-0000-0000-0000-00000000f0a1', '00000000-0000-0000-0000-00000000f0a0', 'city', 'SB City', 'એસબી શહેર', 'IN');
insert into t.ids values ('ch', '00000000-0000-0000-0000-00000000f0a1');
select app.bootstrap_global_admin('sb-admin@example.test');

-- ---------------------------------------------------------------- identity from the JWT
set role authenticated;
select t.as_jwt(t.uid('member'));
select t.ok('app request identifies the caller from the JWT',
    (select email_verified from api.my_status()));
select set_config('app.account_id', t.id('admin')::text, false);
select t.raises('a client-set account id cannot override the JWT identity (admin action refused)',
    $$select api.grant_role(t.id('other'), 'chapter_secretary', t.id('ch'))$$, '42501');
select t.as_jwt(null);
select t.raises('API request without a JWT is rejected even with app.account_id set',
    $$select * from api.my_status()$$, '28000');
select set_config('app.account_id', '', false);
select t.as_jwt(t.uid('member'));
select t.raises('app cannot read tables directly', $$select * from app.accounts$$, '42501');
select t.raises('app cannot create or verify accounts', $$select app.upsert_account('x', 'x@example.test', true)$$, '42501');
select t.raises('app cannot bootstrap an admin', $$select app.bootstrap_global_admin('sb-member@example.test')$$, '42501');
reset role;

set role anon;
select t.raises('anonymous callers cannot reach the api schema', $$select * from api.my_status()$$, '42501');
reset role;

-- ---------------------------------------------------------------- full flow through JWTs
set role authenticated;
select t.as_jwt(t.uid('admin'));
select api.grant_role(t.id('chadm'), 'chapter_admin', t.id('ch'));
select api.grant_role(t.id('chadm'), 'chapter_secretary', t.id('ch'));
select t.as_jwt(t.uid('member'));
insert into t.ids select 'app_member', api.submit_application(t.id('ch'), 'Sb', 'Memberbhai', 1985, null, null, 'IN');
select t.as_jwt(t.uid('chadm'));
select api.review_application(t.id('app_member'), 'approved', null);
insert into t.ids select 'ev', api.create_event(t.id('ch'), 'Photo day', 'ફોટો દિવસ', null, null,
    '2027-03-01 10:00', '2027-03-01 12:00', 'Asia/Kolkata', 'Hall', null, null);
select api.set_event_status(t.id('ev'), 'published');
reset role;

select t.ok('audit records the JWT caller as actor',
    (select count(*) = 1 from app.audit_events where action = 'review_application:approved' and actor = t.id('chadm')));

-- ---------------------------------------------------------------- storage policies
create table t.keys (name text primary key, key text not null);
insert into t.keys values ('good', 'events/' || t.id('ev') || '/day1.webp'),
                          ('other_folder', 'events/' || gen_random_uuid() || '/x.webp'),
                          ('traversal', 'events/' || t.id('ev') || '/../x.webp');
grant select on t.keys to authenticated;

select t.ok('event-photos bucket is private with size and type limits',
    (select not public and file_size_limit = 2000000 and allowed_mime_types = array['image/jpeg', 'image/webp']
       from storage.buckets where id = 'event-photos'));
select t.ok('read, upload and delete policies exist; no update policy',
    (select count(*) = 3 and bool_and(policyname like 'bbg_event_photos_%') from pg_policies
      where schemaname = 'storage' and tablename = 'objects' and policyname like 'bbg_%'));

set role authenticated;
select t.as_jwt(t.uid('chadm'));
select t.ok('chapter admin may upload into the event folder',
    app.can_upload_event_photo((select key from t.keys where name = 'good')));
select t.ok('nobody may upload outside a real event folder',
    not app.can_upload_event_photo((select key from t.keys where name = 'other_folder'))
    and not app.can_upload_event_photo((select key from t.keys where name = 'traversal')));
select t.succeeds('upload through RLS succeeds for the chapter admin',
    $$insert into storage.objects (bucket_id, name) values ('event-photos', (select key from t.keys where name = 'good'))$$);
select t.as_jwt(t.uid('member'));
select t.ok('members may not upload', not app.can_upload_event_photo((select key from t.keys where name = 'good')));
select t.raises('upload through RLS is refused for a member',
    $$insert into storage.objects (bucket_id, name) values ('event-photos', 'events/' || t.id('ev') || '/member.webp')$$, '42501');
select t.ok('unregistered photo is not readable yet',
    not exists (select 1 from storage.objects where name = (select key from t.keys where name = 'good')));
select t.as_jwt(t.uid('chadm'));
select api.register_event_photo(t.id('ev'), (select key from t.keys where name = 'good'), 'image/webp', 200000, 1600, 1200, null, null);
select t.as_jwt(t.uid('member'));
select t.ok('approved member can read the registered photo (signed URLs need this)',
    exists (select 1 from storage.objects where name = (select key from t.keys where name = 'good')));
select t.ok('members may not delete photos', not app.can_delete_event_photo((select key from t.keys where name = 'good')));
select t.as_jwt(t.uid('other'));
select t.ok('verified non-member cannot read photos',
    not exists (select 1 from storage.objects where bucket_id = 'event-photos'));
select t.as_jwt(t.uid('chadm'));
select t.ok('chapter admin may delete photos of their event', app.can_delete_event_photo((select key from t.keys where name = 'good')));
select t.as_jwt(t.uid('admin'));
select t.ok('global admin may delete any event photo', app.can_delete_event_photo((select key from t.keys where name = 'good')));
reset role;

-- ---------------------------------------------------------------- account deletion
delete from auth.users where id = t.uid('other');
select t.ok('deleting the auth user disables the account (records kept for others'' trees)',
    (select status = 'disabled' from app.accounts where id = t.id('other')));

\ir _report.sql
\else
\echo '006_supabase_adapter_test.sql skipped: not a Supabase database'
\endif
