-- Tests for migration 0002: correction/resubmission, withdrawal, appeals, review queue,
-- duplicate suggestions, chapter routing and account disabling. Synthetic data only.
\set ON_ERROR_STOP on
set client_min_messages = warning;
\o /dev/null

\ir _harness.sql

-- ---------------------------------------------------------------- fixtures (operator)
insert into t.ids select 'admin',  app.upsert_account('s-admin',  'admin@example.test',  true);
insert into t.ids select 'admin2', app.upsert_account('s-admin2', 'admin2@example.test', true);
insert into t.ids select 'sec_a',  app.upsert_account('s-seca',   'seca@example.test',   true);
insert into t.ids select 'sec_a2', app.upsert_account('s-seca2',  'seca2@example.test',  true);
insert into t.ids select 'sec_b',  app.upsert_account('s-secb',   'secb@example.test',   true);
insert into t.ids select 'erin',   app.upsert_account('s-erin',   'erin@example.test',   true);
insert into t.ids select 'frank',  app.upsert_account('s-frank',  'frank@example.test',  true);
insert into t.ids select 'gina',   app.upsert_account('s-gina',   'gina@example.test',   true);
insert into t.ids select 'hari',   app.upsert_account('s-hari',   'hari@example.test',   true);
insert into t.ids select 'ivy',    app.upsert_account('s-ivy',    'ivy@example.test',    true);
insert into t.ids select 'ivy2',   app.upsert_account('s-ivy2',   'ivy2@example.test',   true);
insert into t.ids select 'jay',    app.upsert_account('s-jay',    'jay@example.test',    true);
insert into t.ids select 'unv',    app.upsert_account('s-unv',    'unv@example.test',    false);

insert into app.chapters (id, parent_id, level, name_en, name_gu, accepts_applications, is_global_intake) values
 ('00000000-0000-0000-0000-0000000000a0', null, 'global', 'Global', 'વૈશ્વિક', false, false);
insert into app.chapters (id, parent_id, level, name_en, name_gu, country_code, accepts_applications, is_global_intake) values
 ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'city', 'Test City A', 'ટેસ્ટ શહેર A', 'IN', true, false),
 ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a0', 'city', 'Test City B', 'ટેસ્ટ શહેર B', 'GB', true, false),
 ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000a0', 'country', 'Global intake (no local chapter)', 'વૈશ્વિક પ્રવેશ (સ્થાનિક શાખા નથી)', null, true, true);
insert into t.ids values ('ch_a', '00000000-0000-0000-0000-0000000000a1'),
                         ('ch_b', '00000000-0000-0000-0000-0000000000b1'),
                         ('ch_intake', '00000000-0000-0000-0000-0000000000c1');

select app.bootstrap_global_admin('admin@example.test');

set role bbg_api;

select t.as_user('admin');
select api.grant_role(t.id('admin2'), 'global_admin', null);
select api.grant_role(t.id('sec_a'),  'chapter_secretary', t.id('ch_a'));
select api.grant_role(t.id('sec_a2'), 'chapter_secretary', t.id('ch_a'));
select api.grant_role(t.id('sec_b'),  'chapter_secretary', t.id('ch_b'));

-- ---------------------------------------------------------------- chapter routing
select t.as_user('unv');
select t.raises('unverified cannot list chapters', $$select * from api.list_chapters()$$, '42501');

select t.as_user('erin');
select t.ok('chapter list excludes non-accepting global root',
    not exists (select 1 from api.list_chapters() where level = 'global'));
select t.ok('global intake is listed first and has no secretary yet',
    (select is_global_intake and not has_secretary from api.list_chapters() limit 1));
select t.ok('chapter A shows a secretary is available',
    (select has_secretary from api.list_chapters() where id = t.id('ch_a')));

-- ---------------------------------------------------------------- applications
select t.as_user('erin');  insert into t.ids select 'app_erin',  api.submit_application(t.id('ch_a'), 'Erin',  'Alpha', 1990, 'Gam1', 'City A', 'IN');
select t.as_user('frank'); insert into t.ids select 'app_frank', api.submit_application(t.id('ch_a'), 'Frank', 'Beta',  1985, 'Gam2', 'City A', 'IN');
select t.as_user('gina');  insert into t.ids select 'app_gina',  api.submit_application(t.id('ch_a'), 'Gina',  'Gamma', 1975, 'Gam3', 'City A', 'IN');
select t.as_user('hari');  insert into t.ids select 'app_hari',  api.submit_application(t.id('ch_a'), 'Hari',  'Delta', 1970, 'Gam4', 'City A', 'IN');
select t.as_user('ivy');   insert into t.ids select 'app_ivy',   api.submit_application(t.id('ch_a'), 'Ivy',   'Same',  1980, 'Gam5', 'City A', 'IN');
select t.as_user('ivy2');  insert into t.ids select 'app_ivy2',  api.submit_application(t.id('ch_b'), 'IVY',   'same',  1981, 'Gam5', 'City B', 'GB');
select t.as_user('jay');   insert into t.ids select 'app_jay',   api.submit_application(t.id('ch_intake'), 'Jay', 'Epsilon', 1995, null, 'Nairobi', 'KE');

-- ---------------------------------------------------------------- review queue and duplicates
select t.as_user('sec_a');
select t.ok('secretary A queue holds exactly chapter A pending applications',
    (select count(*) = 5 and bool_and(chapter_id = t.id('ch_a')) from api.review_queue()));
select t.ok('queue never shows intake or other-chapter applications',
    not exists (select 1 from api.review_queue() where application_id in (t.id('app_jay'), t.id('app_ivy2'))));
select t.ok('possible duplicate flagged across chapters (case-insensitive, birth year +/- 1)',
    (select possible_duplicates = 1 from api.review_queue() where application_id = t.id('app_ivy')));
select t.ok('non-duplicates are not flagged',
    (select possible_duplicates = 0 from api.review_queue() where application_id = t.id('app_erin')));
select t.ok('secretary sees duplicate candidate by member code only with minimal fields',
    (select count(*) = 1 and bool_and(member_code like 'BBG-%' and not is_member)
       from api.duplicate_candidates(t.id('app_ivy'))));
select t.as_user('sec_b');
select t.raises('other chapter secretary cannot inspect duplicates',
    $$select * from api.duplicate_candidates(t.id('app_ivy'))$$, 'P0002');
select t.as_user('erin');
select t.ok('ordinary member has an empty review queue', (select count(*) = 0 from api.review_queue()));
select t.raises('applicant cannot inspect duplicates', $$select * from api.duplicate_candidates(t.id('app_erin'))$$, 'P0002');

-- ---------------------------------------------------------------- correction and resubmission
select t.as_user('sec_a');
select t.raises('correction request needs a reason',
    $$select api.review_application(t.id('app_erin'), 'correction_requested', '')$$, '22023');
select t.succeeds('secretary requests correction',
    $$select api.review_application(t.id('app_erin'), 'correction_requested', 'Please give full surname')$$);
select t.ok('application needing correction leaves the queue',
    not exists (select 1 from api.review_queue() where application_id = t.id('app_erin')));

select t.as_user('frank');
select t.raises('someone else cannot resubmit the application',
    $$select api.resubmit_application(t.id('app_erin'), 'X', 'Y', 1990, null, null, 'IN')$$, 'P0002');
select t.raises('pending application cannot be resubmitted',
    $$select api.resubmit_application(t.id('app_frank'), 'Frank', 'Beta', 1985, null, null, 'IN')$$, '55000');
select t.as_user('erin');
select t.succeeds('applicant resubmits corrected details',
    $$select api.resubmit_application(t.id('app_erin'), 'Erin', 'Alphabhai', 1990, 'Gam1', 'City A', 'IN')$$);
select t.ok('applicant sees status pending again', (select application_status = 'pending' from api.my_status()));
select t.as_user('sec_a');
select t.ok('resubmitted application returns to queue with corrected surname',
    (select surname = 'Alphabhai' from api.review_queue() where application_id = t.id('app_erin')));

-- ---------------------------------------------------------------- withdrawal
select t.as_user('frank');
select t.raises('someone else cannot withdraw the application', $$select api.withdraw_application(t.id('app_hari'))$$, 'P0002');
select t.as_user('hari');
select t.succeeds('applicant withdraws', $$select api.withdraw_application(t.id('app_hari'))$$);
select t.raises('withdrawn application cannot be withdrawn again', $$select api.withdraw_application(t.id('app_hari'))$$, '55000');
select t.succeeds('applicant may apply again after withdrawing',
    $$select api.submit_application(t.id('ch_a'), 'Hari', 'Delta', 1970, 'Gam4', 'City A', 'IN')$$);

-- ---------------------------------------------------------------- appeals
select t.as_user('sec_a');
select api.review_application(t.id('app_frank'), 'rejected', 'Could not confirm details');

select t.as_user('erin');
select t.raises('cannot appeal a pending application', $$select api.appeal_rejection(t.id('app_erin'), 'why')$$, '55000');
select t.raises('cannot appeal someone else''s rejection', $$select api.appeal_rejection(t.id('app_frank'), 'why')$$, 'P0002');
select t.as_user('frank');
select t.raises('appeal needs a reason', $$select api.appeal_rejection(t.id('app_frank'), ' ')$$, '22023');
insert into t.ids select 'appeal_frank', api.appeal_rejection(t.id('app_frank'), 'My father is a member of chapter A');
select t.raises('only one appeal per application', $$select api.appeal_rejection(t.id('app_frank'), 'again')$$, '23505');

select t.as_user('sec_a');
select t.raises('secretary cannot decide appeals', $$select api.decide_appeal(t.id('appeal_frank'), true, 'ok')$$, '42501');
select t.as_user('admin');
select t.raises('appeal decision needs a note', $$select api.decide_appeal(t.id('appeal_frank'), true, '')$$, '22023');
select t.succeeds('admin upholds appeal', $$select api.decide_appeal(t.id('appeal_frank'), true, 'Reopened for fresh review')$$);
select t.raises('decided appeal cannot be decided again', $$select api.decide_appeal(t.id('appeal_frank'), false, 'x')$$, '55000');

select t.as_user('sec_a');
select t.ok('reopened application is back in the queue marked after_appeal',
    (select after_appeal from api.review_queue() where application_id = t.id('app_frank')));
select t.raises('original reviewer cannot re-review after upheld appeal',
    $$select api.review_application(t.id('app_frank'), 'rejected', 'still no')$$, '42501');
select t.as_user('sec_a2');
select t.succeeds('a different secretary approves after appeal', $$select api.review_application(t.id('app_frank'), 'approved', null)$$);
select t.as_user('frank');
select t.ok('applicant now approved', (select membership_status = 'approved' from api.my_status()));

-- Reviewer who is also an admin cannot decide the appeal against their own rejection.
select t.as_user('admin2');
select api.grant_role(t.id('admin'), 'chapter_secretary', t.id('ch_a'));
select t.as_user('admin');
select api.review_application(t.id('app_gina'), 'rejected', 'Duplicate of existing record');
select t.as_user('gina');
insert into t.ids select 'appeal_gina', api.appeal_rejection(t.id('app_gina'), 'I have no other record');
select t.as_user('admin');
select t.raises('admin cannot decide an appeal against own rejection',
    $$select api.decide_appeal(t.id('appeal_gina'), true, 'self')$$, '42501');
select t.as_user('admin2');
select t.succeeds('another admin dismisses the appeal', $$select api.decide_appeal(t.id('appeal_gina'), false, 'Rejection stands')$$);
select t.as_user('gina');
select t.ok('dismissed appeal leaves application rejected', (select application_status = 'rejected' from api.my_status()));

-- ---------------------------------------------------------------- account disable
select t.as_user('sec_a');
select t.raises('secretary cannot disable accounts', $$select api.set_account_disabled(t.id('erin'), true, 'x')$$, '42501');
select t.as_user('admin');
select t.raises('disable needs a reason', $$select api.set_account_disabled(t.id('erin'), true, '')$$, '22023');
select t.raises('admin cannot disable own account', $$select api.set_account_disabled(t.id('admin'), true, 'x')$$, '42501');
select t.succeeds('admin disables an account', $$select api.set_account_disabled(t.id('erin'), true, 'Reported impersonation')$$);
select t.as_user('erin');
select t.raises('disabled account is blocked from every action', $$select * from api.list_chapters()$$, '42501');
select t.raises('disabled account cannot withdraw or resubmit', $$select api.withdraw_application(t.id('app_erin'))$$, '42501');
select t.as_user('admin');
select api.set_account_disabled(t.id('erin'), false, 'Resolved');
select t.as_user('erin');
select t.succeeds('re-enabled account works again', $$select * from api.list_chapters()$$);

reset role;

-- ---------------------------------------------------------------- audit (operator view)
select t.ok('workflow actions audited',
    (select count(*) filter (where action = 'resubmit_application') = 1
        and count(*) filter (where action = 'withdraw_application') = 1
        and count(*) filter (where action = 'appeal_rejection') = 2
        and count(*) filter (where action = 'appeal_upheld') = 1
        and count(*) filter (where action = 'appeal_dismissed') = 1
        and count(*) filter (where action = 'disable_account') = 1
        and count(*) filter (where action = 'enable_account') = 1
     from app.audit_events));
select t.ok('appeal decisions record a decider distinct from appellant and reviewer',
    (select bool_and(decided_by not in (account_id, original_reviewer)) from app.appeals where status <> 'open'));

\ir _report.sql
