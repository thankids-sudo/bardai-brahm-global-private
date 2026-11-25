-- 0001: identity, chapters, scoped roles, membership applications, audit.
-- Plain PostgreSQL (16+). Portable across the backend options in docs/BACKEND_OPTIONS.md.
--
-- Security model
--   * Clients never touch tables. The API connects as role bbg_api, which may only EXECUTE
--     the functions in schema api. Every function re-checks the caller's permissions.
--   * The caller is identified by app.current_account_id(), which reads the transaction
--     setting app.account_id that the API sets (SET LOCAL) after verifying the auth token.
--     A Supabase adapter would replace only that function body (auth.uid()).
--   * Email address is contact data, never identity: accounts are keyed by the auth
--     provider's subject id; persons get an immutable member code.

create schema if not exists app;   -- tables and internal helpers
create schema if not exists api;   -- the only surface exposed to bbg_api

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'bbg_api') then
        create role bbg_api nologin;
    end if;
end $$;

revoke all on schema app from public;
revoke all on schema api from public;
grant usage on schema api to bbg_api;

-- ------------------------------------------------------------------ types

create type app.account_status as enum ('active', 'disabled');
create type app.chapter_level as enum ('global', 'country', 'state', 'district', 'city');
create type app.role_kind as enum (
    'global_admin', 'country_admin', 'state_admin', 'chapter_admin',
    'chapter_secretary', 'survey_volunteer'
);
create type app.application_status as enum ('pending', 'correction_requested', 'approved', 'rejected', 'withdrawn');
create type app.membership_status as enum ('approved', 'suspended');
create type app.consent_purpose as enum ('membership', 'directory_listing', 'directory_email', 'directory_phone');

-- ------------------------------------------------------------------ tables

create table app.accounts (
    id              uuid primary key default gen_random_uuid(),
    auth_subject    text not null unique,          -- provider user id, e.g. Firebase/Supabase uid
    email           text not null,
    email_verified  boolean not null default false,
    status          app.account_status not null default 'active',
    created_at      timestamptz not null default now()
);
create unique index accounts_email_lower_uq on app.accounts (lower(email));

create sequence app.member_code_seq start 1001;

create table app.persons (
    id              uuid primary key default gen_random_uuid(),
    member_code     text not null unique
                    default 'BBG-' || lpad(nextval('app.member_code_seq')::text, 7, '0'),
    given_name      text not null check (length(trim(given_name)) between 1 and 100),
    surname         text not null check (length(trim(surname)) between 1 and 100),
    former_surname  text check (former_surname is null or length(trim(former_surname)) <= 100),
    birth_year      int check (birth_year between 1850 and 2100),
    is_living       boolean not null default true,
    ancestral_village text check (ancestral_village is null or length(ancestral_village) <= 120),
    present_city    text check (present_city is null or length(present_city) <= 120),
    present_country text check (present_country is null or present_country ~ '^[A-Z]{2}$'),
    profession      text check (profession is null or length(profession) <= 120),
    created_by      uuid references app.accounts(id),
    created_at      timestamptz not null default now()
);

-- One person record per account (the account holder). Other relatives come in M3.
create table app.account_person (
    account_id uuid primary key references app.accounts(id),
    person_id  uuid not null unique references app.persons(id)
);

create table app.chapters (
    id         uuid primary key default gen_random_uuid(),
    parent_id  uuid references app.chapters(id),
    level      app.chapter_level not null,
    name_en    text not null,
    name_gu    text not null,
    country_code text check (country_code is null or country_code ~ '^[A-Z]{2}$'),
    accepts_applications boolean not null default true,
    is_global_intake boolean not null default false,  -- temporary global membership secretary route
    created_at timestamptz not null default now(),
    check ((level = 'global') = (parent_id is null))
);
create unique index one_global_intake on app.chapters (is_global_intake) where is_global_intake;

create table app.role_assignments (
    id          uuid primary key default gen_random_uuid(),
    account_id  uuid not null references app.accounts(id),
    role        app.role_kind not null,
    chapter_id  uuid references app.chapters(id),
    granted_by  uuid references app.accounts(id),          -- null only for the one-time bootstrap
    granted_at  timestamptz not null default now(),
    revoked_by  uuid references app.accounts(id),
    revoked_at  timestamptz,
    check ((role = 'global_admin') = (chapter_id is null)),
    check (granted_by is null or granted_by <> account_id)   -- no self-grants
);
create unique index active_role_uq on app.role_assignments
    (account_id, role, coalesce(chapter_id, '00000000-0000-0000-0000-000000000000'))
    where revoked_at is null;

create table app.membership_applications (
    id            uuid primary key default gen_random_uuid(),
    account_id    uuid not null references app.accounts(id),
    person_id     uuid not null references app.persons(id),
    chapter_id    uuid not null references app.chapters(id),
    status        app.application_status not null default 'pending',
    reviewer_note text check (reviewer_note is null or length(reviewer_note) <= 1000),
    reviewed_by   uuid references app.accounts(id),
    reviewed_at   timestamptz,
    submitted_at  timestamptz not null default now(),
    check (reviewed_by is null or reviewed_by <> account_id)
);
create unique index one_open_application on app.membership_applications (account_id)
    where status in ('pending', 'correction_requested');

-- Primary residence chapter membership. One per person (no double counting).
create table app.memberships (
    person_id   uuid primary key references app.persons(id),
    chapter_id  uuid not null references app.chapters(id),
    status      app.membership_status not null,
    approved_by uuid not null references app.accounts(id),
    approved_at timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);

create table app.consents (
    person_id  uuid not null references app.persons(id),
    purpose    app.consent_purpose not null,
    granted    boolean not null,
    recorded_by uuid not null references app.accounts(id),
    recorded_at timestamptz not null default now(),
    primary key (person_id, purpose)
);

-- Append-only. Holds ids and action names, never personal payloads.
create table app.audit_events (
    id          bigint generated always as identity primary key,
    at          timestamptz not null default now(),
    actor       uuid references app.accounts(id),
    action      text not null,
    entity      text not null,
    entity_id   uuid,
    chapter_id  uuid references app.chapters(id),
    detail      jsonb not null default '{}'::jsonb
);

-- ------------------------------------------------------------------ integrity triggers

create function app.forbid_member_code_change() returns trigger language plpgsql as $$
begin
    if new.member_code is distinct from old.member_code then
        raise exception 'member_code is immutable' using errcode = 'P0001';
    end if;
    return new;
end $$;
create trigger persons_member_code_immutable before update on app.persons
    for each row execute function app.forbid_member_code_change();

create function app.forbid_audit_mutation() returns trigger language plpgsql as $$
begin
    raise exception 'audit_events is append-only' using errcode = 'P0001';
end $$;
create trigger audit_append_only before update or delete on app.audit_events
    for each row execute function app.forbid_audit_mutation();

-- ------------------------------------------------------------------ helpers (not exposed)

create function app.current_account_id() returns uuid language plpgsql stable as $$
declare v text := current_setting('app.account_id', true);
begin
    if v is null or v = '' then
        raise exception 'not authenticated' using errcode = '28000';
    end if;
    return v::uuid;
end $$;

-- Active, email-verified caller. Everything except reading one's own status needs this.
create function app.require_verified_caller() returns uuid language plpgsql stable as $$
declare a app.accounts;
begin
    select * into a from app.accounts where id = app.current_account_id();
    if not found or a.status <> 'active' then
        raise exception 'account not active' using errcode = '42501';
    end if;
    if not a.email_verified then
        raise exception 'email not verified' using errcode = '42501';
    end if;
    return a.id;
end $$;

-- Exact-scope role check. Parent-chapter roles do NOT inherit authority over children:
-- the brief requires explicit policies for parent scope, which M2 does not define.
create function app.has_role(p_account uuid, p_role app.role_kind, p_chapter uuid)
returns boolean language sql stable as $$
    select exists (
        select 1 from app.role_assignments r
        where r.account_id = p_account and r.role = p_role and r.revoked_at is null
          and r.chapter_id is not distinct from p_chapter
    )
$$;

create function app.is_approved_member(p_account uuid) returns boolean language sql stable as $$
    select exists (
        select 1 from app.account_person ap
        join app.memberships m on m.person_id = ap.person_id
        where ap.account_id = p_account and m.status = 'approved'
    )
$$;

create function app.audit(p_action text, p_entity text, p_id uuid, p_chapter uuid, p_detail jsonb default '{}')
returns void language sql as $$
    insert into app.audit_events (actor, action, entity, entity_id, chapter_id, detail)
    values (nullif(current_setting('app.account_id', true), '')::uuid, p_action, p_entity, p_id, p_chapter, p_detail)
$$;

-- ------------------------------------------------------------------ operator-only

-- Called by the API's trusted auth webhook after the provider confirms identity/verification,
-- never with client-supplied values. Not granted to bbg_api; run by a separate backend role.
create function app.upsert_account(p_subject text, p_email text, p_verified boolean)
returns uuid language plpgsql security definer set search_path = app, pg_temp as $$
declare v uuid;
begin
    insert into accounts (auth_subject, email, email_verified)
    values (p_subject, p_email, p_verified)
    on conflict (auth_subject) do update
        set email = excluded.email, email_verified = excluded.email_verified
    returning id into v;
    return v;
end $$;

-- One-time global administrator bootstrap (brief: verified identity + controlled backend op).
-- Run manually by the database owner. Refuses if any global admin already exists.
create function app.bootstrap_global_admin(p_email text) returns uuid
language plpgsql security definer set search_path = app, pg_temp as $$
declare a accounts;
begin
    if exists (select 1 from role_assignments where role = 'global_admin' and revoked_at is null) then
        raise exception 'global admin already exists; use api.grant_role' using errcode = '42501';
    end if;
    select * into a from accounts where lower(email) = lower(p_email);
    if not found then
        raise exception 'no account for that email; the person must sign up first' using errcode = 'P0002';
    end if;
    if not a.email_verified or a.status <> 'active' then
        raise exception 'account email not verified or not active' using errcode = '42501';
    end if;
    insert into role_assignments (account_id, role, chapter_id, granted_by) values (a.id, 'global_admin', null, null);
    insert into audit_events (actor, action, entity, entity_id) values (null, 'bootstrap_global_admin', 'account', a.id);
    return a.id;
end $$;

revoke all on all functions in schema app from public;

-- ------------------------------------------------------------------ API surface

create function api.my_status() returns table (
    email_verified boolean, account_status app.account_status,
    application_status app.application_status, membership_status app.membership_status, member_code text
) language sql stable security definer set search_path = app, pg_temp as $$
    select a.email_verified, a.status,
           (select ma.status from membership_applications ma where ma.account_id = a.id
             order by ma.submitted_at desc limit 1),
           m.status, p.member_code
    from accounts a
    left join account_person ap on ap.account_id = a.id
    left join persons p on p.id = ap.person_id
    left join memberships m on m.person_id = ap.person_id
    where a.id = app.current_account_id()
$$;

create function api.submit_application(
    p_chapter uuid, p_given_name text, p_surname text, p_birth_year int,
    p_ancestral_village text, p_present_city text, p_present_country text
) returns uuid language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); pid uuid; aid uuid; ch chapters;
begin
    select * into ch from chapters where id = p_chapter;
    if not found or not ch.accepts_applications then
        raise exception 'chapter does not accept applications' using errcode = '22023';
    end if;
    if exists (select 1 from account_person ap join memberships m on m.person_id = ap.person_id
               where ap.account_id = me) then
        raise exception 'already a member' using errcode = '23505';
    end if;

    select person_id into pid from account_person where account_id = me;
    if pid is null then
        insert into persons (given_name, surname, birth_year, ancestral_village, present_city, present_country, created_by)
        values (trim(p_given_name), trim(p_surname), p_birth_year, p_ancestral_village, p_present_city, p_present_country, me)
        returning id into pid;
        insert into account_person values (me, pid);
    else
        update persons set given_name = trim(p_given_name), surname = trim(p_surname), birth_year = p_birth_year,
               ancestral_village = p_ancestral_village, present_city = p_present_city, present_country = p_present_country
        where id = pid;
    end if;

    insert into membership_applications (account_id, person_id, chapter_id) values (me, pid, p_chapter)
    returning id into aid;   -- unique index blocks a second open application
    insert into consents (person_id, purpose, granted, recorded_by) values (pid, 'membership', true, me)
        on conflict (person_id, purpose) do update set granted = true, recorded_at = now(), recorded_by = me;
    perform app.audit('submit_application', 'membership_application', aid, p_chapter);
    return aid;
end $$;

-- Secretary decision. Authority is the exact chapter the application was routed to.
create function api.review_application(p_application uuid, p_decision app.application_status, p_note text)
returns void language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); ma membership_applications;
begin
    if p_decision not in ('approved', 'rejected', 'correction_requested') then
        raise exception 'invalid decision' using errcode = '22023';
    end if;
    select * into ma from membership_applications where id = p_application for update;
    if not found then
        raise exception 'application not found' using errcode = 'P0002';
    end if;
    if not app.has_role(me, 'chapter_secretary', ma.chapter_id) then
        raise exception 'not secretary of this chapter' using errcode = '42501';
    end if;
    if ma.account_id = me then
        raise exception 'cannot review own application' using errcode = '42501';
    end if;
    if ma.status <> 'pending' then
        raise exception 'application is not pending' using errcode = '55000';
    end if;
    if p_decision in ('rejected', 'correction_requested') and coalesce(trim(p_note), '') = '' then
        raise exception 'a reason is required' using errcode = '22023';
    end if;

    update membership_applications
       set status = p_decision, reviewer_note = p_note, reviewed_by = me, reviewed_at = now()
     where id = ma.id;
    if p_decision = 'approved' then
        insert into memberships (person_id, chapter_id, status, approved_by)
        values (ma.person_id, ma.chapter_id, 'approved', me);
    end if;
    perform app.audit('review_application:' || p_decision, 'membership_application', ma.id, ma.chapter_id);
end $$;

create function api.set_membership_suspended(p_person uuid, p_suspended boolean, p_reason text)
returns void language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); m memberships;
begin
    select * into m from memberships where person_id = p_person for update;
    if not found then
        raise exception 'membership not found' using errcode = 'P0002';
    end if;
    if not app.has_role(me, 'chapter_secretary', m.chapter_id) then
        raise exception 'not secretary of this chapter' using errcode = '42501';
    end if;
    if exists (select 1 from account_person where account_id = me and person_id = p_person) then
        raise exception 'cannot change own membership' using errcode = '42501';
    end if;
    if coalesce(trim(p_reason), '') = '' then
        raise exception 'a reason is required' using errcode = '22023';
    end if;
    update memberships set status = case when p_suspended then 'suspended' else 'approved' end::membership_status,
           updated_at = now()
     where person_id = p_person;
    perform app.audit(case when p_suspended then 'suspend_member' else 'reinstate_member' end,
                      'person', p_person, m.chapter_id);
end $$;

-- Role appointment. M2 policy: only a global administrator appoints, never to themselves.
create function api.grant_role(p_account uuid, p_role app.role_kind, p_chapter uuid)
returns uuid language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); rid uuid;
begin
    if not app.has_role(me, 'global_admin', null) then
        raise exception 'only a global administrator can appoint roles' using errcode = '42501';
    end if;
    if p_account = me then
        raise exception 'cannot grant a role to yourself' using errcode = '42501';
    end if;
    if not exists (select 1 from accounts where id = p_account and email_verified and status = 'active') then
        raise exception 'target account must be active and email-verified' using errcode = '42501';
    end if;
    insert into role_assignments (account_id, role, chapter_id, granted_by)
    values (p_account, p_role, p_chapter, me) returning id into rid;
    perform app.audit('grant_role:' || p_role, 'account', p_account, p_chapter);
    return rid;
end $$;

create function api.revoke_role(p_assignment uuid) returns void
language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); r role_assignments;
begin
    if not app.has_role(me, 'global_admin', null) then
        raise exception 'only a global administrator can revoke roles' using errcode = '42501';
    end if;
    select * into r from role_assignments where id = p_assignment and revoked_at is null for update;
    if not found then
        raise exception 'active assignment not found' using errcode = 'P0002';
    end if;
    if r.account_id = me and r.role = 'global_admin' then
        raise exception 'cannot revoke your own global admin role' using errcode = '42501';
    end if;
    update role_assignments set revoked_at = now(), revoked_by = me where id = r.id;
    perform app.audit('revoke_role:' || r.role, 'account', r.account_id, r.chapter_id);
end $$;

create function api.set_consent(p_purpose app.consent_purpose, p_granted boolean) returns void
language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); pid uuid;
begin
    select person_id into pid from account_person where account_id = me;
    if pid is null then
        raise exception 'no profile yet' using errcode = 'P0002';
    end if;
    insert into consents (person_id, purpose, granted, recorded_by) values (pid, p_purpose, p_granted, me)
    on conflict (person_id, purpose) do update set granted = excluded.granted, recorded_at = now(), recorded_by = me;
    perform app.audit('set_consent:' || p_purpose || ':' || p_granted, 'person', pid, null);
end $$;

-- Worldwide directory for approved members. Only people who opted in are listed, and only
-- approved-name/profession/chapter/village/country fields; contact details are never returned here.
create function api.directory_search(p_query text, p_limit int default 20)
returns table (member_code text, given_name text, surname text, profession text,
               ancestral_village text, present_country text, chapter_name_en text, chapter_name_gu text)
language plpgsql stable security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); q text := trim(coalesce(p_query, ''));
begin
    if not app.is_approved_member(me) then
        raise exception 'directory is available to approved members only' using errcode = '42501';
    end if;
    if length(q) < 2 then
        raise exception 'search needs at least 2 characters' using errcode = '22023';
    end if;
    -- Escape LIKE wildcards so a query cannot enumerate everyone.
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

revoke all on all functions in schema api from public;
grant execute on all functions in schema api to bbg_api;
