-- 0003: person records for relatives, family relationships, households, residences,
-- record claims (invitations) and reviewed merges.  Brief milestone M3.
--
-- Principles
--   * Every person record has exactly one owner: the account that claimed it, or else the
--     account that entered it (managed_by). Only the owner edits it.
--   * Relationships are parent->child (with a type: biological, adoptive, step, guardian,
--     foster, unknown) or spouse (with optional start/end years for remarriage).
--     Siblings, half-siblings, grandparents and in-laws are derived, not stored.
--   * A link between two records with different owners is 'pending' until the other owner
--     accepts it. Pending links are visible only to the two parties.
--   * Family views mask living relatives unless the viewer owns the record, or the relative
--     has their own account, allows relatives to see them, and every link on the path is
--     accepted. Living minors are always masked except to their owner. Directory
--     membership never grants access to anyone's tree.
--   * Records are never merged automatically; a reviewer approves each merge.
create type app.rel_kind as enum ('parent', 'spouse');
create type app.parent_type as enum ('biological', 'adoptive', 'step', 'guardian', 'foster', 'unknown');
create type app.link_status as enum ('self_reported', 'pending', 'confirmed', 'disputed', 'retracted');
create type app.person_visibility as enum ('relatives', 'only_me');
create type app.consent_basis as enum ('self', 'assisted_with_consent', 'guardian', 'deceased_record');
create type app.merge_status as enum ('pending', 'approved', 'rejected');

alter table app.persons
    add column birthplace text check (birthplace is null or length(birthplace) <= 120),
    add column death_year int check (death_year between 1700 and 2100),
    add column managed_by uuid references app.accounts(id),
    add column family_visibility app.person_visibility not null default 'relatives',
    add column consent_basis app.consent_basis not null default 'self',
    add column merged_into uuid references app.persons(id),
    add constraint death_after_birth check (death_year is null or birth_year is null or death_year >= birth_year),
    add constraint deceased_has_no_living_flag check (death_year is null or not is_living),
    add constraint not_merged_into_self check (merged_into is null or merged_into <> id);

create table app.relationships (
    id           uuid primary key default gen_random_uuid(),
    kind         app.rel_kind not null,
    from_person  uuid not null references app.persons(id),   -- parent, or spouse with the lower id
    to_person    uuid not null references app.persons(id),   -- child, or spouse with the higher id
    parent_type  app.parent_type,
    parent_label text check (parent_label in ('father', 'mother', 'parent')),
    start_year   int check (start_year between 1700 and 2100),
    end_year     int check (end_year between 1700 and 2100),
    status       app.link_status not null,
    created_by   uuid not null references app.accounts(id),
    created_at   timestamptz not null default now(),
    decided_by   uuid references app.accounts(id),
    decided_at   timestamptz,
    check (from_person <> to_person),
    check ((kind = 'parent') = (parent_type is not null)),
    check (kind = 'parent' or parent_label is null),
    check (kind = 'parent' or from_person < to_person),
    check (end_year is null or start_year is null or end_year >= start_year)
);
create unique index relationships_active_uq on app.relationships (kind, from_person, to_person)
    where status <> 'retracted';
create index relationships_to_idx on app.relationships (to_person);

create sequence app.household_code_seq start 1001;
create table app.households (
    id             uuid primary key default gen_random_uuid(),
    household_code text not null unique default 'HH-' || lpad(nextval('app.household_code_seq')::text, 7, '0'),
    created_by     uuid not null references app.accounts(id),
    created_at     timestamptz not null default now()
);
create table app.household_members (
    household_id uuid not null references app.households(id),
    person_id    uuid not null references app.persons(id),
    joined_on    date not null default current_date,
    left_on      date,
    check (left_on is null or left_on >= joined_on)
);
-- A person is counted in at most one current household.
create unique index one_current_household on app.household_members (person_id) where left_on is null;

create table app.residences (
    id        uuid primary key default gen_random_uuid(),
    person_id uuid not null references app.persons(id),
    city      text check (city is null or length(city) <= 120),
    state     text check (state is null or length(state) <= 120),
    country   text not null check (country ~ '^[A-Z]{2}$'),
    from_year int check (from_year between 1700 and 2100),
    to_year   int check (to_year between 1700 and 2100),
    is_current boolean not null default true,
    check (to_year is null or from_year is null or to_year >= from_year)
);
create unique index one_current_residence on app.residences (person_id) where is_current;

create table app.claim_invites (
    token_hash text primary key,                 -- sha256 of the token; the token itself is never stored
    person_id  uuid not null references app.persons(id),
    created_by uuid not null references app.accounts(id),
    created_at timestamptz not null default now(),
    expires_at timestamptz not null,
    used_by    uuid references app.accounts(id),
    used_at    timestamptz
);

create table app.merge_requests (
    id            uuid primary key default gen_random_uuid(),
    keep_person   uuid not null references app.persons(id),
    merge_person  uuid not null references app.persons(id),
    requested_by  uuid not null references app.accounts(id),
    conflicts     text[] not null default '{}',   -- field names that differ, never values
    status        app.merge_status not null default 'pending',
    reviewed_by   uuid references app.accounts(id),
    reviewed_at   timestamptz,
    review_note   text check (review_note is null or length(review_note) <= 1000),
    created_at    timestamptz not null default now(),
    check (keep_person <> merge_person),
    check (reviewed_by is null or reviewed_by <> requested_by)
);
create unique index one_open_merge_per_pair on app.merge_requests
    (least(keep_person, merge_person), greatest(keep_person, merge_person)) where status = 'pending';

-- ------------------------------------------------------------------ helpers

create function app.this_year() returns int language sql stable as $$ select extract(year from now())::int $$;

create function app.person_owner(p uuid) returns uuid language sql stable as $$
    select coalesce((select account_id from app.account_person where person_id = p),
                    (select managed_by from app.persons where id = p))
$$;

create function app.my_person(me uuid) returns uuid language sql stable as $$
    select person_id from app.account_person where account_id = me
$$;

create function app.require_owned_person(me uuid, p uuid) returns app.persons language plpgsql as $$
declare r app.persons;
begin
    select * into r from app.persons where id = p and merged_into is null;
    if not found or app.person_owner(p) is distinct from me then
        raise exception 'person not found' using errcode = 'P0002';   -- same error: no probing
    end if;
    return r;
end $$;

-- Adults with unknown birth year are treated as adults (stricter consent rules).
create function app.is_minor(r app.persons) returns boolean language sql stable as $$
    select r.is_living and r.birth_year is not null and r.birth_year > app.this_year() - 18
$$;

-- Account that must accept a link: owner of an endpoint who did not create it.
create function app.link_confirmer(r app.relationships) returns uuid language sql stable as $$
    select case when app.person_owner(r.from_person) is distinct from r.created_by
                then app.person_owner(r.from_person) else app.person_owner(r.to_person) end
$$;

-- True if `ancestor` is reachable upward from `p` through active parent links.
create function app.is_ancestor(ancestor uuid, p uuid) returns boolean language sql stable as $$
    with recursive up(id) as (
        select from_person from app.relationships
         where kind = 'parent' and to_person = p and status not in ('retracted', 'disputed')
        union
        select r.from_person from app.relationships r join up on r.to_person = up.id
         where r.kind = 'parent' and r.status not in ('retracted', 'disputed')
    )
    select exists (select 1 from up where id = ancestor)
$$;

create function app.can_see_person(me uuid, p uuid, via_pending boolean) returns boolean
language plpgsql stable as $$
declare r app.persons;
begin
    select * into r from app.persons where id = p;
    if app.person_owner(p) = me then return true; end if;
    if via_pending then return false; end if;
    if not r.is_living then return true; end if;
    if app.is_minor(r) then return false; end if;
    return exists (select 1 from app.account_person where person_id = p)
       and r.family_visibility = 'relatives';
end $$;

revoke all on all functions in schema app from public;

-- ------------------------------------------------------------------ person records

create function api.add_relative_person(
    p_given_name text, p_surname text, p_former_surname text, p_birth_year int,
    p_is_living boolean, p_death_year int, p_birthplace text, p_ancestral_village text,
    p_consent_basis app.consent_basis
) returns uuid language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); pid uuid; minor boolean;
begin
    if app.my_person(me) is null then
        raise exception 'create your own profile first' using errcode = '55000';
    end if;
    minor := p_is_living and p_birth_year is not null and p_birth_year > app.this_year() - 18;
    -- Consent basis must match who the record is about (brief: record who entered and why).
    if (not p_is_living and p_consent_basis <> 'deceased_record')
       or (p_is_living and minor and p_consent_basis <> 'guardian')
       or (p_is_living and not minor and p_consent_basis <> 'assisted_with_consent') then
        raise exception 'consent basis does not match this person' using errcode = '22023';
    end if;
    insert into persons (given_name, surname, former_surname, birth_year, is_living, death_year,
                         birthplace, ancestral_village, created_by, managed_by, consent_basis)
    values (trim(p_given_name), trim(p_surname), nullif(trim(p_former_surname), ''), p_birth_year, p_is_living,
            p_death_year, p_birthplace, p_ancestral_village, me, me, p_consent_basis)
    returning id into pid;
    perform app.audit('add_person:' || p_consent_basis, 'person', pid, null);
    return pid;
end $$;

create function api.set_family_visibility(p_visibility app.person_visibility) returns void
language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); pid uuid := app.my_person(me);
begin
    if pid is null then raise exception 'no profile yet' using errcode = 'P0002'; end if;
    update persons set family_visibility = p_visibility where id = pid;
    perform app.audit('set_family_visibility:' || p_visibility, 'person', pid, null);
end $$;

-- ------------------------------------------------------------------ relationships

create function api.add_relationship(
    p_kind app.rel_kind, p_from uuid, p_to uuid, p_parent_type app.parent_type,
    p_parent_label text, p_start_year int, p_end_year int
) returns uuid language plpgsql security definer set search_path = app, pg_temp as $$
declare
    me uuid := app.require_verified_caller();
    a persons; b persons; tmp uuid; rid uuid; st link_status;
    owner_a uuid; owner_b uuid;
begin
    if p_kind = 'spouse' and p_from > p_to then tmp := p_from; p_from := p_to; p_to := tmp; end if;
    select * into a from persons where id = p_from and merged_into is null;
    select * into b from persons where id = p_to and merged_into is null;
    owner_a := app.person_owner(p_from); owner_b := app.person_owner(p_to);
    -- You may only assert links that touch a record you own.
    if a.id is null or b.id is null or me not in (owner_a, owner_b) then
        raise exception 'person not found' using errcode = 'P0002';
    end if;
    if p_from = p_to then
        raise exception 'a person cannot be related to themselves' using errcode = '23514';
    end if;

    if p_kind = 'parent' then
        if p_parent_type is null then
            raise exception 'parent type is required' using errcode = '22023';
        end if;
        if app.is_ancestor(p_to, p_from) then
            raise exception 'this link would make a person their own ancestor' using errcode = '23514';
        end if;
        if a.birth_year is not null and b.birth_year is not null and a.birth_year >= b.birth_year then
            raise exception 'parent must be born before child' using errcode = '23514';
        end if;
        if p_parent_type = 'biological' and (
            select count(*) from relationships
             where kind = 'parent' and to_person = p_to and parent_type = 'biological'
               and status not in ('retracted', 'disputed')) >= 2 then
            raise exception 'a person has at most two biological parents' using errcode = '23514';
        end if;
    elsif p_parent_type is not null or p_parent_label is not null then
        raise exception 'parent fields apply only to parent links' using errcode = '22023';
    end if;

    st := case when owner_a = me and owner_b = me then 'self_reported' else 'pending' end;
    insert into relationships (kind, from_person, to_person, parent_type, parent_label, start_year, end_year, status, created_by)
    values (p_kind, p_from, p_to, p_parent_type, p_parent_label, p_start_year, p_end_year, st, me)
    returning id into rid;
    perform app.audit('add_relationship:' || p_kind || ':' || st, 'relationship', rid, null);
    return rid;
end $$;

create function api.respond_relationship(p_relationship uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); r relationships;
begin
    select * into r from relationships where id = p_relationship for update;
    if not found or r.status <> 'pending' or app.link_confirmer(r) is distinct from me then
        raise exception 'no pending link for you to answer' using errcode = 'P0002';
    end if;
    update relationships set status = case when p_accept then 'confirmed' else 'disputed' end::link_status,
           decided_by = me, decided_at = now()
     where id = r.id;
    perform app.audit(case when p_accept then 'confirm_relationship' else 'dispute_relationship' end,
                      'relationship', r.id, null);
end $$;

create function api.retract_relationship(p_relationship uuid) returns void
language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); r relationships;
begin
    select * into r from relationships where id = p_relationship and status <> 'retracted' for update;
    if not found or me not in (r.created_by, app.person_owner(r.from_person), app.person_owner(r.to_person)) then
        raise exception 'link not found' using errcode = 'P0002';
    end if;
    update relationships set status = 'retracted', decided_by = me, decided_at = now() where id = r.id;
    perform app.audit('retract_relationship', 'relationship', r.id, null);
end $$;

create function api.my_pending_links() returns table (
    relationship_id uuid, kind app.rel_kind, parent_label text, other_given_name text, other_surname text,
    my_record_given_name text
) language plpgsql stable security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller();
begin
    -- For each link awaiting my answer: who the other record is, and which of my records it touches.
    return query
    select r.id, r.kind, r.parent_label,
           case when app.person_owner(r.from_person) = me then pt.given_name else pf.given_name end,
           case when app.person_owner(r.from_person) = me then pt.surname else pf.surname end,
           case when app.person_owner(r.from_person) = me then pf.given_name else pt.given_name end
    from relationships r
    join persons pf on pf.id = r.from_person
    join persons pt on pt.id = r.to_person
    where r.status = 'pending' and app.link_confirmer(r) = me;
end $$;

-- ------------------------------------------------------------------ family view

create function api.family_tree(p_root uuid default null, p_depth int default 3) returns table (
    person_id uuid, member_code text, given_name text, surname text, birth_year int, death_year int,
    is_living boolean, path text, unconfirmed boolean, is_private boolean
) language plpgsql stable security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); root uuid := coalesce(p_root, app.my_person(me));
begin
    -- Only your own record or records you manage can be the root. No browsing other trees.
    if root is null then raise exception 'no profile yet' using errcode = 'P0002'; end if;
    perform app.require_owned_person(me, root);

    return query
    with recursive edges as (
        select r.from_person as a, r.to_person as b,
               case when r.kind = 'parent' then 'child' else 'spouse' end as step, r.status
        from relationships r
        where r.status in ('self_reported', 'confirmed')
           or (r.status = 'pending' and me in (r.created_by, app.link_confirmer(r)))
        union all
        select r.to_person, r.from_person,
               case when r.kind = 'parent' then 'parent' else 'spouse' end, r.status
        from relationships r
        where r.status in ('self_reported', 'confirmed')
           or (r.status = 'pending' and me in (r.created_by, app.link_confirmer(r)))
    ),
    walk(pid, depth, visited, route, pend) as (
        select root, 0, array[root], ''::text, false
        union all
        select e.b, w.depth + 1, w.visited || e.b,
               w.route || case when w.route = '' then '' else '>' end || e.step,
               w.pend or e.status = 'pending'
        from walk w join edges e on e.a = w.pid
        where w.depth < least(greatest(p_depth, 1), 4) and not e.b = any(w.visited)
    ),
    best as (
        select distinct on (w.pid) w.pid, w.route, w.pend
        from walk w order by w.pid, w.pend, w.depth
    )
    select p.id,
           case when v.ok then p.member_code end,
           case when v.ok then p.given_name end,
           case when v.ok then p.surname end,
           case when v.ok then p.birth_year end,
           case when v.ok then p.death_year end,
           case when v.ok then p.is_living end,
           b.route, b.pend, not v.ok
    from best b
    join persons p on p.id = b.pid and p.merged_into is null
    cross join lateral (select app.can_see_person(me, p.id, b.pend) as ok) v
    order by length(b.route), b.route;
end $$;

-- ------------------------------------------------------------------ households and residences

create function api.create_household() returns uuid
language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); pid uuid := app.my_person(me); hid uuid;
begin
    if pid is null then raise exception 'no profile yet' using errcode = 'P0002'; end if;
    insert into households (created_by) values (me) returning id into hid;
    insert into household_members (household_id, person_id) values (hid, pid);  -- unique: one current household
    perform app.audit('create_household', 'household', hid, null);
    return hid;
end $$;

-- Adds a record you own (e.g. a child you manage) to a household you currently belong to.
-- People with their own accounts join from their own account (deferred to the app slice).
create function api.add_household_member(p_household uuid, p_person uuid) returns void
language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller();
begin
    if not exists (select 1 from household_members
                   where household_id = p_household and person_id = app.my_person(me) and left_on is null) then
        raise exception 'household not found' using errcode = 'P0002';
    end if;
    perform app.require_owned_person(me, p_person);
    insert into household_members (household_id, person_id) values (p_household, p_person);
    perform app.audit('add_household_member', 'household', p_household, null);
end $$;

create function api.leave_household(p_household uuid, p_person uuid) returns void
language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller();
begin
    perform app.require_owned_person(me, p_person);
    update household_members set left_on = current_date
     where household_id = p_household and person_id = p_person and left_on is null;
    if not found then raise exception 'not a current member' using errcode = 'P0002'; end if;
    perform app.audit('leave_household', 'household', p_household, null);
end $$;

create function api.set_current_residence(p_person uuid, p_city text, p_state text, p_country text, p_from_year int)
returns void language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller();
begin
    perform app.require_owned_person(me, p_person);
    update residences set is_current = false, to_year = coalesce(to_year, coalesce(p_from_year, app.this_year()))
     where person_id = p_person and is_current;
    insert into residences (person_id, city, state, country, from_year) values (p_person, p_city, p_state, p_country, p_from_year);
    update persons set present_city = p_city, present_country = p_country where id = p_person;
    perform app.audit('set_residence', 'person', p_person, null);
end $$;

-- ------------------------------------------------------------------ claiming a record

-- The owner of a living adult's record invites that person to take it over.
-- Returns the token once; only its hash is stored. Valid 14 days, single use.
create function api.create_claim_invite(p_person uuid) returns text
language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); r persons; tok text;
begin
    r := app.require_owned_person(me, p_person);
    if exists (select 1 from account_person where person_id = p_person) then
        raise exception 'record already belongs to an account' using errcode = '55000';
    end if;
    if not r.is_living or app.is_minor(r) then
        raise exception 'only living adults can claim their record' using errcode = '55000';
    end if;
    -- 244 random bits from PostgreSQL's strong random source (no extension needed).
    tok := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
    insert into claim_invites (token_hash, person_id, created_by, expires_at)
    values (encode(sha256(convert_to(tok, 'UTF8')), 'hex'), p_person, me, now() + interval '14 days');
    perform app.audit('create_claim_invite', 'person', p_person, null);
    return tok;
end $$;

create function api.claim_person(p_token text) returns uuid
language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); ci claim_invites;
begin
    if app.my_person(me) is not null then
        raise exception 'your account already has a person record' using errcode = '55000';
    end if;
    select * into ci from claim_invites where token_hash = encode(sha256(convert_to(coalesce(p_token, ''), 'UTF8')), 'hex') for update;
    if not found or ci.used_at is not null or ci.expires_at < now() then
        raise exception 'invitation is invalid or expired' using errcode = 'P0002';
    end if;
    if exists (select 1 from account_person where person_id = ci.person_id)
       or exists (select 1 from persons where id = ci.person_id and merged_into is not null) then
        raise exception 'invitation is invalid or expired' using errcode = 'P0002';
    end if;
    update claim_invites set used_by = me, used_at = now() where token_hash = ci.token_hash;
    insert into account_person (account_id, person_id) values (me, ci.person_id);
    update persons set managed_by = null, consent_basis = 'self' where id = ci.person_id;
    -- Links others recorded about this person now need the person's own acceptance.
    update relationships set status = 'pending'
     where status = 'self_reported' and ci.person_id in (from_person, to_person);
    perform app.audit('claim_person', 'person', ci.person_id, null);
    return ci.person_id;
end $$;

-- ------------------------------------------------------------------ reviewed merges

create function api.request_merge(p_keep uuid, p_merge uuid) returns uuid
language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); k persons; m persons; diffs text[] := '{}'; mid uuid;
begin
    select * into k from persons where id = p_keep and merged_into is null;
    select * into m from persons where id = p_merge and merged_into is null;
    if k.id is null or m.id is null or me not in (app.person_owner(p_keep), app.person_owner(p_merge)) then
        raise exception 'person not found' using errcode = 'P0002';
    end if;
    if exists (select 1 from account_person where person_id = p_merge) then
        raise exception 'a record that belongs to an account cannot be merged away' using errcode = '55000';
    end if;
    if k.given_name is distinct from m.given_name then diffs := array_append(diffs, 'given_name'); end if;
    if k.surname is distinct from m.surname then diffs := array_append(diffs, 'surname'); end if;
    if k.birth_year is distinct from m.birth_year then diffs := array_append(diffs, 'birth_year'); end if;
    if k.death_year is distinct from m.death_year then diffs := array_append(diffs, 'death_year'); end if;
    if k.is_living is distinct from m.is_living then diffs := array_append(diffs, 'is_living'); end if;
    if k.ancestral_village is distinct from m.ancestral_village then diffs := array_append(diffs, 'ancestral_village'); end if;
    insert into merge_requests (keep_person, merge_person, requested_by, conflicts)
    values (p_keep, p_merge, me, diffs) returning id into mid;
    perform app.audit('request_merge', 'merge_request', mid, null, jsonb_build_object('conflict_fields', diffs));
    return mid;
end $$;

-- Reviewer: a global administrator, or the secretary of the requester's chapter.
-- Neither the requester nor the owner of either record may review.
create function api.review_merge(p_request uuid, p_approve boolean, p_acknowledge_conflicts boolean, p_note text)
returns void language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); mr merge_requests; req_chapter uuid; r relationships;
begin
    select * into mr from merge_requests where id = p_request for update;
    if not found or mr.status <> 'pending' then
        raise exception 'no pending merge request' using errcode = 'P0002';
    end if;
    select m.chapter_id into req_chapter from account_person ap join memberships m on m.person_id = ap.person_id
     where ap.account_id = mr.requested_by;
    if not (app.has_role(me, 'global_admin', null)
            or (req_chapter is not null and app.has_role(me, 'chapter_secretary', req_chapter))) then
        raise exception 'not allowed to review this merge' using errcode = '42501';
    end if;
    if me in (mr.requested_by, app.person_owner(mr.keep_person), app.person_owner(mr.merge_person)) then
        raise exception 'cannot review a merge you are party to' using errcode = '42501';
    end if;
    if coalesce(trim(p_note), '') = '' then
        raise exception 'a review note is required' using errcode = '22023';
    end if;

    if not p_approve then
        update merge_requests set status = 'rejected', reviewed_by = me, reviewed_at = now(), review_note = p_note where id = mr.id;
        perform app.audit('reject_merge', 'merge_request', mr.id, req_chapter);
        return;
    end if;
    if cardinality(mr.conflicts) > 0 and not coalesce(p_acknowledge_conflicts, false) then
        raise exception 'conflicting fields must be reviewed and acknowledged' using errcode = '22023';
    end if;
    if exists (select 1 from account_person where person_id = mr.merge_person) then
        raise exception 'a record that belongs to an account cannot be merged away' using errcode = '55000';
    end if;

    -- Move links. A link between the two records themselves makes the merge invalid.
    if exists (select 1 from relationships where status <> 'retracted'
               and ((from_person = mr.keep_person and to_person = mr.merge_person)
                 or (from_person = mr.merge_person and to_person = mr.keep_person))) then
        raise exception 'records are linked to each other; merging would relate a person to themselves' using errcode = '23514';
    end if;
    for r in select * from relationships where status <> 'retracted' and mr.merge_person in (from_person, to_person) loop
        if exists (select 1 from relationships x where x.status <> 'retracted' and x.kind = r.kind
                   and x.from_person = case when r.from_person = mr.merge_person then mr.keep_person else r.from_person end
                   and x.to_person   = case when r.to_person   = mr.merge_person then mr.keep_person else r.to_person end) then
            update relationships set status = 'retracted', decided_by = me, decided_at = now() where id = r.id;  -- duplicate
        elsif r.kind = 'spouse' then
            update relationships set
                from_person = least(case when from_person = mr.merge_person then mr.keep_person else from_person end,
                                    case when to_person = mr.merge_person then mr.keep_person else to_person end),
                to_person   = greatest(case when from_person = mr.merge_person then mr.keep_person else from_person end,
                                       case when to_person = mr.merge_person then mr.keep_person else to_person end)
             where id = r.id;
        else
            update relationships set
                from_person = case when from_person = mr.merge_person then mr.keep_person else from_person end,
                to_person   = case when to_person   = mr.merge_person then mr.keep_person else to_person end
             where id = r.id;
        end if;
    end loop;
    if app.is_ancestor(mr.keep_person, mr.keep_person) then
        raise exception 'merge would create an invalid relationship cycle' using errcode = '23514';
    end if;
    if (select count(*) from relationships where kind = 'parent' and to_person = mr.keep_person
          and parent_type = 'biological' and status not in ('retracted', 'disputed')) > 2 then
        raise exception 'merge would give more than two biological parents' using errcode = '23514';
    end if;

    -- Households and residences: the kept record wins; nothing is counted twice.
    if exists (select 1 from household_members where person_id = mr.keep_person and left_on is null) then
        update household_members set left_on = current_date where person_id = mr.merge_person and left_on is null;
    else
        update household_members set person_id = mr.keep_person where person_id = mr.merge_person and left_on is null;
    end if;
    update residences set person_id = mr.keep_person, is_current = false where person_id = mr.merge_person;

    update persons set merged_into = mr.keep_person where id = mr.merge_person;
    update merge_requests set status = 'approved', reviewed_by = me, reviewed_at = now(), review_note = p_note where id = mr.id;
    perform app.audit('approve_merge', 'merge_request', mr.id, req_chapter);
end $$;

revoke all on all functions in schema api from public;
grant execute on all functions in schema api to bbg_api;
