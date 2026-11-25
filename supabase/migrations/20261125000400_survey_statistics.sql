-- 0004: versioned bilingual surveys and permission-aware, small-cell-suppressed statistics.
-- Brief milestone M4.
--
-- Rules
--   * Separate individual and household questionnaires; one household response per household
--     per questionnaire version, so household income is counted once.
--   * Every question is optional unless marked required; "Prefer not to disclose" is stored as
--     declined, and an unanswered question stays absent. Neither ever becomes zero.
--   * Income is a band within a currency and reporting year. Bands exist only where a method
--     has been defined; different currencies are never pooled.
--   * Survey answers need an approved membership and the person's survey consent; withdrawing
--     consent removes their responses from every statistic.
--   * Statistics return counts only. Counts from 1 to (minimum cell size - 1) are suppressed,
--     plus one extra cell when a single suppressed cell could be recovered by subtraction.
--     Country filters are refused when either the filtered group or the rest of the world is small.
-- Enum values 'survey' and 'planning_analyst' are added in 20261125000390_enum_additions.sql.


create type app.survey_scope as enum ('individual', 'household');
create type app.question_kind as enum ('single_choice', 'multi_choice', 'integer', 'year', 'income_band');
create type app.response_status as enum ('draft', 'submitted');
create type app.stat_cell as (key text, currency text, reporting_year int, n int);

create table app.settings (
    key   text primary key,
    value text not null
);
insert into app.settings values ('min_cell_size', '5');

create table app.survey_versions (
    id           uuid primary key default gen_random_uuid(),
    scope        app.survey_scope not null,
    version      int not null check (version > 0),
    title_en     text not null,
    title_gu     text not null,
    published_at timestamptz,
    retired_at   timestamptz,
    unique (scope, version)
);

create table app.survey_questions (
    id          uuid primary key default gen_random_uuid(),
    version_id  uuid not null references app.survey_versions(id),
    code        text not null check (code ~ '^[a-z][a-z0-9_]*$'),
    position    int not null,
    kind        app.question_kind not null,
    prompt_en   text not null,
    prompt_gu   text not null,
    required    boolean not null default false,
    sensitive   boolean not null default false,       -- shown only to planning users in statistics
    min_value   int,
    max_value   int,
    unique (version_id, code),
    unique (version_id, position)
);

create table app.survey_options (
    question_id uuid not null references app.survey_questions(id),
    code        text not null check (code ~ '^[a-z][a-z0-9_]*$'),
    position    int not null,
    label_en    text not null,
    label_gu    text not null,
    primary key (question_id, code)
);

create table app.income_bands (
    currency       text not null check (currency ~ '^[A-Z]{3}$'),
    reporting_year int not null check (reporting_year between 2000 and 2100),
    code           text not null check (code ~ '^[a-z][a-z0-9_]*$'),
    position       int not null,
    lower_amount   numeric,           -- annual household income, inclusive
    upper_amount   numeric,           -- exclusive; null = no upper limit
    label_en       text not null,
    label_gu       text not null,
    method         text not null,     -- how these bands were chosen (brief: explicit method required)
    primary key (currency, reporting_year, code),
    check (upper_amount is null or lower_amount is null or upper_amount > lower_amount)
);

create table app.survey_responses (
    id                uuid primary key default gen_random_uuid(),
    version_id        uuid not null references app.survey_versions(id),
    scope             app.survey_scope not null,
    subject_person    uuid references app.persons(id),
    subject_household uuid references app.households(id),
    submitted_by      uuid not null references app.accounts(id),
    status            app.response_status not null default 'draft',
    is_verified       boolean not null default false,   -- self-reported unless later verified
    currency          text check (currency ~ '^[A-Z]{3}$'),
    reporting_year    int check (reporting_year between 2000 and 2100),
    started_at        timestamptz not null default now(),
    submitted_at      timestamptz,
    check ((scope = 'individual') = (subject_person is not null)),
    check ((scope = 'household') = (subject_household is not null)),
    check ((status = 'submitted') = (submitted_at is not null))
);
create unique index one_response_per_person_version on app.survey_responses (version_id, subject_person)
    where subject_person is not null;
create unique index one_response_per_household_version on app.survey_responses (version_id, subject_household)
    where subject_household is not null;

create table app.survey_answers (
    response_id   uuid not null references app.survey_responses(id) on delete cascade,
    question_id   uuid not null references app.survey_questions(id),
    declined      boolean not null default false,
    option_codes  text[],
    value_int     int,
    answered_at   timestamptz not null default now(),
    primary key (response_id, question_id),
    check (not declined or (option_codes is null and value_int is null)),
    check (declined or option_codes is not null or value_int is not null)
);

-- ------------------------------------------------------------------ seed: questionnaire v1

do $$
declare iv uuid; hv uuid; q uuid;
begin
    insert into app.survey_versions (scope, version, title_en, title_gu, published_at)
    values ('individual', 1, 'Individual survey', 'વ્યક્તિગત સર્વેક્ષણ', now()) returning id into iv;
    insert into app.survey_versions (scope, version, title_en, title_gu, published_at)
    values ('household', 1, 'Household survey', 'કુટુંબ સર્વેક્ષણ', now()) returning id into hv;

    insert into app.survey_questions (version_id, code, position, kind, prompt_en, prompt_gu)
    values (iv, 'education_level', 1, 'single_choice', 'Highest education completed', 'પૂર્ણ કરેલું સર્વોચ્ચ શિક્ષણ') returning id into q;
    insert into app.survey_options values
      (q, 'below_secondary', 1, 'Below secondary', 'માધ્યમિકથી ઓછું'),
      (q, 'secondary', 2, 'Secondary (10th/12th)', 'માધ્યમિક (૧૦/૧૨)'),
      (q, 'diploma', 3, 'Diploma / vocational', 'ડિપ્લોમા / વ્યાવસાયિક'),
      (q, 'graduate', 4, 'Graduate', 'સ્નાતક'),
      (q, 'postgraduate', 5, 'Postgraduate or higher', 'અનુસ્નાતક કે તેથી વધુ');

    insert into app.survey_questions (version_id, code, position, kind, prompt_en, prompt_gu)
    values (iv, 'currently_studying', 2, 'single_choice', 'Currently studying?', 'હાલ અભ્યાસ કરો છો?') returning id into q;
    insert into app.survey_options values (q, 'yes', 1, 'Yes', 'હા'), (q, 'no', 2, 'No', 'ના');

    insert into app.survey_questions (version_id, code, position, kind, prompt_en, prompt_gu)
    values (iv, 'employment_status', 3, 'single_choice', 'Work status', 'કામની સ્થિતિ') returning id into q;
    insert into app.survey_options values
      (q, 'employed', 1, 'Employed', 'નોકરી'),
      (q, 'self_employed', 2, 'Self-employed / business', 'સ્વરોજગાર / વ્યવસાય'),
      (q, 'seeking_work', 3, 'Looking for work', 'કામની શોધમાં'),
      (q, 'student', 4, 'Student', 'વિદ્યાર્થી'),
      (q, 'homemaker', 5, 'Homemaker', 'ગૃહિણી / ગૃહસ્થ'),
      (q, 'retired', 6, 'Retired', 'નિવૃત્ત'),
      (q, 'other', 7, 'Other', 'અન્ય');

    insert into app.survey_questions (version_id, code, position, kind, prompt_en, prompt_gu)
    values (iv, 'occupation_sector', 4, 'single_choice', 'Main field of work', 'મુખ્ય કાર્યક્ષેત્ર') returning id into q;
    insert into app.survey_options values
      (q, 'agriculture', 1, 'Agriculture', 'ખેતી'),
      (q, 'manufacturing', 2, 'Manufacturing / trades', 'ઉત્પાદન / કારીગરી'),
      (q, 'business_trade', 3, 'Business / trade', 'વેપાર'),
      (q, 'education', 4, 'Education', 'શિક્ષણ'),
      (q, 'health', 5, 'Health', 'આરોગ્ય'),
      (q, 'it_engineering', 6, 'IT / engineering', 'આઇટી / ઇજનેરી'),
      (q, 'government', 7, 'Government service', 'સરકારી સેવા'),
      (q, 'religious_service', 8, 'Religious / priestly service', 'ધાર્મિક / પૂજા સેવા'),
      (q, 'other', 9, 'Other', 'અન્ય');

    insert into app.survey_questions (version_id, code, position, kind, prompt_en, prompt_gu, min_value, max_value)
    values (iv, 'migration_year', 5, 'year', 'Year you moved to your present country (if you moved)',
            'હાલના દેશમાં આવ્યાનું વર્ષ (જો સ્થળાંતર કર્યું હોય)', 1940, null);

    insert into app.survey_questions (version_id, code, position, kind, prompt_en, prompt_gu)
    values (iv, 'volunteer_interest', 6, 'multi_choice', 'Would you help with', 'આમાં મદદ કરશો?') returning id into q;
    insert into app.survey_options values
      (q, 'mentoring', 1, 'Mentoring students', 'વિદ્યાર્થી માર્ગદર્શન'),
      (q, 'career_guidance', 2, 'Career guidance', 'કારકિર્દી માર્ગદર્શન'),
      (q, 'events', 3, 'Organising events', 'કાર્યક્રમ આયોજન'),
      (q, 'surveys', 4, 'Helping with surveys', 'સર્વેક્ષણમાં મદદ');

    insert into app.survey_questions (version_id, code, position, kind, prompt_en, prompt_gu, required, min_value, max_value)
    values (hv, 'household_size', 1, 'integer', 'People living in your household', 'તમારા ઘરમાં રહેતા સભ્યો', true, 1, 30);
    insert into app.survey_questions (version_id, code, position, kind, prompt_en, prompt_gu, min_value, max_value)
    values (hv, 'earning_members', 2, 'integer', 'Earning members', 'કમાતા સભ્યો', 0, 30);
    insert into app.survey_questions (version_id, code, position, kind, prompt_en, prompt_gu, sensitive)
    values (hv, 'income_band', 3, 'income_band', 'Annual household income (band)', 'કુટુંબની વાર્ષિક આવક (શ્રેણી)', true);
    insert into app.survey_questions (version_id, code, position, kind, prompt_en, prompt_gu, sensitive)
    values (hv, 'housing', 4, 'single_choice', 'Home', 'રહેઠાણ', true) returning id into q;
    insert into app.survey_options values
      (q, 'owned', 1, 'Owned', 'પોતાનું'), (q, 'rented', 2, 'Rented', 'ભાડાનું'), (q, 'other', 3, 'Other', 'અન્ય');
    insert into app.survey_questions (version_id, code, position, kind, prompt_en, prompt_gu, sensitive)
    values (hv, 'support_needs', 5, 'multi_choice', 'Support your household would welcome', 'કુટુંબને કઈ સહાય ઉપયોગી થાય', true) returning id into q;
    insert into app.survey_options values
      (q, 'education', 1, 'Education', 'શિક્ષણ'),
      (q, 'career', 2, 'Career / jobs', 'કારકિર્દી / નોકરી'),
      (q, 'senior_care', 3, 'Senior care', 'વડીલ સંભાળ'),
      (q, 'emergency', 4, 'Emergency help', 'કટોકટી સહાય'),
      (q, 'none', 5, 'None at present', 'હાલ કોઈ નહીં');
end $$;

-- Proposed INR bands for owner approval. Other currencies have no bands until a method is agreed.
insert into app.income_bands values
 ('INR', 2026, 'inr_lt_3l',   1, 0,       300000,  'Below ₹3 lakh',     '₹૩ લાખથી ઓછી', 'PROPOSED, pending owner approval: round lakh boundaries'),
 ('INR', 2026, 'inr_3_6l',    2, 300000,  600000,  '₹3–6 lakh',         '₹૩–૬ લાખ',      'PROPOSED, pending owner approval: round lakh boundaries'),
 ('INR', 2026, 'inr_6_12l',   3, 600000,  1200000, '₹6–12 lakh',        '₹૬–૧૨ લાખ',     'PROPOSED, pending owner approval: round lakh boundaries'),
 ('INR', 2026, 'inr_12_24l',  4, 1200000, 2400000, '₹12–24 lakh',       '₹૧૨–૨૪ લાખ',    'PROPOSED, pending owner approval: round lakh boundaries'),
 ('INR', 2026, 'inr_ge_24l',  5, 2400000, null,    '₹24 lakh or more',  '₹૨૪ લાખ કે વધુ', 'PROPOSED, pending owner approval: round lakh boundaries');

-- ------------------------------------------------------------------ helpers

create function app.min_cell() returns int language sql stable as $$
    select value::int from app.settings where key = 'min_cell_size'
$$;

create function app.has_consent(p uuid, purpose app.consent_purpose) returns boolean language sql stable as $$
    select coalesce((select granted from app.consents c where c.person_id = p and c.purpose = $2), false)
$$;

create function app.require_survey_participant(me uuid) returns uuid language plpgsql stable as $$
declare pid uuid := app.my_person(me);
begin
    if pid is null or not app.is_approved_member(me) then
        raise exception 'surveys are open to approved members only' using errcode = '42501';
    end if;
    if not app.has_consent(pid, 'survey') then
        raise exception 'survey consent has not been given' using errcode = '42501';
    end if;
    return pid;
end $$;

create function app.is_planner(me uuid) returns boolean language sql stable as $$
    select app.has_role(me, 'global_admin', null)
        or exists (select 1 from app.role_assignments r join app.chapters c on c.id = r.chapter_id
                   where r.account_id = me and r.role = 'planning_analyst' and r.revoked_at is null and c.level = 'global')
$$;

create function app.current_version(p_scope app.survey_scope) returns uuid language sql stable as $$
    select id from app.survey_versions where scope = p_scope and published_at is not null and retired_at is null
    order by version desc limit 1
$$;

-- Applies small-cell suppression and complementary suppression. Zero stays zero.
create function app.suppress(cells app.stat_cell[], k int)
returns table (key text, currency text, reporting_year int, n int, suppressed boolean)
language plpgsql immutable as $$
declare
    flags boolean[];
    i int; small_count int := 0; pick int; pick_n int;
begin
    flags := array_fill(false, array[coalesce(array_length(cells, 1), 0)]);
    for i in 1 .. coalesce(array_length(cells, 1), 0) loop
        if (cells[i]).n between 1 and k - 1 then
            flags[i] := true; small_count := small_count + 1;
        end if;
    end loop;
    -- A lone suppressed cell can be recovered as (total - others): hide the next smallest too.
    if small_count = 1 then
        pick := null;
        for i in 1 .. array_length(cells, 1) loop
            if not flags[i] and (cells[i]).n > 0 and (pick is null or (cells[i]).n < pick_n) then
                pick := i; pick_n := (cells[i]).n;
            end if;
        end loop;
        if pick is not null then flags[pick] := true; end if;
    end if;
    for i in 1 .. coalesce(array_length(cells, 1), 0) loop
        key := (cells[i]).key; currency := (cells[i]).currency; reporting_year := (cells[i]).reporting_year;
        suppressed := flags[i];
        n := case when flags[i] then null else (cells[i]).n end;
        return next;
    end loop;
end $$;

revoke all on all functions in schema app from public;

-- ------------------------------------------------------------------ questionnaire API

create function api.survey_questions(p_scope app.survey_scope) returns table (
    version int, question_code text, question_position int, kind app.question_kind, prompt_en text, prompt_gu text,
    required boolean, min_value int, max_value int, options jsonb
) language plpgsql stable security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller();
begin
    return query
    select v.version, q.code, q.position, q.kind, q.prompt_en, q.prompt_gu, q.required, q.min_value, q.max_value,
           coalesce((select jsonb_agg(jsonb_build_object('code', o.code, 'en', o.label_en, 'gu', o.label_gu) order by o.position)
                     from survey_options o where o.question_id = q.id), '[]'::jsonb)
    from survey_versions v join survey_questions q on q.version_id = v.id
    where v.id = app.current_version(p_scope)
    order by q.position;
end $$;

create function api.income_bands(p_currency text, p_reporting_year int) returns table (
    code text, label_en text, label_gu text, method text
) language plpgsql stable security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller();
begin
    return query select b.code, b.label_en, b.label_gu, b.method from income_bands b
    where b.currency = upper(p_currency) and b.reporting_year = p_reporting_year order by b.position;
end $$;

-- Starts (or returns the existing) response for the current version.
create function api.start_survey(p_scope app.survey_scope) returns uuid
language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); pid uuid := app.require_survey_participant(me);
        v uuid := app.current_version(p_scope); hid uuid; rid uuid;
begin
    if p_scope = 'individual' then
        select id into rid from survey_responses where version_id = v and subject_person = pid;
        if rid is not null then return rid; end if;
        insert into survey_responses (version_id, scope, subject_person, submitted_by)
        values (v, 'individual', pid, me) returning id into rid;
    else
        select household_id into hid from household_members where person_id = pid and left_on is null;
        if hid is null then
            raise exception 'join or create a household first' using errcode = '55000';
        end if;
        select id into rid from survey_responses where version_id = v and subject_household = hid;
        if rid is not null then
            -- One household response; another member may not open a second one.
            if (select submitted_by from survey_responses where id = rid) <> me then
                raise exception 'another household member has already started this survey' using errcode = '23505';
            end if;
            return rid;
        end if;
        insert into survey_responses (version_id, scope, subject_household, submitted_by)
        values (v, 'household', hid, me) returning id into rid;
    end if;
    perform app.audit('start_survey:' || p_scope, 'survey_response', rid, null);
    return rid;
end $$;

create function api.save_answer(p_response uuid, p_question_code text, p_declined boolean,
                                p_option_codes text[], p_value_int int) returns void
language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); r survey_responses; q survey_questions; bad text;
begin
    perform app.require_survey_participant(me);
    select * into r from survey_responses where id = p_response for update;
    if not found or r.submitted_by <> me then
        raise exception 'response not found' using errcode = 'P0002';
    end if;
    if r.status <> 'draft' then
        raise exception 'submitted responses cannot be changed' using errcode = '55000';
    end if;
    select * into q from survey_questions where version_id = r.version_id and code = p_question_code;
    if not found then
        raise exception 'unknown question' using errcode = '22023';
    end if;

    if coalesce(p_declined, false) then
        p_option_codes := null; p_value_int := null;
    elsif q.kind in ('single_choice', 'multi_choice') then
        if p_value_int is not null or coalesce(cardinality(p_option_codes), 0) = 0
           or (q.kind = 'single_choice' and cardinality(p_option_codes) <> 1) then
            raise exception 'invalid answer for this question' using errcode = '22023';
        end if;
        select c into bad from unnest(p_option_codes) c
         where not exists (select 1 from survey_options o where o.question_id = q.id and o.code = c) limit 1;
        if bad is not null or cardinality(p_option_codes) <> (select count(distinct c) from unnest(p_option_codes) c) then
            raise exception 'invalid option' using errcode = '22023';
        end if;
    elsif q.kind = 'income_band' then
        -- Band validity depends on the response's currency and year; checked at submission.
        if p_value_int is not null or coalesce(cardinality(p_option_codes), 0) <> 1 then
            raise exception 'invalid answer for this question' using errcode = '22023';
        end if;
    else  -- integer, year
        if p_option_codes is not null or p_value_int is null
           or (q.min_value is not null and p_value_int < q.min_value)
           or (q.max_value is not null and p_value_int > q.max_value)
           or (q.kind = 'year' and p_value_int > app.this_year()) then
            raise exception 'value out of range' using errcode = '22023';
        end if;
    end if;

    insert into survey_answers (response_id, question_id, declined, option_codes, value_int)
    values (r.id, q.id, coalesce(p_declined, false), p_option_codes, p_value_int)
    on conflict (response_id, question_id) do update
        set declined = excluded.declined, option_codes = excluded.option_codes,
            value_int = excluded.value_int, answered_at = now();
end $$;

create function api.clear_answer(p_response uuid, p_question_code text) returns void
language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); r survey_responses;
begin
    select * into r from survey_responses where id = p_response;
    if not found or r.submitted_by <> me then raise exception 'response not found' using errcode = 'P0002'; end if;
    if r.status <> 'draft' then raise exception 'submitted responses cannot be changed' using errcode = '55000'; end if;
    delete from survey_answers a using survey_questions q
     where a.response_id = r.id and q.id = a.question_id and q.code = p_question_code;
end $$;

create function api.submit_survey(p_response uuid, p_currency text, p_reporting_year int) returns void
language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); r survey_responses; inc survey_answers;
begin
    perform app.require_survey_participant(me);
    select * into r from survey_responses where id = p_response for update;
    if not found or r.submitted_by <> me then raise exception 'response not found' using errcode = 'P0002'; end if;
    if r.status <> 'draft' then raise exception 'already submitted' using errcode = '55000'; end if;
    if exists (select 1 from survey_questions q where q.version_id = r.version_id and q.required
               and not exists (select 1 from survey_answers a where a.response_id = r.id and a.question_id = q.id)) then
        raise exception 'required questions are unanswered' using errcode = '22023';
    end if;

    select a.* into inc from survey_answers a join survey_questions q on q.id = a.question_id
     where a.response_id = r.id and q.kind = 'income_band';
    if inc.response_id is not null and not inc.declined then
        if p_currency is null or p_reporting_year is null then
            raise exception 'currency and reporting year are required with an income answer' using errcode = '22023';
        end if;
        if not exists (select 1 from income_bands b where b.currency = upper(p_currency)
                       and b.reporting_year = p_reporting_year and b.code = inc.option_codes[1]) then
            raise exception 'no such income band for that currency and year' using errcode = '22023';
        end if;
    end if;

    update survey_responses set status = 'submitted', submitted_at = now(),
           currency = upper(p_currency), reporting_year = p_reporting_year
     where id = r.id;
    perform app.audit('submit_survey:' || r.scope, 'survey_response', r.id, null);
end $$;

-- Right to withdraw: deletes the caller's response and its answers.
create function api.delete_my_response(p_response uuid) returns void
language plpgsql security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller();
begin
    delete from survey_responses where id = p_response and submitted_by = me;
    if not found then raise exception 'response not found' using errcode = 'P0002'; end if;
    perform app.audit('delete_survey_response', 'survey_response', p_response, null);
end $$;

-- ------------------------------------------------------------------ statistics API

-- Headline counts. Each is a different population; none is a census.
create function api.stats_overview() returns table (
    measure text, n int, suppressed boolean, as_of timestamptz
) language plpgsql stable security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller(); k int := app.min_cell(); cells stat_cell[];
begin
    if not app.is_approved_member(me) then
        raise exception 'statistics are available to approved members only' using errcode = '42501';
    end if;
    cells := array[
        row('registered_accounts', null, null, (select count(*) from accounts where status = 'active'))::stat_cell,
        row('approved_members', null, null, (select count(*) from memberships where status = 'approved'))::stat_cell,
        row('person_records', null, null, (select count(*) from persons where merged_into is null))::stat_cell,
        row('households_recorded', null, null,
            (select count(distinct household_id) from household_members where left_on is null))::stat_cell,
        row('surveyed_individuals', null, null, (
            select count(*) from survey_responses r where r.status = 'submitted' and r.scope = 'individual'
               and r.version_id = app.current_version('individual') and app.has_consent(r.subject_person, 'survey')))::stat_cell,
        row('surveyed_households', null, null, (
            select count(*) from survey_responses r where r.status = 'submitted' and r.scope = 'household'
               and r.version_id = app.current_version('household')
               and app.has_consent(app.my_person(r.submitted_by), 'survey')))::stat_cell,
        row('pending_duplicate_reviews', null, null, (select count(*) from merge_requests where status = 'pending'))::stat_cell
    ];
    -- Headline totals are independent populations, so only small-cell suppression applies.
    return query
    select c.key, case when c.n between 1 and k - 1 then null else c.n end, c.n between 1 and k - 1, now()
    from unnest(cells) c;
end $$;

-- One breakdown at a time. Members: member_country, age_group, education_level, employment_status,
-- household_size. Planning users additionally: income_band, housing, support_needs.
-- Every row set includes 'declined' and 'not_answered' so totals reconcile with the denominator.
create function api.stats_breakdown(p_dimension text, p_country text default null) returns table (
    group_key text, currency text, reporting_year int, n int, suppressed boolean, denominator int, as_of timestamptz
) language plpgsql security definer set search_path = app, pg_temp as $$
declare
    me uuid := app.require_verified_caller(); k int := app.min_cell();
    cells stat_cell[]; total int; whole int; ctry text := upper(nullif(trim(p_country), ''));
    planner_only text[] := array['income_band', 'housing', 'support_needs'];
    member_dims text[] := array['member_country', 'age_group', 'education_level', 'employment_status', 'household_size'];
    iv uuid := app.current_version('individual'); hv uuid := app.current_version('household');
begin
    if not app.is_approved_member(me) and not app.is_planner(me) then
        raise exception 'statistics are available to approved members only' using errcode = '42501';
    end if;
    if p_dimension = any(planner_only) then
        if not app.is_planner(me) then
            raise exception 'this breakdown is limited to planning users' using errcode = '42501';
        end if;
    elsif not p_dimension = any(member_dims) then
        raise exception 'unknown breakdown' using errcode = '22023';
    end if;
    if p_dimension = 'member_country' and ctry is not null then
        raise exception 'country filter does not apply to the country breakdown' using errcode = '22023';
    end if;

    -- Population for this breakdown, then cells.
    create temp table if not exists pg_temp.stat_pop (subject uuid, response uuid, country text) on commit drop;
    truncate pg_temp.stat_pop;
    if p_dimension in ('member_country', 'age_group') then
        insert into pg_temp.stat_pop
        select p.id, null, p.present_country from memberships m join persons p on p.id = m.person_id
        where m.status = 'approved';
    elsif p_dimension in ('education_level', 'employment_status') then
        insert into pg_temp.stat_pop
        select r.subject_person, r.id, p.present_country from survey_responses r join persons p on p.id = r.subject_person
        where r.version_id = iv and r.status = 'submitted' and app.has_consent(r.subject_person, 'survey');
    else
        insert into pg_temp.stat_pop
        select r.subject_household, r.id, p.present_country
        from survey_responses r join persons p on p.id = app.my_person(r.submitted_by)
        where r.version_id = hv and r.status = 'submitted' and app.has_consent(p.id, 'survey');
    end if;

    select count(*) into whole from pg_temp.stat_pop;
    if ctry is not null then
        delete from pg_temp.stat_pop where country is distinct from ctry;
    end if;
    select count(*) into total from pg_temp.stat_pop;

    -- Refuse filters that isolate a small group, directly or by subtraction from the world total.
    if ctry is not null and (total between 1 and k - 1 or (whole - total) between 1 and k - 1) then
        return query select null::text, null::text, null::int, null::int, true, null::int, now();
        return;
    end if;

    if p_dimension = 'member_country' then
        select array_agg(row(coalesce(country, 'unknown'), null, null, c)::stat_cell) into cells
        from (select country, count(*)::int c from pg_temp.stat_pop group by country) x;
    elsif p_dimension = 'age_group' then
        select array_agg(row(g, null, null, c)::stat_cell) into cells from (
            select case when p.birth_year is null then 'unknown'
                        when app.this_year() - p.birth_year < 18 then 'under_18'
                        when app.this_year() - p.birth_year < 30 then '18_29'
                        when app.this_year() - p.birth_year < 45 then '30_44'
                        when app.this_year() - p.birth_year < 60 then '45_59'
                        else '60_plus' end g, count(*)::int c
            from pg_temp.stat_pop s join persons p on p.id = s.subject group by 1) x;
    elsif p_dimension = 'household_size' then
        select array_agg(row(g, null, null, c)::stat_cell) into cells from (
            select case when a.response_id is null then 'not_answered'
                        when a.declined then 'declined'
                        when a.value_int <= 2 then '1_2'
                        when a.value_int <= 4 then '3_4'
                        when a.value_int <= 6 then '5_6'
                        else '7_plus' end g, count(*)::int c
            from pg_temp.stat_pop s
            left join survey_answers a on a.response_id = s.response
                 and a.question_id = (select id from survey_questions where version_id = hv and code = 'household_size')
            group by 1) x;
    elsif p_dimension = 'income_band' then
        -- Bands are reported within their own currency and reporting year; never pooled.
        select array_agg(row(g, cur, yr, c)::stat_cell) into cells from (
            select case when a.response_id is null then 'not_answered'
                        when a.declined then 'declined' else a.option_codes[1] end g,
                   case when a.response_id is not null and not a.declined then r.currency end cur,
                   case when a.response_id is not null and not a.declined then r.reporting_year end yr,
                   count(*)::int c
            from pg_temp.stat_pop s join survey_responses r on r.id = s.response
            left join survey_answers a on a.response_id = s.response
                 and a.question_id = (select id from survey_questions where version_id = hv and code = 'income_band')
            group by 1, 2, 3) x;
    elsif p_dimension = 'support_needs' then
        -- Multi-choice: a household can count in several needs; declined/not_answered once each.
        select array_agg(row(g, null, null, c)::stat_cell) into cells from (
            select g, count(*)::int c from (
                select case when a.response_id is null then 'not_answered' when a.declined then 'declined' end g
                from pg_temp.stat_pop s
                left join survey_answers a on a.response_id = s.response
                     and a.question_id = (select id from survey_questions where version_id = hv and code = 'support_needs')
                where a.response_id is null or a.declined
                union all
                select unnest(a.option_codes)
                from pg_temp.stat_pop s
                join survey_answers a on a.response_id = s.response and not a.declined
                     and a.question_id = (select id from survey_questions where version_id = hv and code = 'support_needs')
            ) y group by g) x;
    else  -- single-choice survey questions: education_level, employment_status, housing
        select array_agg(row(g, null, null, c)::stat_cell) into cells from (
            select case when a.response_id is null then 'not_answered'
                        when a.declined then 'declined' else a.option_codes[1] end g, count(*)::int c
            from pg_temp.stat_pop s
            left join survey_answers a on a.response_id = s.response
                 and a.question_id = (select q.id from survey_questions q
                                      where q.version_id = case when p_dimension = 'housing' then hv else iv end
                                        and q.code = p_dimension)
            group by 1) x;
    end if;

    return query
    select sx.key, sx.currency, sx.reporting_year, sx.n, sx.suppressed,
           case when total between 1 and k - 1 then null else total end, now()
    from app.suppress(coalesce(cells, '{}'), k) sx
    order by sx.currency nulls first, sx.key;
end $$;

revoke all on all functions in schema api from public;
grant execute on all functions in schema api to bbg_api;
