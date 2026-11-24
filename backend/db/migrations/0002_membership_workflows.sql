-- 0002: remaining M2 membership workflows.
--   * correction requested -> applicant resubmits; applicant may withdraw
--   * rejection -> one appeal, decided by a global administrator who did not reject it;
--     an upheld appeal reopens the application and bars the original reviewer
--   * secretary review queue with possible-duplicate counts (suggestions only, never merges)
--   * chapter list for routing, including the temporary global intake chapter
--   * account disable/enable by a global administrator
begin;

create type app.appeal_status as enum ('open', 'upheld', 'dismissed');

create table app.appeals (
    id                uuid primary key default gen_random_uuid(),
    application_id    uuid not null unique references app.membership_applications(id),
    account_id        uuid not null references app.accounts(id),
    original_reviewer uuid not null references app.accounts(id),
    reason            text not null check (length(trim(reason)) between 1 and 2000),
    status            app.appeal_status not null default 'open',
    decided_by        uuid references app.accounts(id),
    decision_note     text check (decision_note is null or length(decision_note) <= 1000),
    submitted_at      timestamptz not null default now(),
    decided_at        timestamptz,
    check (decided_by is null or (decided_by <> account_id and decided_by <> original_reviewer))
);

-- ------------------------------------------------------------------ helpers

create function app.owned_application(p_application uuid, p_account uuid)
returns app.membership_applications language plpgsql as $$
declare ma app.membership_applications;
begin
    select * into ma from app.membership_applications where id = p_application for update;
    -- Same error whether it does not exist or belongs to someone else: no probing.
    if not found or ma.account_id <> p_account then
        raise exception 'application not found' using errcode = 'P0002';
    end if;
    return ma;
end $$;

-- Possible duplicates: same surname and given name (case-insensitive) and birth year within one.
-- Suggestions for human review only.
create function app.duplicate_candidates(p_person uuid) returns setof uuid language sql stable as $$
    select o.id from app.persons p
    join app.persons o on o.id <> p.id
     and lower(o.surname) = lower(p.surname)
     and lower(o.given_name) = lower(p.given_name)
     and (o.birth_year is null or p.birth_year is null or abs(o.birth_year - p.birth_year) <= 1)
    where p.id = p_person
$$;

revoke all on all functions in schema app from public;

-- ------------------------------------------------------------------ applicant actions

create function api.resubmit_application(
    p_application uuid, p_given_name text, p_surname text, p_birth_year int,
    p_ancestral_village text, p_present_city text, p_present_country text
) returns void language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); ma membership_applications;
begin
    ma := app.owned_application(p_application, me);
    if ma.status <> 'correction_requested' then
        raise exception 'only applications needing correction can be resubmitted' using errcode = '55000';
    end if;
    update persons set given_name = trim(p_given_name), surname = trim(p_surname), birth_year = p_birth_year,
           ancestral_village = p_ancestral_village, present_city = p_present_city, present_country = p_present_country
     where id = ma.person_id;
    update membership_applications set status = 'pending', submitted_at = now() where id = ma.id;
    perform app.audit('resubmit_application', 'membership_application', ma.id, ma.chapter_id);
end $$;

create function api.withdraw_application(p_application uuid) returns void
language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); ma membership_applications;
begin
    ma := app.owned_application(p_application, me);
    if ma.status not in ('pending', 'correction_requested') then
        raise exception 'only open applications can be withdrawn' using errcode = '55000';
    end if;
    update membership_applications set status = 'withdrawn' where id = ma.id;
    perform app.audit('withdraw_application', 'membership_application', ma.id, ma.chapter_id);
end $$;

create function api.appeal_rejection(p_application uuid, p_reason text) returns uuid
language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); ma membership_applications; aid uuid;
begin
    ma := app.owned_application(p_application, me);
    if ma.status <> 'rejected' then
        raise exception 'only rejected applications can be appealed' using errcode = '55000';
    end if;
    if coalesce(trim(p_reason), '') = '' then
        raise exception 'a reason is required' using errcode = '22023';
    end if;
    insert into appeals (application_id, account_id, original_reviewer, reason)
    values (ma.id, me, ma.reviewed_by, trim(p_reason)) returning id into aid;   -- unique: one appeal
    perform app.audit('appeal_rejection', 'appeal', aid, ma.chapter_id);
    return aid;
end $$;

-- ------------------------------------------------------------------ reviewer actions

create function api.decide_appeal(p_appeal uuid, p_uphold boolean, p_note text) returns void
language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); ap appeals; ch uuid;
begin
    if not app.has_role(me, 'global_admin', null) then
        raise exception 'only a global administrator decides appeals' using errcode = '42501';
    end if;
    select * into ap from appeals where id = p_appeal for update;
    if not found then
        raise exception 'appeal not found' using errcode = 'P0002';
    end if;
    if ap.status <> 'open' then
        raise exception 'appeal already decided' using errcode = '55000';
    end if;
    if me in (ap.account_id, ap.original_reviewer) then
        raise exception 'cannot decide an appeal you are party to' using errcode = '42501';
    end if;
    if coalesce(trim(p_note), '') = '' then
        raise exception 'a decision note is required' using errcode = '22023';
    end if;
    update appeals set status = case when p_uphold then 'upheld' else 'dismissed' end::appeal_status,
           decided_by = me, decision_note = trim(p_note), decided_at = now()
     where id = ap.id;
    if p_uphold then
        update membership_applications set status = 'pending', reviewed_by = null, reviewed_at = null
         where id = ap.application_id
        returning chapter_id into ch;
    end if;
    perform app.audit(case when p_uphold then 'appeal_upheld' else 'appeal_dismissed' end, 'appeal', ap.id, ch);
end $$;

-- Replaces 0001's version: adds the bar on the original reviewer after an upheld appeal.
create or replace function api.review_application(p_application uuid, p_decision app.application_status, p_note text)
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
    if exists (select 1 from appeals where application_id = ma.id and status = 'upheld' and original_reviewer = me) then
        raise exception 'original reviewer cannot re-review after an upheld appeal' using errcode = '42501';
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

-- Applications waiting in chapters where the caller is secretary. Oldest first.
create function api.review_queue() returns table (
    application_id uuid, chapter_id uuid, chapter_name_en text, submitted_at timestamptz,
    given_name text, surname text, birth_year int, ancestral_village text,
    present_city text, present_country text, possible_duplicates int, after_appeal boolean
) language plpgsql stable security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller();
begin
    return query
    select ma.id, ma.chapter_id, c.name_en, ma.submitted_at,
           p.given_name, p.surname, p.birth_year, p.ancestral_village, p.present_city, p.present_country,
           (select count(*)::int from app.duplicate_candidates(p.id)),
           exists (select 1 from appeals a where a.application_id = ma.id and a.status = 'upheld')
    from membership_applications ma
    join persons p on p.id = ma.person_id
    join chapters c on c.id = ma.chapter_id
    where ma.status = 'pending'
      and app.has_role(me, 'chapter_secretary', ma.chapter_id)
      and ma.account_id <> me
    order by ma.submitted_at;
end $$;

-- Duplicate candidates for one application in the caller's queue: minimal identifying fields.
create function api.duplicate_candidates(p_application uuid) returns table (
    member_code text, given_name text, surname text, birth_year int, ancestral_village text,
    is_member boolean
) language plpgsql stable security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); ma membership_applications;
begin
    select * into ma from membership_applications where id = p_application;
    if not found or not app.has_role(me, 'chapter_secretary', ma.chapter_id) then
        raise exception 'application not found' using errcode = 'P0002';
    end if;
    return query
    select o.member_code, o.given_name, o.surname, o.birth_year, o.ancestral_village,
           exists (select 1 from memberships m where m.person_id = o.id)
    from app.duplicate_candidates(ma.person_id) d
    join persons o on o.id = d;
end $$;

-- ------------------------------------------------------------------ routing and admin

-- Chapters a verified applicant can choose. has_secretary tells the app whether review
-- can currently happen; no names of office-bearers are exposed.
create function api.list_chapters() returns table (
    id uuid, parent_id uuid, level app.chapter_level, name_en text, name_gu text,
    country_code text, is_global_intake boolean, has_secretary boolean
) language plpgsql stable security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller();
begin
    return query
    select c.id, c.parent_id, c.level, c.name_en, c.name_gu, c.country_code, c.is_global_intake,
           exists (select 1 from role_assignments r where r.chapter_id = c.id
                   and r.role = 'chapter_secretary' and r.revoked_at is null)
    from chapters c
    where c.accepts_applications
    order by c.is_global_intake desc, c.country_code nulls first, c.name_en;
end $$;

-- Disabling blocks every api call at once (require_verified_caller). Revoking the
-- sign-in session itself is done at the auth provider by the API layer.
create function api.set_account_disabled(p_account uuid, p_disabled boolean, p_reason text) returns void
language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller();
begin
    if not app.has_role(me, 'global_admin', null) then
        raise exception 'only a global administrator can disable accounts' using errcode = '42501';
    end if;
    if p_account = me then
        raise exception 'cannot disable your own account' using errcode = '42501';
    end if;
    if coalesce(trim(p_reason), '') = '' then
        raise exception 'a reason is required' using errcode = '22023';
    end if;
    update accounts set status = case when p_disabled then 'disabled' else 'active' end::account_status
     where id = p_account;
    if not found then
        raise exception 'account not found' using errcode = 'P0002';
    end if;
    perform app.audit(case when p_disabled then 'disable_account' else 'enable_account' end, 'account', p_account, null);
end $$;

revoke all on all functions in schema api from public;
grant execute on all functions in schema api to bbg_api;

commit;
