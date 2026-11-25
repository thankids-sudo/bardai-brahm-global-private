-- Tests for migration 0003 (brief M3): no duplicate counting, unconfirmed links marked,
-- private relatives do not leak, merges need review, invalid cycles blocked. Synthetic data only.
\set ON_ERROR_STOP on
set client_min_messages = warning;
\o /dev/null

\ir _harness.sql

-- Shorthand: does a tree row for person `who` exist in the caller's tree, and its flags.
create function t.in_tree(who text) returns boolean language sql as $$
    select exists (select 1 from api.family_tree() where person_id = t.id(who)) $$;
create function t.private_in_tree(who text) returns boolean language sql as $$
    select is_private from api.family_tree() where person_id = t.id(who) $$;
create function t.unconfirmed_in_tree(who text) returns boolean language sql as $$
    select unconfirmed from api.family_tree() where person_id = t.id(who) $$;
grant execute on all functions in schema t to bbg_api;

-- ---------------------------------------------------------------- fixtures
insert into t.ids select 'admin',    app.upsert_account('s-admin', 'admin@example.test', true);
insert into t.ids select 'sec',      app.upsert_account('s-sec',   'sec@example.test',   true);
insert into t.ids select 'raj',      app.upsert_account('s-raj',   'raj@example.test',   true);
insert into t.ids select 'sita',     app.upsert_account('s-sita',  'sita@example.test',  true);
insert into t.ids select 'ved',      app.upsert_account('s-ved',   'ved@example.test',   true);
insert into t.ids select 'mom_acct', app.upsert_account('s-mom',   'mom@example.test',   true);
insert into t.ids select 'other',    app.upsert_account('s-other', 'other@example.test', true);
insert into app.chapters (id, parent_id, level, name_en, name_gu, accepts_applications) values
 ('00000000-0000-0000-0000-0000000000a0', null, 'global', 'Global', 'વૈશ્વિક', false);
insert into app.chapters (id, parent_id, level, name_en, name_gu, country_code) values
 ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'city', 'Test City A', 'ટેસ્ટ શહેર A', 'IN');
insert into t.ids values ('ch_a', '00000000-0000-0000-0000-0000000000a1');
select app.bootstrap_global_admin('admin@example.test');

set role bbg_api;
select t.as_user('admin'); select api.grant_role(t.id('sec'), 'chapter_secretary', t.id('ch_a'));

select t.as_user('raj');  insert into t.ids select 'app_raj',  api.submit_application(t.id('ch_a'), 'Raj',  'Testbhai', 1980, 'Gam', 'City A', 'IN');
select t.as_user('sita'); insert into t.ids select 'app_sita', api.submit_application(t.id('ch_a'), 'Sita', 'Testbhai', 1983, 'Gam', 'City A', 'IN');
select t.as_user('ved');  insert into t.ids select 'app_ved',  api.submit_application(t.id('ch_a'), 'Ved',  'Otherbhai', 1979, 'Gam2', 'City A', 'IN');
select t.as_user('sec');
select api.review_application(t.id('app_raj'), 'approved', null);
select api.review_application(t.id('app_sita'), 'approved', null);
select api.review_application(t.id('app_ved'), 'approved', null);

reset role;
insert into t.ids select 'p_raj',  person_id from app.account_person where account_id = t.id('raj');
insert into t.ids select 'p_sita', person_id from app.account_person where account_id = t.id('sita');
insert into t.ids select 'p_ved',  person_id from app.account_person where account_id = t.id('ved');
set role bbg_api;

-- ---------------------------------------------------------------- consent basis
select t.as_user('raj');
select t.raises('living adult relative needs assisted-with-consent basis',
    $$select api.add_relative_person('M', 'T', null, 1955, true, null, null, null, 'guardian')$$, '22023');
select t.raises('minor needs guardian basis',
    $$select api.add_relative_person('S', 'T', null, 2015, true, null, null, null, 'assisted_with_consent')$$, '22023');
select t.raises('deceased needs deceased-record basis',
    $$select api.add_relative_person('F', 'T', null, 1950, false, 2010, null, null, 'self')$$, '22023');
select t.as_user('other');
select t.raises('account without own profile cannot add relatives',
    $$select api.add_relative_person('F', 'T', null, 1950, false, 2010, null, null, 'deceased_record')$$, '55000');

-- Raj records both parental branches, a spouse and a minor son.
select t.as_user('raj');
insert into t.ids select 'father', api.add_relative_person('Pita',  'Testbhai', null, 1950, false, 2010, 'Gam', 'Gam', 'deceased_record');
insert into t.ids select 'mother', api.add_relative_person('Mata',  'Testbhai', 'Maidenbhai', 1955, true, null, 'Gam3', 'Gam3', 'assisted_with_consent');
insert into t.ids select 'pgf',    api.add_relative_person('Dada',  'Testbhai', null, 1920, false, 1990, null, 'Gam', 'deceased_record');
insert into t.ids select 'pgm',    api.add_relative_person('Dadi',  'Testbhai', null, 1925, false, 1995, null, 'Gam', 'deceased_record');
insert into t.ids select 'mgf',    api.add_relative_person('Nana',  'Maidenbhai', null, 1922, false, 1999, null, 'Gam3', 'deceased_record');
insert into t.ids select 'mgm',    api.add_relative_person('Nani',  'Maidenbhai', null, 1928, false, 2001, null, 'Gam3', 'deceased_record');
insert into t.ids select 'wife',   api.add_relative_person('Patni', 'Testbhai', 'Wifebhai', 1983, true, null, null, 'Gam4', 'assisted_with_consent');
insert into t.ids select 'son',    api.add_relative_person('Putra', 'Testbhai', null, 2015, true, null, null, 'Gam', 'guardian');

select api.add_relationship('parent', t.id('father'), t.id('p_raj'), 'biological', 'father', null, null);
insert into t.ids select 'l_mother_raj', api.add_relationship('parent', t.id('mother'), t.id('p_raj'), 'biological', 'mother', null, null);
select api.add_relationship('parent', t.id('pgf'), t.id('father'), 'biological', 'father', null, null);
select api.add_relationship('parent', t.id('pgm'), t.id('father'), 'biological', 'mother', null, null);
select api.add_relationship('parent', t.id('mgf'), t.id('mother'), 'biological', 'father', null, null);
select api.add_relationship('parent', t.id('mgm'), t.id('mother'), 'biological', 'mother', null, null);
select api.add_relationship('parent', t.id('p_raj'), t.id('son'), 'biological', 'father', null, null);
select api.add_relationship('spouse', t.id('wife'), t.id('p_raj'), null, null, 2008, null);

select t.ok('own links between own records are self-reported (not marked unconfirmed)',
    not t.unconfirmed_in_tree('father'));
select t.ok('tree expands both parental branches to grandparents',
    (select count(*) = 4 from api.family_tree() where path = 'parent>parent'));
select t.ok('deceased ancestors are shown with names',
    (select not is_private and given_name = 'Dada' from api.family_tree() where person_id = t.id('pgf')));
select t.ok('owner sees own minor child', not t.private_in_tree('son'));

-- ---------------------------------------------------------------- invalid relationships
select t.raises('person cannot be own parent',
    $$select api.add_relationship('parent', t.id('p_raj'), t.id('p_raj'), 'biological', 'parent', null, null)$$, '23514');
select t.raises('cannot become parent of own father (cycle)',
    $$select api.add_relationship('parent', t.id('p_raj'), t.id('father'), 'adoptive', 'parent', null, null)$$, '23514');
select t.raises('cannot become parent of own grandfather (longer cycle)',
    $$select api.add_relationship('parent', t.id('son'), t.id('pgf'), 'guardian', 'parent', null, null)$$, '23514');
-- Cycle check on its own (unknown birth years, so the birth-order rule cannot catch it).
insert into t.ids select 'anc1', api.add_relative_person('Purvaj', 'Ek',  null, null, false, null, null, null, 'deceased_record');
insert into t.ids select 'anc2', api.add_relative_person('Purvaj', 'Be',  null, null, false, null, null, null, 'deceased_record');
insert into t.ids select 'anc3', api.add_relative_person('Purvaj', 'Tran', null, null, false, null, null, null, 'deceased_record');
select api.add_relationship('parent', t.id('anc1'), t.id('anc2'), 'unknown', 'parent', null, null);
select api.add_relationship('parent', t.id('anc2'), t.id('anc3'), 'unknown', 'parent', null, null);
select t.raises('cycle blocked even when birth years are unknown',
    $$select api.add_relationship('parent', t.id('anc3'), t.id('anc1'), 'unknown', 'parent', null, null)$$, '23514');
insert into t.ids select 'young', api.add_relative_person('Yuva', 'Testbhai', null, 1990, false, 2000, null, null, 'deceased_record');
select t.raises('parent born after child is rejected',
    $$select api.add_relationship('parent', t.id('young'), t.id('p_raj'), 'step', 'parent', null, null)$$, '23514');
insert into t.ids select 'extra', api.add_relative_person('Extra', 'Testbhai', null, 1940, false, 2005, null, null, 'deceased_record');
select t.raises('no third biological parent',
    $$select api.add_relationship('parent', t.id('extra'), t.id('p_raj'), 'biological', 'parent', null, null)$$, '23514');
select t.succeeds('adoptive/step/guardian parents are supported beyond two',
    $$select api.add_relationship('parent', t.id('extra'), t.id('p_raj'), 'guardian', 'parent', null, null)$$);
select t.raises('parent fields not allowed on spouse links',
    $$select api.add_relationship('spouse', t.id('p_raj'), t.id('young'), 'biological', null, null, null)$$, '22023');
insert into t.ids select 'ex', api.add_relative_person('Purva', 'Exbhai', null, 1982, false, 2007, null, null, 'deceased_record');
select t.succeeds('earlier marriage with end year (remarriage) is supported',
    $$select api.add_relationship('spouse', t.id('p_raj'), t.id('ex'), null, null, 2002, 2007)$$);
select t.raises('duplicate link is rejected',
    $$select api.add_relationship('spouse', t.id('p_raj'), t.id('wife'), null, null, 2008, null)$$, '23505');
select t.as_user('ved');
select t.raises('cannot link two records you do not own',
    $$select api.add_relationship('spouse', t.id('father'), t.id('mother'), null, null, null, null)$$, 'P0002');

-- ---------------------------------------------------------------- confirmation of links to other people
select t.as_user('raj');
insert into t.ids select 'l_father_sita', api.add_relationship('parent', t.id('father'), t.id('p_sita'), 'biological', 'father', null, null);
select t.ok('link to another account holder is marked unconfirmed for its creator', t.unconfirmed_in_tree('p_sita'));
select t.ok('unconfirmed relative is not revealed even to the link creator', t.private_in_tree('p_sita'));

select t.as_user('ved');
select t.ok('unrelated member sees none of another family',
    not exists (select 1 from api.family_tree() where person_id in (t.id('father'), t.id('p_sita'), t.id('son'))));
select t.raises('cannot open another member''s tree', $$select * from api.family_tree(t.id('p_raj'))$$, 'P0002');
select t.raises('third party cannot answer the pending link',
    $$select api.respond_relationship(t.id('l_father_sita'), true)$$, 'P0002');
select t.raises('third party cannot retract the link', $$select api.retract_relationship(t.id('l_father_sita'))$$, 'P0002');
select t.ok('directory does not expose relationships',
    not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace, unnest(p.proargnames) a
                where n.nspname = 'api' and p.proname = 'directory_search' and a ~* '(parent|spouse|relat|household)'));

select t.as_user('raj');
select t.raises('creator cannot accept own link on the other person''s behalf',
    $$select api.respond_relationship(t.id('l_father_sita'), true)$$, 'P0002');

select t.as_user('sita');
select t.ok('pending link not shown in the other party''s tree before accepting',
    not exists (select 1 from api.family_tree() where person_id = t.id('father') and not unconfirmed));
select t.ok('sita sees one link awaiting her answer', (select count(*) = 1 from api.my_pending_links()));
select t.succeeds('sita accepts the link', $$select api.respond_relationship(t.id('l_father_sita'), true)$$);

select t.as_user('raj');
select t.ok('after acceptance, sibling is visible and derived as parent>child',
    (select not is_private and not unconfirmed and path = 'parent>child' from api.family_tree() where person_id = t.id('p_sita')));

select t.as_user('sita');
select t.ok('sita now sees shared deceased father and grandparents',
    (select count(*) = 3 from api.family_tree() where person_id in (t.id('father'), t.id('pgf'), t.id('pgm')) and not is_private));
select t.ok('brother with own account is visible to sister', not t.private_in_tree('p_raj'));
select t.ok('living relative managed by someone else stays private (brother''s wife)', t.private_in_tree('wife'));
select t.ok('another person''s minor child stays private', t.private_in_tree('son'));
select t.ok('private rows carry no name, code or birth year',
    (select bool_and(given_name is null and surname is null and member_code is null and birth_year is null)
       from api.family_tree() where is_private));

select api.set_family_visibility('only_me');
select t.as_user('raj');
select t.ok('relative who chose only_me becomes private', t.private_in_tree('p_sita'));
select t.as_user('sita'); select api.set_family_visibility('relatives');

-- Disputes keep wrong links out of everyone's tree.
select t.as_user('raj');
insert into t.ids select 'l_mother_sita', api.add_relationship('parent', t.id('mother'), t.id('p_sita'), 'step', 'mother', null, null);
select t.as_user('sita');
select t.succeeds('sita disputes an incorrect link', $$select api.respond_relationship(t.id('l_mother_sita'), false)$$);
select t.as_user('raj');
select t.ok('disputed link no longer connects records',
    (select path = 'parent>child' from api.family_tree() where person_id = t.id('p_sita')));

-- ---------------------------------------------------------------- claiming a record
select t.as_user('raj');
select t.raises('minor cannot be invited to claim', $$select api.create_claim_invite(t.id('son'))$$, '55000');
select t.raises('deceased record cannot be claimed', $$select api.create_claim_invite(t.id('father'))$$, '55000');
select t.raises('account-holder record cannot be invited', $$select api.create_claim_invite(t.id('p_sita'))$$, 'P0002');
reset role;
create table t.tokens (name text primary key, token text);
grant all on t.tokens to bbg_api;
set role bbg_api;
select t.as_user('raj');
insert into t.tokens select 'mother', api.create_claim_invite(t.id('mother'));
insert into t.tokens select 'wife',   api.create_claim_invite(t.id('wife'));

select t.as_user('sita');
select t.raises('account that already has a record cannot claim another',
    $$select api.claim_person((select token from t.tokens where name = 'wife'))$$, '55000');
select t.as_user('mom_acct');
select t.raises('wrong token is rejected', $$select api.claim_person('not-a-real-token')$$, 'P0002');
select t.succeeds('mother claims her own record with the invitation',
    $$select api.claim_person((select token from t.tokens where name = 'mother'))$$);
select t.as_user('other');
select t.raises('used invitation cannot be reused (no takeover)',
    $$select api.claim_person((select token from t.tokens where name = 'mother'))$$, 'P0002');

select t.as_user('raj');
select t.raises('former manager can no longer manage a claimed record',
    $$select api.create_claim_invite(t.id('mother'))$$, 'P0002');
select t.ok('links recorded about her become unconfirmed until she accepts', t.unconfirmed_in_tree('mother'));
select t.as_user('mom_acct');
select t.ok('mother has three links to review (to Raj and to both her parents)', (select count(*) = 3 from api.my_pending_links()));
select api.respond_relationship(t.id('l_mother_raj'), true);
select t.as_user('raj');
select t.ok('confirmed mother is visible again', (select not unconfirmed and not is_private from api.family_tree() where person_id = t.id('mother')));

reset role;
update app.claim_invites set expires_at = now() - interval '1 minute' where person_id = t.id('wife');
set role bbg_api;
select t.as_user('other');
select t.raises('expired invitation is rejected',
    $$select api.claim_person((select token from t.tokens where name = 'wife'))$$, 'P0002');

-- ---------------------------------------------------------------- households and residences
select t.as_user('raj');
insert into t.ids select 'hh_raj', api.create_household();
select t.succeeds('add managed spouse to household', $$select api.add_household_member(t.id('hh_raj'), t.id('wife'))$$);
select t.succeeds('add managed son to household', $$select api.add_household_member(t.id('hh_raj'), t.id('son'))$$);
select t.raises('person cannot be counted in two current households',
    $$select api.create_household()$$, '23505');
select t.raises('same person cannot be added twice', $$select api.add_household_member(t.id('hh_raj'), t.id('son'))$$, '23505');
select t.raises('cannot add someone else''s record to a household',
    $$select api.add_household_member(t.id('hh_raj'), t.id('p_sita'))$$, 'P0002');
select t.as_user('ved');
select t.raises('non-member cannot add to a household', $$select api.add_household_member(t.id('hh_raj'), t.id('p_ved'))$$, 'P0002');
select t.as_user('raj');
select t.succeeds('member leaves with an end date', $$select api.leave_household(t.id('hh_raj'), t.id('son'))$$);
select t.succeeds('time-bounded membership allows rejoining later', $$select api.add_household_member(t.id('hh_raj'), t.id('son'))$$);

select api.set_current_residence(t.id('p_raj'), 'City A', 'State', 'IN', 2005);
select api.set_current_residence(t.id('p_raj'), 'London', null, 'GB', 2018);
select t.as_user('ved');
select t.raises('cannot set another person''s residence',
    $$select api.set_current_residence(t.id('p_raj'), 'X', null, 'IN', 2020)$$, 'P0002');

-- ---------------------------------------------------------------- reviewed merges
select t.as_user('raj');
select t.raises('record belonging to an account cannot be merged away',
    $$select api.request_merge(t.id('pgf'), t.id('p_raj'))$$, '55000');
select t.as_user('sita');
insert into t.ids select 'pgf_dup', api.add_relative_person('Dada', 'Testbhai', null, 1921, false, 1990, null, 'Gam', 'deceased_record');
select t.as_user('ved');
select t.raises('cannot request merge of records you do not own',
    $$select api.request_merge(t.id('pgf'), t.id('pgf_dup'))$$, 'P0002');
select t.as_user('sita');
insert into t.ids select 'mr_pgf', api.request_merge(t.id('pgf'), t.id('pgf_dup'));
select t.raises('requester cannot approve own merge',
    $$select api.review_merge(t.id('mr_pgf'), true, true, 'same person')$$, '42501');
select t.as_user('raj');
select t.raises('owner of a record cannot review its merge',
    $$select api.review_merge(t.id('mr_pgf'), true, true, 'same person')$$, '42501');
select t.as_user('sec');
select t.raises('conflicting fields must be acknowledged',
    $$select api.review_merge(t.id('mr_pgf'), true, false, 'same person')$$, '22023');
select t.raises('merge review needs a note',
    $$select api.review_merge(t.id('mr_pgf'), true, true, '')$$, '22023');
select t.succeeds('secretary approves merge after reviewing conflicts',
    $$select api.review_merge(t.id('mr_pgf'), true, true, 'Birth year differs by one; same person per family')$$);

-- Merge that would create a cycle is refused and leaves everything unchanged.
select t.as_user('raj');
insert into t.ids select 'x_child', api.add_relative_person('Dada', 'Testbhai', null, 2001, false, 2002, null, null, 'deceased_record');
select api.add_relationship('parent', t.id('p_raj'), t.id('x_child'), 'biological', 'father', null, null);
insert into t.ids select 'mr_cycle', api.request_merge(t.id('pgf'), t.id('x_child'));
select t.as_user('sec');
select t.raises('merge that would make an ancestor a descendant is blocked',
    $$select api.review_merge(t.id('mr_cycle'), true, true, 'try')$$, '23514');
select t.succeeds('reviewer can reject the invalid merge instead',
    $$select api.review_merge(t.id('mr_cycle'), false, false, 'Different people')$$);

reset role;
select t.ok('merged record is marked and excluded', (select merged_into = t.id('pgf') from app.persons where id = t.id('pgf_dup')));
select t.ok('merge conflicts store field names only',
    (select conflicts = array['birth_year'] from app.merge_requests where id = t.id('mr_pgf')));
select t.ok('every person is in at most one current household',
    (select count(*) = count(distinct person_id) from app.household_members where left_on is null));
select t.ok('household membership history is kept (son left and rejoined)',
    (select count(*) = 2 from app.household_members where person_id = t.id('son')));
select t.ok('exactly one current residence, earlier one closed',
    (select count(*) filter (where is_current) = 1 and count(*) = 2
       and bool_and(is_current or to_year = 2018) from app.residences where person_id = t.id('p_raj')));
select t.ok('no person has more than two active biological parents',
    not exists (select 1 from app.relationships where kind = 'parent' and parent_type = 'biological'
                and status not in ('retracted', 'disputed') group by to_person having count(*) > 2));
select t.ok('no active parent cycles anywhere', not exists (select 1 from app.persons p where app.is_ancestor(p.id, p.id)));
select t.ok('each record entered by someone records who and on what basis',
    not exists (select 1 from app.persons where created_by is null)
    and (select count(*) filter (where consent_basis = 'guardian') = 1 from app.persons));
select t.ok('family audit entries hold no names',
    not exists (select 1 from app.audit_events where detail::text ~* '(dada|raj|sita|testbhai)'));

\ir _report.sql
