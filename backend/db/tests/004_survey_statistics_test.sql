-- Tests for migration 0004 (brief M4): household totals reconcile, missing answers never become
-- zeros, currency and reporting year retained, filters do not reveal small groups,
-- versioned bilingual questionnaires, consent. Synthetic population: 12 IN, 6 GB, 1 KE members.
\set ON_ERROR_STOP on
set client_min_messages = warning;
\o /dev/null

\ir _harness.sql

create function t.cell(p_dim text, p_key text, p_country text default null) returns int language sql as $$
    select n from api.stats_breakdown(p_dim, p_country) where group_key = p_key $$;
create function t.cell_hidden(p_dim text, p_key text, p_country text default null) returns boolean language sql as $$
    select suppressed from api.stats_breakdown(p_dim, p_country) where group_key = p_key $$;
create function t.overview(p_measure text) returns int language sql as $$
    select n from api.stats_overview() where measure = p_measure $$;
create function t.m(i int) returns text language sql immutable as $$ select 'm' || lpad(i::text, 2, '0') $$;
grant execute on all functions in schema t to bbg_api;

-- ---------------------------------------------------------------- fixtures (operator)
insert into t.ids select 'admin',    app.upsert_account('s-admin', 'admin@example.test', true);
insert into t.ids select 'sec',      app.upsert_account('s-sec',   'sec@example.test',   true);
insert into t.ids select 'planner',  app.upsert_account('s-plan',  'plan@example.test',  true);
insert into t.ids select 'outsider', app.upsert_account('s-out',   'out@example.test',   true);
insert into t.ids select t.m(i), app.upsert_account('s-' || t.m(i), t.m(i) || '@example.test', true) from generate_series(1, 19) i;

insert into app.chapters (id, parent_id, level, name_en, name_gu, accepts_applications) values
 ('00000000-0000-0000-0000-0000000000a0', null, 'global', 'Global', 'વૈશ્વિક', false);
insert into app.chapters (id, parent_id, level, name_en, name_gu, country_code) values
 ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'country', 'India', 'ભારત', 'IN'),
 ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a0', 'country', 'United Kingdom', 'યુનાઇટેડ કિંગડમ', 'GB'),
 ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000a0', 'country', 'Kenya', 'કેન્યા', 'KE');
insert into t.ids values ('ch_g', '00000000-0000-0000-0000-0000000000a0'), ('ch_in', '00000000-0000-0000-0000-0000000000a1'),
                         ('ch_gb', '00000000-0000-0000-0000-0000000000b1'), ('ch_ke', '00000000-0000-0000-0000-0000000000c1');
select app.bootstrap_global_admin('admin@example.test');

set role bbg_api;
select t.as_user('admin');
select api.grant_role(t.id('sec'), 'chapter_secretary', t.id(c)) from unnest(array['ch_in', 'ch_gb', 'ch_ke']) c;
select api.grant_role(t.id('planner'), 'planning_analyst', t.id('ch_g'));

do $$
declare i int; ctry text; ch text; aid uuid;
begin
    for i in 1 .. 19 loop
        ctry := case when i <= 12 then 'IN' when i <= 18 then 'GB' else 'KE' end;
        ch := case ctry when 'IN' then 'ch_in' when 'GB' then 'ch_gb' else 'ch_ke' end;
        perform t.as_user(t.m(i));
        aid := api.submit_application(t.id(ch), 'Name' || i, 'Survey', 1950 + i * 3, 'Gam', 'City', ctry);
        perform t.as_user('sec');
        perform api.review_application(aid, 'approved', null);
    end loop;
end $$;

-- ---------------------------------------------------------------- questionnaire and consent
select t.as_user('m01');
select t.ok('individual and household questionnaires are separate and versioned',
    (select count(*) > 0 and bool_and(version = 1) from api.survey_questions('individual'))
    and exists (select 1 from api.survey_questions('household') where question_code = 'income_band'));
select t.ok('every question and option is bilingual (Gujarati script present)',
    (select bool_and(prompt_gu ~ '[઀-૿]' and prompt_en <> '') from api.survey_questions('individual'))
    and (select bool_and(o->>'gu' ~ '[઀-૿]') from api.survey_questions('household'), jsonb_array_elements(options) o));
select t.ok('income question is optional; household size is required',
    (select not required from api.survey_questions('household') where question_code = 'income_band')
    and (select required from api.survey_questions('household') where question_code = 'household_size'));
select t.ok('no Aadhaar, bank, exact-income or DNA questions exist',
    not exists (select 1 from api.survey_questions('individual') where question_code ~* '(aadhaar|bank|account_no|exact_income|dna)')
    and not exists (select 1 from api.survey_questions('household') where question_code ~* '(aadhaar|bank|account_no|exact_income|dna)'));
select t.ok('INR bands are labelled as proposed with their method',
    (select bool_and(method like 'PROPOSED%') and count(*) = 5 from api.income_bands('INR', 2026)));
select t.ok('no bands exist for currencies without an agreed method', (select count(*) = 0 from api.income_bands('GBP', 2026)));

select t.raises('survey needs consent first', $$select api.start_survey('individual')$$, '42501');
select t.as_user('outsider');
select t.raises('non-members cannot take the survey', $$select api.start_survey('individual')$$, '42501');

do $$ declare i int; begin
    for i in 1 .. 19 loop perform t.as_user(t.m(i)); perform api.set_consent('survey', true); end loop;
end $$;

-- ---------------------------------------------------------------- individual answers
select t.as_user('m01');
insert into t.ids select 'r_m01', api.start_survey('individual');
select t.ok('starting again returns the same response', api.start_survey('individual') = t.id('r_m01'));
select t.raises('unknown option rejected', $$select api.save_answer(t.id('r_m01'), 'education_level', false, array['phd_x'], null)$$, '22023');
select t.raises('single choice takes one option', $$select api.save_answer(t.id('r_m01'), 'education_level', false, array['graduate','diploma'], null)$$, '22023');
select t.raises('repeated option rejected', $$select api.save_answer(t.id('r_m01'), 'volunteer_interest', false, array['events','events'], null)$$, '22023');
select t.raises('future year rejected', $$select api.save_answer(t.id('r_m01'), 'migration_year', false, null, 2999)$$, '22023');
select t.raises('unknown question rejected', $$select api.save_answer(t.id('r_m01'), 'aadhaar_number', false, null, 1)$$, '22023');
select t.as_user('m02');
select t.raises('cannot write to someone else''s response', $$select api.save_answer(t.id('r_m01'), 'education_level', false, array['graduate'], null)$$, 'P0002');

do $$
declare i int; rid uuid; edu text;
begin
    for i in 1 .. 19 loop
        perform t.as_user(t.m(i));
        rid := api.start_survey('individual');
        edu := case when i <= 7 then 'graduate' when i <= 10 then 'postgraduate' when i = 11 then 'declined'
                    when i = 12 then null when i <= 14 then 'graduate' when i <= 18 then 'secondary' else 'postgraduate' end;
        if edu = 'declined' then
            perform api.save_answer(rid, 'education_level', true, null, null);
        elsif edu is not null then
            perform api.save_answer(rid, 'education_level', false, array[edu], null);
        end if;
        perform api.save_answer(rid, 'employment_status', false, array['employed'], null);
        perform api.submit_survey(rid, null, null);
    end loop;
end $$;

select t.as_user('m01');
select t.raises('submitted response cannot be changed', $$select api.save_answer(t.id('r_m01'), 'education_level', false, array['diploma'], null)$$, '55000');

-- ---------------------------------------------------------------- households
do $$ declare i int; begin
    for i in 1 .. 8 loop perform t.as_user(t.m(i)); perform api.create_household(); end loop;
    perform t.as_user('m13'); perform api.create_household();
end $$;
reset role;
-- m09 lives in m01's household (account holders joining is an app-slice feature; fixture insert).
insert into app.household_members (household_id, person_id)
select hm.household_id, (select person_id from app.account_person where account_id = t.id('m09'))
from app.household_members hm where hm.person_id = (select person_id from app.account_person where account_id = t.id('m01'));
set role bbg_api;

select t.as_user('m01');
insert into t.ids select 'h_m01', api.start_survey('household');
select t.raises('household size is required', $$select api.submit_survey(t.id('h_m01'), null, null)$$, '22023');
select t.raises('household size out of range', $$select api.save_answer(t.id('h_m01'), 'household_size', false, null, 0)$$, '22023');
select api.save_answer(t.id('h_m01'), 'household_size', false, null, 3);
select api.save_answer(t.id('h_m01'), 'income_band', false, array['inr_6_12l'], null);
select t.raises('income answer needs currency and year', $$select api.submit_survey(t.id('h_m01'), null, null)$$, '22023');
select t.raises('band must exist for the stated currency and year', $$select api.submit_survey(t.id('h_m01'), 'INR', 2019)$$, '22023');
select t.as_user('m09');
select t.raises('second member cannot open a second response for the same household',
    $$select api.start_survey('household')$$, '23505');

do $$
declare i int; rid uuid;
begin
    for i in 1 .. 8 loop
        perform t.as_user(t.m(i));
        rid := api.start_survey('household');
        perform api.save_answer(rid, 'household_size', false, null, 3);
        if i <= 6 then perform api.save_answer(rid, 'earning_members', false, null, 1); end if;
        if i <= 5 then
            perform api.save_answer(rid, 'income_band', false, array['inr_6_12l'], null);
            perform api.submit_survey(rid, 'inr', 2026);
        elsif i = 6 then
            perform api.save_answer(rid, 'income_band', false, array['inr_3_6l'], null);
            perform api.submit_survey(rid, 'INR', 2026);
        else
            perform api.save_answer(rid, 'income_band', true, null, null);   -- prefer not to disclose
            perform api.submit_survey(rid, null, null);
        end if;
    end loop;
end $$;

select t.as_user('m13');
insert into t.ids select 'h_m13', api.start_survey('household');
select api.save_answer(t.id('h_m13'), 'household_size', false, null, 2);
select api.save_answer(t.id('h_m13'), 'income_band', false, array['gbp_30_50k'], null);
select t.raises('currencies without agreed bands cannot record income', $$select api.submit_survey(t.id('h_m13'), 'GBP', 2026)$$, '22023');
select api.clear_answer(t.id('h_m13'), 'income_band');
select t.succeeds('household submits with income left unanswered', $$select api.submit_survey(t.id('h_m13'), null, null)$$);

reset role;
select t.ok('missing answers are absent, not stored as zero',
    not exists (select 1 from app.survey_answers a join app.survey_questions q on q.id = a.question_id
                where q.code = 'earning_members' and a.value_int = 0)
    and (select count(*) = 6 from app.survey_answers a join app.survey_questions q on q.id = a.question_id
         where q.code = 'earning_members'));
select t.ok('currency and reporting year retained on income responses (normalised to upper case)',
    (select count(*) = 6 and bool_and(currency = 'INR' and reporting_year = 2026) from app.survey_responses r
     where exists (select 1 from app.survey_answers a join app.survey_questions q on q.id = a.question_id
                   where a.response_id = r.id and q.code = 'income_band' and not a.declined)));
select t.ok('one household response per household', (select count(*) = count(distinct subject_household)
    from app.survey_responses where scope = 'household'));

-- ---------------------------------------------------------------- reconciliation (cell size 1 = no suppression)
update app.settings set value = '1' where key = 'min_cell_size';
set role bbg_api;
select t.as_user('planner');
select t.ok('income cells reconcile with surveyed households (bands + declined + not answered = total)',
    (select sum(n) = max(denominator) and max(denominator) = 9 from api.stats_breakdown('income_band')));
select t.ok('declined and not answered are reported separately, never as a zero band',
    t.cell('income_band', 'declined') = 2 and t.cell('income_band', 'not_answered') = 1);
select t.ok('income bands carry their currency and reporting year',
    (select bool_and(currency = 'INR' and reporting_year = 2026) from api.stats_breakdown('income_band')
     where group_key like 'inr_%'));
select t.ok('household income counted once per household (m09 shares m01''s household)',
    (select sum(n) from api.stats_breakdown('income_band')) = 9);
select t.ok('household size reconciles too', (select sum(n) = 9 from api.stats_breakdown('household_size')));
select t.as_user('m01');
select t.ok('education reconciles: answers + declined + not answered = respondents',
    (select sum(n) = 19 and max(denominator) = 19 from api.stats_breakdown('education_level')));
select t.ok('unanswered and declined education stay separate from real answers',
    t.cell('education_level', 'not_answered') = 1 and t.cell('education_level', 'declined') = 1
    and t.cell('education_level', 'graduate') = 9);
reset role;
update app.settings set value = '5' where key = 'min_cell_size';
set role bbg_api;

-- ---------------------------------------------------------------- suppression and permissions
select t.as_user('m01');
select t.raises('members cannot see income', $$select * from api.stats_breakdown('income_band')$$, '42501');
select t.raises('members cannot see support needs', $$select * from api.stats_breakdown('support_needs')$$, '42501');
select t.raises('unknown breakdown rejected', $$select * from api.stats_breakdown('surname')$$, '22023');
select t.ok('large cells are shown', t.cell('education_level', 'graduate') = 9);
select t.ok('cells below 5 are suppressed with no number',
    t.cell('education_level', 'secondary') is null and t.cell_hidden('education_level', 'secondary')
    and t.cell_hidden('education_level', 'declined'));
select t.ok('a lone small country is hidden and so is the next smallest (no recovery by subtraction)',
    t.cell_hidden('member_country', 'KE') and t.cell_hidden('member_country', 'GB')
    and t.cell('member_country', 'IN') = 12);
select t.ok('filtering to a tiny country returns nothing usable',
    (select count(*) = 1 and bool_and(n is null and suppressed and denominator is null)
       from api.stats_breakdown('education_level', 'KE')));
select t.ok('filtering to a country of adequate size works', (select max(denominator) = 6 from api.stats_breakdown('education_level', 'GB')));
select t.as_user('planner');
select t.ok('filter refused when the rest of the world is small (IN 8 vs 1 other household)',
    (select bool_and(n is null and suppressed) from api.stats_breakdown('household_size', 'IN')));
select t.ok('planner sees income with small bands suppressed',
    t.cell('income_band', 'inr_6_12l') = 5 and t.cell('income_band', 'inr_3_6l') is null);
select t.as_user('outsider');
select t.raises('non-members get no statistics', $$select * from api.stats_overview()$$, '42501');

select t.as_user('m01');
select t.ok('headline counts are separate measures',
    t.overview('approved_members') = 19 and t.overview('surveyed_individuals') = 19
    and t.overview('surveyed_households') = 9 and t.overview('pending_duplicate_reviews') = 0);
select t.ok('overview never pools people with households',
    (select count(*) = 7 from api.stats_overview()));

-- ---------------------------------------------------------------- consent withdrawal and deletion
select t.as_user('m12'); select api.set_consent('survey', false);
select t.raises('without consent, survey actions stop', $$select api.start_survey('individual')$$, '42501');
select t.as_user('m01');
select t.ok('withdrawn consent removes the response from statistics', t.overview('surveyed_individuals') = 18);
select t.as_user('m02');
select t.raises('cannot delete someone else''s response', $$select api.delete_my_response(t.id('r_m01'))$$, 'P0002');
select t.as_user('m01');
select t.succeeds('member deletes own response', $$select api.delete_my_response(t.id('r_m01'))$$);
select t.ok('deleted response leaves statistics', t.overview('surveyed_individuals') = 17);

-- ---------------------------------------------------------------- versioning
reset role;
insert into app.survey_versions (scope, version, title_en, title_gu, published_at)
values ('individual', 2, 'Individual survey v2', 'વ્યક્તિગત સર્વેક્ષણ આ.૨', now());
insert into app.survey_questions (version_id, code, position, kind, prompt_en, prompt_gu)
select id, 'currently_studying', 1, 'single_choice', 'Currently studying?', 'હાલ અભ્યાસ કરો છો?'
from app.survey_versions where scope = 'individual' and version = 2;
insert into t.ids select 'r_m03_v1', r.id from app.survey_responses r
  join app.account_person ap on ap.person_id = r.subject_person
 where ap.account_id = t.id('m03') and r.scope = 'individual';
set role bbg_api;
select t.as_user('m03');
select t.ok('a new version starts a new response, keeping the old one',
    (select coalesce(api.start_survey('individual') <> t.id('r_m03_v1'), false)));
select t.ok('statistics never mix questionnaire versions', t.overview('surveyed_individuals') = 0);

reset role;
select t.ok('survey audit entries hold no answers',
    not exists (select 1 from app.audit_events where action like '%survey%' and detail <> '{}'::jsonb));

-- Complementary suppression unit check.
select t.ok('complementary suppression hides the smallest other cell, keeps zeros',
    (select array_agg(coalesce(n::text, 'x') order by key) = array['10', 'x', 'x', '0']
       from app.suppress(array[row('a', null, null, 10), row('b', null, null, 3),
                               row('c', null, null, 7), row('d', null, null, 0)]::app.stat_cell[], 5)));
select t.ok('two small cells need no extra suppression',
    (select array_agg(coalesce(n::text, 'x') order by key) = array['10', 'x', 'x', '9']
       from app.suppress(array[row('a', null, null, 10), row('b', null, null, 3),
                               row('c', null, null, 2), row('d', null, null, 9)]::app.stat_cell[], 5)));

\ir _report.sql
