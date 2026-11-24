-- 0005: directory contact sharing and rate limits; chapter events, announcements, RSVP and
-- attendance; event photo metadata with scoped upload, reporting and removal. Brief milestone M5.
--
-- Rules
--   * Contact details are released one member at a time, only to approved members, only the
--     fields the person consented to (email and phone separately), and every release is logged
--     and rate-limited. Searches are rate-limited too.
--   * Events store an absolute instant plus the organiser's IANA time zone; listings return the
--     event-local time and the viewer-local time, computed by PostgreSQL's time zone database
--     (handles daylight-saving changes). Local times that do not exist (clock jumps) are refused.
--   * Only a chapter admin or secretary of the exact chapter creates and manages its events and
--     announcements; only a chapter admin uploads its photos. No parent-chapter inheritance.
--   * Photo bytes live in object storage; the database holds the storage key and limits
--     (JPEG/WebP, max 2 MB, max 2560 px). Signed URLs are issued by the API layer, never public.
--   * Participant names are visible only to the organising chapter's admins/secretaries.
begin;

create type app.event_status as enum ('draft', 'published', 'cancelled');
create type app.rsvp_status as enum ('going', 'maybe', 'not_going', 'waitlisted');
create type app.media_status as enum ('visible', 'removed');

insert into app.settings values
    ('directory_searches_per_hour', '60'),
    ('contact_reveals_per_day', '20'),
    ('max_photo_bytes', '2000000'),
    ('max_photo_pixels', '2560');

create table app.person_contacts (
    person_id uuid primary key references app.persons(id),
    phone     text check (phone is null or phone ~ '^\+?[0-9 ]{6,20}$'),
    updated_at timestamptz not null default now()
);

create table app.directory_queries (
    account_id uuid not null references app.accounts(id),
    at         timestamptz not null default now()
);
create index directory_queries_idx on app.directory_queries (account_id, at);

create table app.contact_reveals (
    viewer  uuid not null references app.accounts(id),
    target  uuid not null references app.persons(id),
    fields  text[] not null,
    at      timestamptz not null default now()
);
create index contact_reveals_idx on app.contact_reveals (viewer, at);

create table app.events (
    id             uuid primary key default gen_random_uuid(),
    chapter_id     uuid not null references app.chapters(id),
    title_en       text not null check (length(trim(title_en)) between 1 and 200),
    title_gu       text not null check (length(trim(title_gu)) between 1 and 200),
    description_en text check (description_en is null or length(description_en) <= 4000),
    description_gu text check (description_gu is null or length(description_gu) <= 4000),
    starts_at      timestamptz not null,
    ends_at        timestamptz not null,
    time_zone      text not null,
    venue          text check (venue is null or length(venue) <= 300),
    online_url     text check (online_url is null or online_url ~ '^https://[^\s]+$'),
    capacity       int check (capacity is null or capacity > 0),
    status         app.event_status not null default 'draft',
    organiser      uuid not null references app.accounts(id),
    created_at     timestamptz not null default now(),
    check (ends_at > starts_at),
    check (venue is not null or online_url is not null)
);

create table app.rsvps (
    event_id   uuid not null references app.events(id),
    person_id  uuid not null references app.persons(id),
    status     app.rsvp_status not null,
    guests     int not null default 0 check (guests between 0 and 5),
    attended   boolean,
    updated_at timestamptz not null default now(),
    primary key (event_id, person_id)
);

create table app.announcements (
    id         uuid primary key default gen_random_uuid(),
    chapter_id uuid not null references app.chapters(id),
    title_en   text not null check (length(trim(title_en)) between 1 and 200),
    title_gu   text not null check (length(trim(title_gu)) between 1 and 200),
    body_en    text not null check (length(body_en) <= 4000),
    body_gu    text not null check (length(body_gu) <= 4000),
    meeting_url text check (meeting_url is null or meeting_url ~ '^https://[^\s]+$'),
    author     uuid not null references app.accounts(id),
    published_at timestamptz not null default now(),
    removed_at timestamptz,
    removed_by uuid references app.accounts(id)
);

create table app.media (
    id            uuid primary key default gen_random_uuid(),
    event_id      uuid not null references app.events(id),
    storage_key   text not null unique
                  check (storage_key ~ '^[a-z0-9][a-z0-9/_\-.]{7,199}$' and storage_key !~ '(\.\.|//)'),  -- no traversal
    content_type  text not null check (content_type in ('image/jpeg', 'image/webp')),
    bytes         int not null check (bytes > 0),
    width         int not null check (width > 0),
    height        int not null check (height > 0),
    caption_en    text check (caption_en is null or length(caption_en) <= 300),
    caption_gu    text check (caption_gu is null or length(caption_gu) <= 300),
    uploaded_by   uuid not null references app.accounts(id),
    uploaded_at   timestamptz not null default now(),
    status        app.media_status not null default 'visible',
    removed_by    uuid references app.accounts(id),
    removed_at    timestamptz,
    removal_reason text
);

create table app.media_reports (
    id          uuid primary key default gen_random_uuid(),
    media_id    uuid not null references app.media(id),
    reporter    uuid not null references app.accounts(id),
    reason      text not null check (length(trim(reason)) between 1 and 1000),
    created_at  timestamptz not null default now(),
    resolved_by uuid references app.accounts(id),
    resolved_at timestamptz,
    resolution  text check (resolution in ('removed', 'kept')),
    unique (media_id, reporter)
);

-- ------------------------------------------------------------------ helpers

create function app.setting_int(k text) returns int language sql stable as $$
    select value::int from app.settings where key = k
$$;

create function app.is_valid_tz(tz text) returns boolean language sql stable as $$
    select exists (select 1 from pg_timezone_names where name = tz)
$$;

-- Event managers: admin or secretary of exactly that chapter.
create function app.can_manage_chapter(me uuid, ch uuid) returns boolean language sql stable as $$
    select app.has_role(me, 'chapter_admin', ch) or app.has_role(me, 'chapter_secretary', ch)
$$;

create function app.require_member(me uuid) returns uuid language plpgsql stable as $$
begin
    if not app.is_approved_member(me) then
        raise exception 'available to approved members only' using errcode = '42501';
    end if;
    return app.my_person(me);
end $$;

create function app.local_to_instant(p_local timestamp, p_tz text) returns timestamptz
language plpgsql stable as $$
declare inst timestamptz;
begin
    if not app.is_valid_tz(p_tz) then
        raise exception 'unknown time zone' using errcode = '22023';
    end if;
    inst := p_local at time zone p_tz;
    -- Refuse wall-clock times skipped by a daylight-saving jump (they do not exist locally).
    if (inst at time zone p_tz) <> p_local then
        raise exception 'that local time does not exist in this time zone (clock change)' using errcode = '22023';
    end if;
    return inst;
end $$;

create function app.going_seats(ev uuid) returns int language sql stable as $$
    select coalesce(sum(1 + guests), 0)::int from app.rsvps where event_id = ev and status = 'going'
$$;

revoke all on all functions in schema app from public;

-- ------------------------------------------------------------------ directory (replaces 0001 version: adds rate limit)

create or replace function api.directory_search(p_query text, p_limit int default 20)
returns table (member_code text, given_name text, surname text, profession text,
               ancestral_village text, present_country text, chapter_name_en text, chapter_name_gu text)
language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); q text := trim(coalesce(p_query, ''));
begin
    if not app.is_approved_member(me) then
        raise exception 'directory is available to approved members only' using errcode = '42501';
    end if;
    if length(q) < 2 then
        raise exception 'search needs at least 2 characters' using errcode = '22023';
    end if;
    if (select count(*) from directory_queries where account_id = me and at > now() - interval '1 hour')
       >= app.setting_int('directory_searches_per_hour') then
        raise exception 'too many searches; try again later' using errcode = '54000';
    end if;
    insert into directory_queries (account_id) values (me);
    q := replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_');
    return query
    select p.member_code, p.given_name, p.surname, p.profession, p.ancestral_village, p.present_country,
           c.name_en, c.name_gu
    from persons p
    join memberships m on m.person_id = p.id and m.status = 'approved'
    join chapters c on c.id = m.chapter_id
    join consents cs on cs.person_id = p.id and cs.purpose = 'directory_listing' and cs.granted
    where p.is_living
      and (p.given_name ilike '%' || q || '%' or p.surname ilike '%' || q || '%'
           or p.ancestral_village ilike '%' || q || '%' or p.profession ilike '%' || q || '%')
    order by p.surname, p.given_name
    limit least(greatest(coalesce(p_limit, 20), 1), 50);
end $$;

create function api.set_contact_phone(p_phone text) returns void
language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); pid uuid := app.my_person(me);
begin
    if pid is null then raise exception 'no profile yet' using errcode = 'P0002'; end if;
    insert into person_contacts (person_id, phone) values (pid, nullif(trim(p_phone), ''))
    on conflict (person_id) do update set phone = excluded.phone, updated_at = now();
    perform app.audit('set_contact_phone', 'person', pid, null);
end $$;

-- One member's contact details, only the fields they chose to share.
create function api.directory_contact(p_member_code text) returns table (email text, phone text)
language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); target persons; acct accounts; f text[] := '{}';
begin
    perform app.require_member(me);
    select p.* into target from persons p
      join memberships m on m.person_id = p.id and m.status = 'approved'
     where p.member_code = p_member_code and p.is_living and app.has_consent(p.id, 'directory_listing');
    if not found then
        raise exception 'member not found' using errcode = 'P0002';   -- unlisted looks the same as absent
    end if;
    if (select count(*) from contact_reveals where viewer = me and at > now() - interval '1 day')
       >= app.setting_int('contact_reveals_per_day') then
        raise exception 'daily contact limit reached' using errcode = '54000';
    end if;
    select a.* into acct from accounts a join account_person ap on ap.account_id = a.id where ap.person_id = target.id;
    email := case when app.has_consent(target.id, 'directory_email') then acct.email end;
    phone := case when app.has_consent(target.id, 'directory_phone')
                  then (select pc.phone from person_contacts pc where pc.person_id = target.id) end;
    if email is not null then f := f || 'email'::text; end if;
    if phone is not null then f := f || 'phone'::text; end if;
    insert into contact_reveals (viewer, target, fields) values (me, target.id, f);
    return next;
end $$;

-- ------------------------------------------------------------------ events

create function api.create_event(
    p_chapter uuid, p_title_en text, p_title_gu text, p_description_en text, p_description_gu text,
    p_starts_local timestamp, p_ends_local timestamp, p_time_zone text,
    p_venue text, p_online_url text, p_capacity int
) returns uuid language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); eid uuid;
begin
    if not app.can_manage_chapter(me, p_chapter) then
        raise exception 'not an admin or secretary of this chapter' using errcode = '42501';
    end if;
    insert into events (chapter_id, title_en, title_gu, description_en, description_gu, starts_at, ends_at,
                        time_zone, venue, online_url, capacity, organiser)
    values (p_chapter, p_title_en, p_title_gu, p_description_en, p_description_gu,
            app.local_to_instant(p_starts_local, p_time_zone), app.local_to_instant(p_ends_local, p_time_zone),
            p_time_zone, p_venue, p_online_url, p_capacity, me)
    returning id into eid;
    perform app.audit('create_event', 'event', eid, p_chapter);
    return eid;
end $$;

create function api.set_event_status(p_event uuid, p_status app.event_status) returns void
language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); e events;
begin
    select * into e from events where id = p_event for update;
    if not found or not app.can_manage_chapter(me, e.chapter_id) then
        raise exception 'event not found' using errcode = 'P0002';
    end if;
    if e.status = 'cancelled' then
        raise exception 'cancelled events cannot be changed' using errcode = '55000';
    end if;
    update events set status = p_status where id = e.id;
    perform app.audit('event_status:' || p_status, 'event', e.id, e.chapter_id);
end $$;

-- Published events worldwide for approved members, in event-local and viewer-local time.
create function api.list_events(p_viewer_tz text, p_from timestamptz default now(),
                                p_to timestamptz default now() + interval '1 year',
                                p_chapter uuid default null, p_country text default null)
returns table (event_id uuid, chapter_name_en text, chapter_name_gu text, title_en text, title_gu text,
               starts_at timestamptz, event_time_zone text, starts_event_local timestamp,
               starts_viewer_local timestamp, ends_viewer_local timestamp,
               venue text, online_url text, capacity int, seats_taken int, my_rsvp app.rsvp_status, status app.event_status)
language plpgsql stable security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); pid uuid;
begin
    pid := app.require_member(me);
    if not app.is_valid_tz(p_viewer_tz) then
        raise exception 'unknown time zone' using errcode = '22023';
    end if;
    return query
    select e.id, c.name_en, c.name_gu, e.title_en, e.title_gu, e.starts_at, e.time_zone,
           (e.starts_at at time zone e.time_zone), (e.starts_at at time zone p_viewer_tz),
           (e.ends_at at time zone p_viewer_tz), e.venue, e.online_url, e.capacity, app.going_seats(e.id),
           (select r.status from rsvps r where r.event_id = e.id and r.person_id = pid), e.status
    from events e join chapters c on c.id = e.chapter_id
    where e.status in ('published', 'cancelled')
      and e.ends_at >= p_from and e.starts_at < p_to
      and (p_chapter is null or e.chapter_id = p_chapter)
      and (p_country is null or c.country_code = upper(p_country))
    order by e.starts_at;
end $$;

-- RSVP. Over capacity becomes waitlisted; when a place frees up the earliest waitlisted moves in.
create function api.rsvp(p_event uuid, p_status app.rsvp_status, p_guests int default 0) returns app.rsvp_status
language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); pid uuid := app.require_member(me); e events;
        final rsvp_status := p_status; mine int := 0; w rsvps;
begin
    if p_status = 'waitlisted' then raise exception 'invalid RSVP' using errcode = '22023'; end if;
    select * into e from events where id = p_event for update;   -- serialises capacity checks
    if not found or e.status <> 'published' then
        raise exception 'event not open for RSVP' using errcode = '55000';
    end if;
    if e.ends_at < now() then
        raise exception 'event has ended' using errcode = '55000';
    end if;
    select 1 + guests into mine from rsvps where event_id = e.id and person_id = pid and status = 'going';
    if p_status = 'going' and e.capacity is not null
       and app.going_seats(e.id) - coalesce(mine, 0) + 1 + coalesce(p_guests, 0) > e.capacity then
        final := 'waitlisted';
    end if;
    insert into rsvps (event_id, person_id, status, guests) values (e.id, pid, final, coalesce(p_guests, 0))
    on conflict (event_id, person_id) do update set status = excluded.status, guests = excluded.guests, updated_at = now();

    -- Promote from the waitlist in order while places remain.
    if e.capacity is not null then
        for w in select * from rsvps where event_id = e.id and status = 'waitlisted' order by updated_at loop
            exit when app.going_seats(e.id) + 1 + w.guests > e.capacity;
            update rsvps set status = 'going' where event_id = w.event_id and person_id = w.person_id;
        end loop;
    end if;
    return (select status from rsvps where event_id = e.id and person_id = pid);
end $$;

-- Participant list for organisers of that chapter only.
create function api.event_participants(p_event uuid) returns table (
    given_name text, surname text, member_code text, rsvp app.rsvp_status, guests int, attended boolean
) language plpgsql stable security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); e events;
begin
    select * into e from events where id = p_event;
    if not found or not app.can_manage_chapter(me, e.chapter_id) then
        raise exception 'event not found' using errcode = 'P0002';
    end if;
    return query select p.given_name, p.surname, p.member_code, r.status, r.guests, r.attended
    from rsvps r join persons p on p.id = r.person_id where r.event_id = e.id order by p.surname, p.given_name;
end $$;

create function api.mark_attendance(p_event uuid, p_member_code text, p_attended boolean) returns void
language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); e events;
begin
    select * into e from events where id = p_event;
    if not found or not app.can_manage_chapter(me, e.chapter_id) then
        raise exception 'event not found' using errcode = 'P0002';
    end if;
    update rsvps r set attended = p_attended from persons p
     where r.event_id = e.id and p.id = r.person_id and p.member_code = p_member_code;
    if not found then raise exception 'no RSVP for that member' using errcode = 'P0002'; end if;
end $$;

-- ------------------------------------------------------------------ announcements

create function api.post_announcement(p_chapter uuid, p_title_en text, p_title_gu text,
                                      p_body_en text, p_body_gu text, p_meeting_url text) returns uuid
language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); aid uuid;
begin
    if not app.can_manage_chapter(me, p_chapter) then
        raise exception 'not an admin or secretary of this chapter' using errcode = '42501';
    end if;
    insert into announcements (chapter_id, title_en, title_gu, body_en, body_gu, meeting_url, author)
    values (p_chapter, p_title_en, p_title_gu, p_body_en, p_body_gu, p_meeting_url, me) returning id into aid;
    perform app.audit('post_announcement', 'announcement', aid, p_chapter);
    return aid;
end $$;

create function api.remove_announcement(p_announcement uuid) returns void
language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); a announcements;
begin
    select * into a from announcements where id = p_announcement and removed_at is null for update;
    if not found or not (app.can_manage_chapter(me, a.chapter_id) or app.has_role(me, 'global_admin', null)) then
        raise exception 'announcement not found' using errcode = 'P0002';
    end if;
    update announcements set removed_at = now(), removed_by = me where id = a.id;
    perform app.audit('remove_announcement', 'announcement', a.id, a.chapter_id);
end $$;

create function api.list_announcements(p_chapter uuid default null) returns table (
    announcement_id uuid, chapter_name_en text, chapter_name_gu text, title_en text, title_gu text,
    body_en text, body_gu text, meeting_url text, published_at timestamptz
) language plpgsql stable security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller();
begin
    perform app.require_member(me);
    return query select a.id, c.name_en, c.name_gu, a.title_en, a.title_gu, a.body_en, a.body_gu, a.meeting_url, a.published_at
    from announcements a join chapters c on c.id = a.chapter_id
    where a.removed_at is null and (p_chapter is null or a.chapter_id = p_chapter)
    order by a.published_at desc limit 100;
end $$;

-- ------------------------------------------------------------------ event photos

-- Registers an already-compressed upload. The API layer stores the bytes and passes the key.
create function api.register_event_photo(p_event uuid, p_storage_key text, p_content_type text,
                                         p_bytes int, p_width int, p_height int,
                                         p_caption_en text, p_caption_gu text) returns uuid
language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); e events; mid uuid;
begin
    select * into e from events where id = p_event;
    if not found or not app.has_role(me, 'chapter_admin', e.chapter_id) then
        raise exception 'only an admin of the event''s chapter can upload photos' using errcode = '42501';
    end if;
    if p_bytes > app.setting_int('max_photo_bytes')
       or greatest(p_width, p_height) > app.setting_int('max_photo_pixels') then
        raise exception 'photo must be compressed first (max 2 MB, 2560 px)' using errcode = '22023';
    end if;
    insert into media (event_id, storage_key, content_type, bytes, width, height, caption_en, caption_gu, uploaded_by)
    values (e.id, p_storage_key, p_content_type, p_bytes, p_width, p_height, p_caption_en, p_caption_gu, me)
    returning id into mid;
    perform app.audit('register_photo', 'media', mid, e.chapter_id);
    return mid;
end $$;

-- Visible photos of one event, for approved members. Storage keys go to the API layer, which
-- turns them into short-lived signed URLs.
create function api.event_photos(p_event uuid) returns table (
    media_id uuid, storage_key text, width int, height int, caption_en text, caption_gu text
) language plpgsql stable security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller();
begin
    perform app.require_member(me);
    return query select m.id, m.storage_key, m.width, m.height, m.caption_en, m.caption_gu
    from media m join events e on e.id = m.event_id
    where m.event_id = p_event and m.status = 'visible' and e.status in ('published', 'cancelled')
    order by m.uploaded_at;
end $$;

create function api.report_photo(p_media uuid, p_reason text) returns void
language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller();
begin
    perform app.require_member(me);
    if not exists (select 1 from media where id = p_media and status = 'visible') then
        raise exception 'photo not found' using errcode = 'P0002';
    end if;
    insert into media_reports (media_id, reporter, reason) values (p_media, me, trim(p_reason));
    perform app.audit('report_photo', 'media', p_media, null);
end $$;

-- Removal by the event chapter's admin or a global admin. Resolves open reports.
create function api.remove_photo(p_media uuid, p_reason text) returns void
language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); m media; ch uuid;
begin
    select md.* into m from media md where md.id = p_media and md.status = 'visible' for update;
    select e.chapter_id into ch from events e where e.id = m.event_id;
    if m.id is null or not (app.has_role(me, 'chapter_admin', ch) or app.has_role(me, 'global_admin', null)) then
        raise exception 'photo not found' using errcode = 'P0002';
    end if;
    if coalesce(trim(p_reason), '') = '' then
        raise exception 'a reason is required' using errcode = '22023';
    end if;
    update media set status = 'removed', removed_by = me, removed_at = now(), removal_reason = trim(p_reason)
     where id = m.id;
    update media_reports set resolved_by = me, resolved_at = now(), resolution = 'removed'
     where media_id = m.id and resolved_at is null;
    perform app.audit('remove_photo', 'media', m.id, ch);
end $$;

-- Open photo reports for chapters the caller administers.
create function api.photo_report_queue() returns table (
    report_id uuid, media_id uuid, event_title_en text, reason text, created_at timestamptz
) language plpgsql stable security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller();
begin
    return query select r.id, r.media_id, e.title_en, r.reason, r.created_at
    from media_reports r join media m on m.id = r.media_id join events e on e.id = m.event_id
    where r.resolved_at is null and m.status = 'visible'
      and (app.has_role(me, 'chapter_admin', e.chapter_id) or app.has_role(me, 'global_admin', null))
    order by r.created_at;
end $$;

revoke all on all functions in schema api from public;
grant execute on all functions in schema api to bbg_api;

commit;
