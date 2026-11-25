-- Tests for migration 0007: callers see only their own application and roles.
\set ON_ERROR_STOP on
set client_min_messages = warning;
\o /dev/null
\ir _harness.sql

insert into t.ids select 'admin', app.upsert_account('s-admin', 'admin@example.test', true);
insert into t.ids select 'sec',   app.upsert_account('s-sec',   'sec@example.test',   true);
insert into t.ids select 'ann',   app.upsert_account('s-ann',   'ann@example.test',   true);
insert into t.ids select 'ben',   app.upsert_account('s-ben',   'ben@example.test',   true);
insert into t.ids select 'unv',   app.upsert_account('s-unv',   'unv@example.test',   false);
insert into app.chapters (id, parent_id, level, name_en, name_gu, accepts_applications) values
 ('00000000-0000-0000-0000-0000000000a0', null, 'global', 'Global', 'વૈશ્વિક', false);
insert into app.chapters (id, parent_id, level, name_en, name_gu, country_code) values
 ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'city', 'Test City A', 'ટેસ્ટ શહેર A', 'IN');
insert into t.ids values ('ch', '00000000-0000-0000-0000-0000000000a1');
select app.bootstrap_global_admin('admin@example.test');

set role bbg_api;
select t.as_user('admin'); select api.grant_role(t.id('sec'), 'chapter_secretary', t.id('ch'));
select t.as_user('ann');
select t.ok('no application yet: empty result', (select count(*) = 0 from api.my_application()));
insert into t.ids select 'app_ann', api.submit_application(t.id('ch'), 'Ann', 'Viewbhai', 1990, 'Gam', 'City', 'IN');
select t.as_user('ben');
select api.submit_application(t.id('ch'), 'Ben', 'Otherbhai', 1991, null, null, 'IN');
select t.as_user('sec');
select api.review_application(t.id('app_ann'), 'correction_requested', 'Please add your ancestral village spelling in full');
select t.as_user('ann');
select t.ok('applicant sees own status, chapter and the reviewer''s note',
    (select status = 'correction_requested' and reviewer_note like 'Please add%' and chapter_name_gu = 'ટેસ્ટ શહેર A'
            and given_name = 'Ann' from api.my_application()));
select t.as_user('ben');
select t.ok('another applicant sees only their own application',
    (select count(*) = 1 and bool_and(given_name = 'Ben' and reviewer_note is null) from api.my_application()));
select t.as_user('sec');
select t.ok('secretary sees own role and chapter', (select count(*) = 1 and bool_and(role = 'chapter_secretary' and chapter_name_en = 'Test City A') from api.my_roles()));
select t.as_user('admin');
select t.ok('global admin role has no chapter', (select bool_or(role = 'global_admin' and chapter_id is null) from api.my_roles()));
select t.as_user('ann');
select t.ok('ordinary member has no roles', (select count(*) = 0 from api.my_roles()));
select t.as_user('unv');
select t.raises('unverified account cannot read application', $$select * from api.my_application()$$, '42501');
reset role;
\ir _report.sql
