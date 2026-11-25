-- Tests for migration 0005 (brief M5): contact choices enforced server-side, time zone conversion
-- correct (incl. daylight-saving changes), upload permissions and removal work, chapter roles scoped.
\set ON_ERROR_STOP on
set client_min_messages = warning;
\o /dev/null

\ir _harness.sql

create function t.ev_local(p_event text, p_tz text) returns text language sql as $$
    select to_char(starts_viewer_local, 'YYYY-MM-DD HH24:MI') from api.list_events(p_tz, '2026-01-01', '2028-01-01')
    where event_id = t.id(p_event) $$;
create function t.ev_utc(p_event text) returns text language sql as $$
    select to_char(starts_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI') from api.list_events('UTC', '2026-01-01', '2028-01-01')
    where event_id = t.id(p_event) $$;
grant execute on all functions in schema t to bbg_api;

-- ---------------------------------------------------------------- fixtures
insert into t.ids select 'admin', app.upsert_account('s-admin', 'admin@example.test', true);
insert into t.ids select 'adm_a', app.upsert_account('s-adma',  'adma@example.test',  true);
insert into t.ids select 'sec_a', app.upsert_account('s-seca',  'seca@example.test',  true);
insert into t.ids select 'adm_b', app.upsert_account('s-admb',  'admb@example.test',  true);
insert into t.ids select 'alice', app.upsert_account('s-alice', 'alice@example.test', true);
insert into t.ids select 'bob',   app.upsert_account('s-bob',   'bob@example.test',   true);
insert into t.ids select 'carol', app.upsert_account('s-carol', 'carol@example.test', true);
insert into t.ids select 'pend',  app.upsert_account('s-pend',  'pend@example.test',  true);
insert into app.chapters (id, parent_id, level, name_en, name_gu, accepts_applications) values
 ('00000000-0000-0000-0000-0000000000a0', null, 'global', 'Global', 'વૈશ્વિક', false);
insert into app.chapters (id, parent_id, level, name_en, name_gu, country_code) values
 ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'city', 'Test City A', 'ટેસ્ટ શહેર A', 'IN'),
 ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a0', 'city', 'London Test', 'લંડન ટેસ્ટ', 'GB');
insert into t.ids values ('ch_a', '00000000-0000-0000-0000-0000000000a1'), ('ch_b', '00000000-0000-0000-0000-0000000000b1');
select app.bootstrap_global_admin('admin@example.test');

set role bbg_api;
select t.as_user('admin');
select api.grant_role(t.id('sec_a'), 'chapter_secretary', t.id('ch_a'));
select api.grant_role(t.id('adm_a'), 'chapter_admin', t.id('ch_a'));
select api.grant_role(t.id('adm_b'), 'chapter_admin', t.id('ch_b'));
select api.grant_role(t.id('adm_b'), 'chapter_secretary', t.id('ch_b'));

select t.as_user('alice'); insert into t.ids select 'app_alice', api.submit_application(t.id('ch_a'), 'Alice', 'Contactbhai', 1980, 'Gam', 'City A', 'IN');
select t.as_user('carol'); insert into t.ids select 'app_carol', api.submit_application(t.id('ch_a'), 'Carol', 'Contactbhai', 1982, 'Gam', 'City A', 'IN');
select t.as_user('bob');   insert into t.ids select 'app_bob',   api.submit_application(t.id('ch_b'), 'Bob', 'Londonbhai', 1975, 'Gam2', 'London', 'GB');
select t.as_user('pend');  select api.submit_application(t.id('ch_a'), 'Pend', 'Ingbhai', 1990, null, null, 'IN');
select t.as_user('sec_a'); select api.review_application(t.id('app_alice'), 'approved', null);
select api.review_application(t.id('app_carol'), 'approved', null);
select t.as_user('adm_b'); select api.review_application(t.id('app_bob'), 'approved', null);
reset role;
create table t.codes (name text primary key, code text);
insert into t.codes select 'bob', p.member_code from app.persons p join app.account_person ap on ap.person_id = p.id where ap.account_id = t.id('bob');
insert into t.codes select 'carol', p.member_code from app.persons p join app.account_person ap on ap.person_id = p.id where ap.account_id = t.id('carol');
insert into t.codes select 'alice', p.member_code from app.persons p join app.account_person ap on ap.person_id = p.id where ap.account_id = t.id('alice');
grant select on t.codes to bbg_api;
set role bbg_api;

-- ---------------------------------------------------------------- contact choices
select t.as_user('bob');
select api.set_consent('directory_listing', true);
select api.set_consent('directory_email', true);
select t.raises('phone format is validated', $$select api.set_contact_phone('call me maybe')$$, '23514');
select api.set_contact_phone('+44 7700 900123');

select t.as_user('alice');
select t.ok('email shared, phone withheld when only email consented',
    (select email = 'bob@example.test' and phone is null from api.directory_contact((select code from t.codes where name = 'bob'))));
select t.as_user('bob'); select api.set_consent('directory_phone', true); select api.set_consent('directory_email', false);
select t.as_user('alice');
select t.ok('choices take effect immediately: phone now shared, email withdrawn',
    (select email is null and phone = '+44 7700 900123' from api.directory_contact((select code from t.codes where name = 'bob'))));
select t.raises('unlisted member looks the same as a missing one',
    $$select * from api.directory_contact((select code from t.codes where name = 'carol'))$$, 'P0002');
select t.raises('unknown code', $$select * from api.directory_contact('BBG-0000000')$$, 'P0002');
select t.as_user('pend');
select t.raises('pending applicant cannot see contacts',
    $$select * from api.directory_contact((select code from t.codes where name = 'bob'))$$, '42501');

reset role;
update app.settings set value = '2' where key = 'contact_reveals_per_day';
update app.settings set value = '2' where key = 'directory_searches_per_hour';
set role bbg_api;
select t.as_user('alice');
select t.raises('daily contact limit stops bulk harvesting',
    $$select * from api.directory_contact((select code from t.codes where name = 'bob'))$$, '54000');
select t.as_user('carol');
select api.directory_search('London');
select api.directory_search('London');
select t.raises('search rate limit stops enumeration', $$select * from api.directory_search('London')$$, '54000');
reset role;
select t.ok('contact log records which fields were shared, never the values',
    (select bool_and(not (fields::text ~* '(@|\+44)')) and count(*) = 2 from app.contact_reveals));
update app.settings set value = '60' where key = 'directory_searches_per_hour';
set role bbg_api;

-- ---------------------------------------------------------------- events: scope and time zones
select t.as_user('alice');
select t.raises('members cannot create events',
    $$select api.create_event(t.id('ch_a'), 'X', 'X', null, null, '2027-01-10 10:00', '2027-01-10 12:00', 'Asia/Kolkata', 'Hall', null, null)$$, '42501');
select t.as_user('adm_a');
select t.raises('chapter admin cannot create events in another chapter',
    $$select api.create_event(t.id('ch_b'), 'X', 'X', null, null, '2027-01-10 10:00', '2027-01-10 12:00', 'Europe/London', 'Hall', null, null)$$, '42501');
select t.raises('unknown time zone rejected',
    $$select api.create_event(t.id('ch_a'), 'X', 'X', null, null, '2027-01-10 10:00', '2027-01-10 12:00', 'Mars/Base', 'Hall', null, null)$$, '22023');
select t.raises('online links must be https',
    $$select api.create_event(t.id('ch_a'), 'X', 'X', null, null, '2027-01-10 10:00', '2027-01-10 12:00', 'Asia/Kolkata', null, 'http://meet.example', null)$$, '23514');
select t.raises('end must be after start',
    $$select api.create_event(t.id('ch_a'), 'X', 'X', null, null, '2027-01-10 10:00', '2027-01-10 09:00', 'Asia/Kolkata', 'Hall', null, null)$$, '23514');

select t.as_user('adm_b');
insert into t.ids select 'ev_lon_gmt', api.create_event(t.id('ch_b'), 'Before clocks change', 'સમય બદલાય તે પહેલાં', null, null,
    '2026-03-28 10:00', '2026-03-28 12:00', 'Europe/London', 'Community hall', null, null);
insert into t.ids select 'ev_lon_bst', api.create_event(t.id('ch_b'), 'After clocks change', 'સમય બદલાયા પછી', null, null,
    '2026-03-29 10:00', '2026-03-29 12:00', 'Europe/London', 'Community hall', null, null);
select t.raises('local time skipped by the clock change is refused',
    $$select api.create_event(t.id('ch_b'), 'X', 'X', null, null, '2026-03-29 01:30', '2026-03-29 03:00', 'Europe/London', 'Hall', null, null)$$, '22023');
select t.as_user('sec_a');
insert into t.ids select 'ev_ny_edt', api.create_event(t.id('ch_a'), 'NY call (EDT)', 'ન્યૂયોર્ક (EDT)', null, null,
    '2026-10-31 09:00', '2026-10-31 10:00', 'America/New_York', null, 'https://meet.example/ny', null);
insert into t.ids select 'ev_ny_est', api.create_event(t.id('ch_a'), 'NY call (EST)', 'ન્યૂયોર્ક (EST)', null, null,
    '2026-11-02 09:00', '2026-11-02 10:00', 'America/New_York', null, 'https://meet.example/ny', null);

select t.as_user('alice');
select t.ok('draft events are not listed', not exists (select 1 from api.list_events('Asia/Kolkata', '2026-01-01', '2028-01-01')));
select t.as_user('adm_a');
select t.raises('chapter admin cannot publish another chapter''s event',
    $$select api.set_event_status(t.id('ev_lon_gmt'), 'published')$$, 'P0002');
select t.as_user('adm_b');
select api.set_event_status(t.id('ev_lon_gmt'), 'published');
select api.set_event_status(t.id('ev_lon_bst'), 'published');
select t.as_user('sec_a');
select t.succeeds('secretary of the chapter can publish its events', $$select api.set_event_status(t.id('ev_ny_edt'), 'published')$$);
select api.set_event_status(t.id('ev_ny_est'), 'published');

select t.as_user('alice');
select t.ok('London 10:00 GMT = 10:00 UTC = 15:30 India',
    t.ev_utc('ev_lon_gmt') = '2026-03-28 10:00' and t.ev_local('ev_lon_gmt', 'Asia/Kolkata') = '2026-03-28 15:30');
select t.ok('London 10:00 BST (after the change) = 09:00 UTC = 14:30 India',
    t.ev_utc('ev_lon_bst') = '2026-03-29 09:00' and t.ev_local('ev_lon_bst', 'Asia/Kolkata') = '2026-03-29 14:30');
select t.ok('New York 09:00 EDT = 18:30 India; after US change 09:00 EST = 19:30 India',
    t.ev_local('ev_ny_edt', 'Asia/Kolkata') = '2026-10-31 18:30' and t.ev_local('ev_ny_est', 'Asia/Kolkata') = '2026-11-02 19:30');
select t.ok('event-local time is kept as entered',
    (select to_char(starts_event_local, 'HH24:MI') = '10:00' and event_time_zone = 'Europe/London'
       from api.list_events('Asia/Kolkata', '2026-01-01', '2028-01-01') where event_id = t.id('ev_lon_bst')));
select t.ok('viewers in other zones see their own local time (London viewer, NY event)',
    t.ev_local('ev_ny_est', 'Europe/London') = '2026-11-02 14:00');
select t.raises('unknown viewer time zone rejected', $$select * from api.list_events('Nowhere/City')$$, '22023');
select t.ok('worldwide listing with chapter and country filters',
    (select count(*) = 4 from api.list_events('UTC', '2026-01-01', '2028-01-01'))
    and (select count(*) = 2 from api.list_events('UTC', '2026-01-01', '2028-01-01', null, 'gb'))
    and (select count(*) = 2 from api.list_events('UTC', '2026-01-01', '2028-01-01', t.id('ch_a'))));
select t.as_user('pend');
select t.raises('pending applicants cannot list events', $$select * from api.list_events('UTC')$$, '42501');

-- ---------------------------------------------------------------- RSVP, capacity, attendance
select t.as_user('adm_a');
insert into t.ids select 'ev_cap', api.create_event(t.id('ch_a'), 'Small gathering', 'નાનો મેળાવડો', null, null,
    '2027-02-14 18:00', '2027-02-14 21:00', 'Asia/Kolkata', 'Hall A', null, 3);
select t.as_user('alice');
select t.raises('cannot RSVP to an unpublished event', $$select api.rsvp(t.id('ev_cap'), 'going', 0)$$, '55000');
select t.as_user('adm_a'); select api.set_event_status(t.id('ev_cap'), 'published');
select t.as_user('alice');
select t.ok('first RSVP with one guest takes two places', api.rsvp(t.id('ev_cap'), 'going', 1) = 'going');
select t.raises('cannot set waitlisted directly', $$select api.rsvp(t.id('ev_cap'), 'waitlisted', 0)$$, '22023');
select t.as_user('bob');
select t.ok('worldwide member takes the last place', api.rsvp(t.id('ev_cap'), 'going', 0) = 'going');
select t.as_user('carol');
select t.ok('over capacity becomes waitlisted', api.rsvp(t.id('ev_cap'), 'going', 0) = 'waitlisted');
select t.as_user('bob');
select api.rsvp(t.id('ev_cap'), 'not_going', 0);
select t.as_user('carol');
select t.ok('freed place promotes the waitlist', (select my_rsvp = 'going' and seats_taken = 3
    from api.list_events('UTC', '2026-01-01', '2028-01-01') where event_id = t.id('ev_cap')));
select t.as_user('pend');
select t.raises('pending applicant cannot RSVP', $$select api.rsvp(t.id('ev_cap'), 'going', 0)$$, '42501');
select t.as_user('alice');
select t.raises('past events take no RSVPs', $$select api.rsvp(t.id('ev_lon_gmt'), 'going', 0)$$, '55000');
select t.raises('members cannot see the participant list', $$select * from api.event_participants(t.id('ev_cap'))$$, 'P0002');
select t.as_user('adm_b');
select t.raises('other chapter admin cannot see participants', $$select * from api.event_participants(t.id('ev_cap'))$$, 'P0002');
select t.raises('other chapter admin cannot mark attendance',
    $$select api.mark_attendance(t.id('ev_cap'), (select code from t.codes where name = 'alice'), true)$$, 'P0002');
select t.as_user('adm_a');
select t.ok('organising chapter sees participants', (select count(*) = 3 from api.event_participants(t.id('ev_cap'))));
select t.succeeds('organiser marks attendance', $$select api.mark_attendance(t.id('ev_cap'), (select code from t.codes where name = 'alice'), true)$$);
select api.set_event_status(t.id('ev_cap'), 'cancelled');
select t.as_user('alice');
select t.ok('cancelled event stays visible as cancelled', (select status = 'cancelled' from api.list_events('UTC', '2026-01-01', '2028-01-01') where event_id = t.id('ev_cap')));
select t.raises('cancelled event takes no RSVPs', $$select api.rsvp(t.id('ev_cap'), 'going', 0)$$, '55000');
select t.as_user('adm_a');
select t.raises('cancelled event cannot be reopened', $$select api.set_event_status(t.id('ev_cap'), 'published')$$, '55000');

-- ---------------------------------------------------------------- announcements
select t.as_user('adm_b');
select t.raises('admin cannot announce in another chapter',
    $$select api.post_announcement(t.id('ch_a'), 'X', 'X', 'x', 'x', null)$$, '42501');
select t.as_user('sec_a');
insert into t.ids select 'ann_a', api.post_announcement(t.id('ch_a'), 'Monthly meeting', 'માસિક બેઠક',
    'Join online.', 'ઓનલાઇન જોડાઓ.', 'https://meet.example/monthly');
select t.raises('announcement meeting link must be https',
    $$select api.post_announcement(t.id('ch_a'), 'X', 'X', 'x', 'x', 'http://meet.example')$$, '23514');
select t.as_user('bob');
select t.ok('members worldwide read announcements, bilingual', (select count(*) = 1 and bool_and(title_gu = 'માસિક બેઠક') from api.list_announcements()));
select t.as_user('adm_b');
select t.raises('other chapter cannot remove the announcement', $$select api.remove_announcement(t.id('ann_a'))$$, 'P0002');
select t.as_user('admin');
select t.succeeds('global admin can remove any announcement', $$select api.remove_announcement(t.id('ann_a'))$$);
select t.as_user('bob');
select t.ok('removed announcement disappears', (select count(*) = 0 from api.list_announcements()));

-- ---------------------------------------------------------------- photos
select t.as_user('adm_a');
insert into t.ids select 'ev_photo', api.create_event(t.id('ch_a'), 'Annual day', 'વાર્ષિક દિવસ', null, null,
    '2026-11-01 10:00', '2026-11-01 13:00', 'Asia/Kolkata', 'Hall A', null, null);
select api.set_event_status(t.id('ev_photo'), 'published');
select t.as_user('sec_a');
select t.raises('secretary (not admin) cannot upload photos',
    $$select api.register_event_photo(t.id('ev_photo'), 'events/' || t.id('ev_photo') || '/p1.webp', 'image/webp', 300000, 1600, 1200, null, null)$$, '42501');
select t.as_user('adm_b');
select t.raises('admin of another chapter cannot upload',
    $$select api.register_event_photo(t.id('ev_photo'), 'events/' || t.id('ev_photo') || '/p1.webp', 'image/webp', 300000, 1600, 1200, null, null)$$, '42501');
select t.as_user('adm_a');
select t.raises('uncompressed (oversized) photo refused',
    $$select api.register_event_photo(t.id('ev_photo'), 'events/' || t.id('ev_photo') || '/big.jpg', 'image/jpeg', 9000000, 1600, 1200, null, null)$$, '22023');
select t.raises('over-large dimensions refused',
    $$select api.register_event_photo(t.id('ev_photo'), 'events/' || t.id('ev_photo') || '/huge.jpg', 'image/jpeg', 900000, 6000, 4000, null, null)$$, '22023');
select t.raises('only JPEG/WebP accepted',
    $$select api.register_event_photo(t.id('ev_photo'), 'events/' || t.id('ev_photo') || '/p.png', 'image/png', 300000, 1600, 1200, null, null)$$, '23514');
select t.raises('path outside the event folder refused',
    $$select api.register_event_photo(t.id('ev_photo'), '../../etc/passwd', 'image/jpeg', 300000, 1600, 1200, null, null)$$, '22023');
select t.raises('storage key must be inside this event''s folder',
    $$select api.register_event_photo(t.id('ev_photo'), 'events/someone-else/p9.webp', 'image/webp', 300000, 1600, 1200, null, null)$$, '22023');
select t.raises('storage key cannot start at the root',
    $$select api.register_event_photo(t.id('ev_photo'), '/etc/a/b.jpg', 'image/jpeg', 300000, 1600, 1200, null, null)$$, '22023');
select t.raises('storage key cannot climb directories mid-path',
    $$select api.register_event_photo(t.id('ev_photo'), 'events/' || t.id('ev_photo') || '/../../secrets/x.jpg', 'image/jpeg', 300000, 1600, 1200, null, null)$$, '23514');
insert into t.ids select 'ph1', api.register_event_photo(t.id('ev_photo'), 'events/' || t.id('ev_photo') || '/p1.webp', 'image/webp', 300000, 1600, 1200, 'Prize giving', 'ઇનામ વિતરણ');
insert into t.ids select 'ph2', api.register_event_photo(t.id('ev_photo'), 'events/' || t.id('ev_photo') || '/p2.webp', 'image/webp', 250000, 1600, 1200, null, null);

select t.as_user('bob');
select t.ok('members see event photos (keys for signed URLs only)', (select count(*) = 2 from api.event_photos(t.id('ev_photo'))));
select t.as_user('pend');
select t.raises('pending applicants cannot see photos', $$select * from api.event_photos(t.id('ev_photo'))$$, '42501');

select t.as_user('alice');
select t.succeeds('member reports a photo of themselves', $$select api.report_photo(t.id('ph1'), 'I am in this photo and do not consent')$$);
select t.raises('one report per member per photo', $$select api.report_photo(t.id('ph1'), 'again')$$, '23505');
select t.raises('members cannot remove photos', $$select api.remove_photo(t.id('ph1'), 'x')$$, 'P0002');
select t.as_user('adm_b');
select t.ok('other chapter admin does not see the report', (select count(*) = 0 from api.photo_report_queue()));
select t.raises('other chapter admin cannot remove the photo', $$select api.remove_photo(t.id('ph1'), 'x')$$, 'P0002');
select t.as_user('adm_a');
select t.ok('chapter admin sees the report', (select count(*) = 1 from api.photo_report_queue()));
select t.raises('removal needs a reason', $$select api.remove_photo(t.id('ph1'), '')$$, '22023');
select t.succeeds('chapter admin removes the reported photo', $$select api.remove_photo(t.id('ph1'), 'Removed at subject''s request')$$);
select t.ok('report resolved and queue empty', (select count(*) = 0 from api.photo_report_queue()));
select t.as_user('admin');
select t.succeeds('global admin can remove any photo', $$select api.remove_photo(t.id('ph2'), 'Moderation')$$);
select t.as_user('bob');
select t.ok('removed photos are no longer served', (select count(*) = 0 from api.event_photos(t.id('ev_photo'))));

reset role;
select t.ok('photo report recorded as resolved by removal',
    (select resolution = 'removed' and resolved_by = t.id('adm_a') from app.media_reports));
select t.ok('M5 audit rows hold no contact details or names',
    not exists (select 1 from app.audit_events where detail::text ~* '(@|\+44|alice|bob|carol)'));

\ir _report.sql
