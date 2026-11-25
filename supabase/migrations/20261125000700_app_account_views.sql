-- 0007: read-only views of the caller's own application and roles, for the app's account screens.

-- The caller's most recent membership application, with the reviewer's note (needed to correct).
create function api.my_application() returns table (
    application_id uuid, status app.application_status, chapter_id uuid, chapter_name_en text, chapter_name_gu text,
    reviewer_note text, submitted_at timestamptz, given_name text, surname text, birth_year int,
    ancestral_village text, present_city text, present_country text
) language plpgsql stable security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller();
begin
    return query
    select ma.id, ma.status, ma.chapter_id, c.name_en, c.name_gu, ma.reviewer_note, ma.submitted_at,
           p.given_name, p.surname, p.birth_year, p.ancestral_village, p.present_city, p.present_country
    from membership_applications ma
    join chapters c on c.id = ma.chapter_id
    join persons p on p.id = ma.person_id
    where ma.account_id = me
    order by ma.submitted_at desc
    limit 1;
end $$;

-- The caller's active roles (so the app can show, e.g., the secretary's review screen).
create function api.my_roles() returns table (
    role app.role_kind, chapter_id uuid, chapter_name_en text, chapter_name_gu text
) language plpgsql stable security definer set search_path = app, pg_temp as $$
declare me uuid := app.require_verified_caller();
begin
    return query
    select r.role, r.chapter_id, c.name_en, c.name_gu
    from role_assignments r left join chapters c on c.id = r.chapter_id
    where r.account_id = me and r.revoked_at is null
    order by r.role, c.name_en;
end $$;

revoke all on function api.my_application(), api.my_roles() from public;
grant execute on function api.my_application(), api.my_roles() to bbg_api;
do $$ begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function api.my_application(), api.my_roles() to authenticated;
    end if;
end $$;
