-- Negative and positive authorisation tests for migration 0001 (brief, milestone M2).
-- Synthetic data only. Run via backend/db/run_tests.sh against a throwaway database.
\set ON_ERROR_STOP on
set client_min_messages = warning;
\o /dev/null

\ir _harness.sql

-- ---------------------------------------------------------------- fixtures (operator)
insert into t.ids select 'admin',        app.upsert_account('sub-admin',  'admin@example.test', true);
insert into t.ids select 'sec_a',        app.upsert_account('sub-seca',   'seca@example.test',  true);
insert into t.ids select 'sec_b',        app.upsert_account('sub-secb',   'secb@example.test',  true);
insert into t.ids select 'alice',        app.upsert_account('sub-alice',  'alice@example.test', true);
insert into t.ids select 'bob',          app.upsert_account('sub-bob',    'bob@example.test',   true);
insert into t.ids select 'carol',        app.upsert_account('sub-carol',  'carol@example.test', true);
insert into t.ids select 'unverified',   app.upsert_account('sub-unv',    'unv@example.test',   false);
insert into t.ids select 'pending_dave', app.upsert_account('sub-dave',   'dave@example.test',  true);

insert into app.chapters (id, parent_id, level, name_en, name_gu, accepts_applications)
values ('00000000-0000-0000-0000-0000000000a0', null, 'global', 'Global', 'વૈશ્વિક', false);
insert into app.chapters (id, parent_id, level, name_en, name_gu, country_code)
values ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'city', 'Test City A', 'ટેસ્ટ શહેર A', 'IN'),
       ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a0', 'city', 'Test City B', 'ટેસ્ટ શહેર B', 'GB');
insert into t.ids values ('ch_global', '00000000-0000-0000-0000-0000000000a0'),
                         ('ch_a', '00000000-0000-0000-0000-0000000000a1'),
                         ('ch_b', '00000000-0000-0000-0000-0000000000b1');

-- Bootstrap: refused for unverified, succeeds once, refused the second time.
select t.raises('bootstrap refuses unverified email', $$select app.bootstrap_global_admin('unv@example.test')$$, '42501');
select t.raises('bootstrap refuses unknown email', $$select app.bootstrap_global_admin('nobody@example.test')$$, 'P0002');
select t.succeeds('bootstrap works once for verified designated account', $$select app.bootstrap_global_admin('ADMIN@example.test')$$);
select t.raises('bootstrap refuses a second time', $$select app.bootstrap_global_admin('alice@example.test')$$, '42501');

-- ---------------------------------------------------------------- everything below runs as the API role
set role bbg_api;

select t.raises('api role cannot read tables directly', $$select * from app.accounts$$, '42501');
select t.raises('api role cannot write role table directly',
    $$insert into app.role_assignments (account_id, role) values (t.id('alice'), 'global_admin')$$, '42501');
select t.raises('api role cannot call bootstrap', $$select app.bootstrap_global_admin('alice@example.test')$$, '42501');
select t.raises('api role cannot create/verify accounts', $$select app.upsert_account('x','x@example.test', true)$$, '42501');

select set_config('app.account_id', '', false);
select t.raises('unauthenticated call is rejected', $$select * from api.my_status()$$, '28000');

-- Admin appoints secretaries; nobody self-promotes.
select t.as_user('admin');
select t.succeeds('admin appoints secretary for chapter A', $$select api.grant_role(t.id('sec_a'), 'chapter_secretary', t.id('ch_a'))$$);
select t.succeeds('admin appoints secretary for chapter B', $$select api.grant_role(t.id('sec_b'), 'chapter_secretary', t.id('ch_b'))$$);
select t.raises('admin cannot grant a role to self', $$select api.grant_role(t.id('admin'), 'chapter_secretary', t.id('ch_a'))$$, '42501');
select t.raises('roles only go to verified accounts', $$select api.grant_role(t.id('unverified'), 'chapter_secretary', t.id('ch_a'))$$, '42501');

select t.as_user('sec_a');
select t.raises('secretary cannot appoint roles', $$select api.grant_role(t.id('alice'), 'chapter_secretary', t.id('ch_a'))$$, '42501');
select t.raises('secretary cannot self-promote to global admin', $$select api.grant_role(t.id('sec_a'), 'global_admin', null)$$, '42501');

select t.as_user('alice');
select t.raises('member cannot self-promote', $$select api.grant_role(t.id('alice'), 'chapter_secretary', t.id('ch_a'))$$, '42501');

-- Unverified accounts cannot apply or search.
select t.as_user('unverified');
select t.raises('unverified email cannot apply',
    $$select api.submit_application(t.id('ch_a'), 'Unv', 'Erified', 1990, null, null, 'IN')$$, '42501');
select t.raises('unverified email cannot search directory', $$select * from api.directory_search('test')$$, '42501');

-- Applications.
select t.as_user('alice');
insert into t.ids select 'app_alice', api.submit_application(t.id('ch_a'), 'Alice', 'Testbhai', 1980, 'Testgam', 'Test City A', 'IN');
select t.raises('only one open application per account',
    $$select api.submit_application(t.id('ch_a'), 'Alice', 'Testbhai', 1980, null, null, 'IN')$$, '23505');
select t.raises('applications cannot target the non-accepting global chapter',
    $$select api.submit_application(t.id('ch_global'), 'A', 'B', 1980, null, null, 'IN')$$, '22023');
select t.raises('pending applicant cannot search directory', $$select * from api.directory_search('Test')$$, '42501');

select t.as_user('bob');
insert into t.ids select 'app_bob', api.submit_application(t.id('ch_b'), 'Bob', 'Samplebhai', 1975, 'Samplegam', 'Test City B', 'GB');
select t.as_user('carol');
insert into t.ids select 'app_carol', api.submit_application(t.id('ch_a'), 'Carol', 'Testbhai', 1985, 'Testgam', 'Test City A', 'IN');
select t.as_user('pending_dave');
insert into t.ids select 'app_dave', api.submit_application(t.id('ch_a'), 'Dave', 'Pendingbhai', 1990, null, null, 'IN');
select t.as_user('sec_a');
insert into t.ids select 'app_sec_a', api.submit_application(t.id('ch_a'), 'Seca', 'Secretarybhai', 1970, null, null, 'IN');

-- Secretary scope.
select t.as_user('sec_a');
select t.raises('secretary cannot approve another chapter''s member',
    $$select api.review_application(t.id('app_bob'), 'approved', null)$$, '42501');
select t.raises('secretary cannot approve own application',
    $$select api.review_application(t.id('app_sec_a'), 'approved', null)$$, '42501');
select t.raises('rejection requires a reason',
    $$select api.review_application(t.id('app_carol'), 'rejected', '  ')$$, '22023');
select t.succeeds('secretary approves own chapter''s applicant', $$select api.review_application(t.id('app_alice'), 'approved', null)$$);
select t.succeeds('secretary approves carol', $$select api.review_application(t.id('app_carol'), 'approved', null)$$);
select t.raises('decided application cannot be re-reviewed',
    $$select api.review_application(t.id('app_alice'), 'rejected', 'changed mind')$$, '55000');

select t.as_user('sec_b');
select t.succeeds('secretary B approves bob', $$select api.review_application(t.id('app_bob'), 'approved', null)$$);

select t.as_user('admin');
select t.raises('global admin is not implicitly a secretary',
    $$select api.review_application(t.id('app_dave'), 'approved', null)$$, '42501');

-- Directory: consent-gated, member-only, no contact fields, no wildcard enumeration.
select t.as_user('alice');
select t.ok('approved member sees nobody before anyone opts in',
    (select count(*) = 0 from api.directory_search('Test')));
select t.as_user('carol');
select api.set_consent('directory_listing', true);
select t.as_user('bob');
select api.set_consent('directory_listing', true);
select t.as_user('alice');
select t.ok('approved member finds consenting member by surname',
    (select count(*) = 1 and bool_and(given_name = 'Carol') from api.directory_search('testbhai')));
select t.ok('directory search spans chapters worldwide',
    (select count(*) = 1 from api.directory_search('Samplegam')));
select t.ok('non-consenting approved member (alice herself) not listed',
    (select count(*) = 0 from api.directory_search('Alice')));
select t.ok('wildcard query does not enumerate everyone',
    (select count(*) = 0 from api.directory_search('%%')));
select t.ok('directory result has no email/phone columns',
    not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace,
                       unnest(p.proargnames) as arg
                where n.nspname = 'api' and p.proname = 'directory_search'
                  and arg ~* '(email|phone|address)'));
select t.raises('search needs at least 2 characters', $$select * from api.directory_search('a')$$, '22023');

select t.as_user('pending_dave');
select t.raises('pending member still cannot search after others are approved',
    $$select * from api.directory_search('Test')$$, '42501');

-- Suspension.
reset role;
insert into t.ids select 'person_alice', person_id from app.account_person where account_id = t.id('alice');
insert into t.ids select 'person_carol', person_id from app.account_person where account_id = t.id('carol');
set role bbg_api;

select t.as_user('alice');
select api.set_consent('directory_listing', true);
select t.as_user('carol');
select t.ok('member who opts in becomes findable',
    (select count(*) = 1 from api.directory_search('Alice')));

select t.as_user('sec_b');
select t.raises('secretary B cannot suspend chapter A member',
    $$select api.set_membership_suspended(t.id('person_alice'), true, 'test')$$, '42501');
select t.as_user('sec_a');
select t.raises('suspension requires a reason',
    $$select api.set_membership_suspended(t.id('person_alice'), true, '')$$, '22023');
select t.succeeds('secretary A suspends alice', $$select api.set_membership_suspended(t.id('person_alice'), true, 'test reason')$$);
select t.as_user('alice');
select t.raises('suspended member cannot search directory', $$select * from api.directory_search('Test')$$, '42501');
select t.as_user('carol');
select t.ok('suspended member disappears from directory results',
    (select count(*) = 0 from api.directory_search('Alice')));

-- Revocation takes effect immediately.
select t.as_user('admin');
reset role;
insert into t.ids select 'role_sec_a', id from app.role_assignments
    where account_id = t.id('sec_a') and role = 'chapter_secretary' and revoked_at is null;
insert into t.ids select 'role_admin', id from app.role_assignments
    where account_id = t.id('admin') and role = 'global_admin' and revoked_at is null;
set role bbg_api;
select t.as_user('admin');
select t.succeeds('admin revokes secretary A', $$select api.revoke_role(t.id('role_sec_a'))$$);
select t.raises('admin cannot revoke own global admin role',
    $$select api.revoke_role(t.id('role_admin'))$$, '42501');
select t.as_user('sec_a');
select t.raises('revoked secretary can no longer review',
    $$select api.review_application(t.id('app_dave'), 'approved', null)$$, '42501');

reset role;

-- ---------------------------------------------------------------- audit and integrity (operator view)
select t.ok('approvals are audited with actor and chapter',
    (select count(*) = 3 from app.audit_events
      where action = 'review_application:approved' and actor is not null and chapter_id is not null));
select t.ok('role grants and revocations are audited',
    (select count(*) = 2 from app.audit_events where action like 'grant_role:%')
    and (select count(*) = 1 from app.audit_events where action like 'revoke_role:%'));
select t.ok('audit rows hold no names or emails',
    not exists (select 1 from app.audit_events
                where detail::text ~* '(alice|carol|bob|example\.test)'));
select t.raises('audit log is append-only (update)', $$update app.audit_events set action = 'x'$$, 'P0001');
select t.raises('audit log is append-only (delete)', $$delete from app.audit_events$$, 'P0001');
select t.raises('member code is immutable',
    $$update app.persons set member_code = 'BBG-9999999' where id = t.id('person_carol')$$, 'P0001');
select t.ok('member codes are assigned and unique',
    (select count(*) = count(distinct member_code) and count(*) = 5 from app.persons));
select t.ok('each approved person counted once',
    (select count(*) = 3 from app.memberships));

\ir _report.sql
