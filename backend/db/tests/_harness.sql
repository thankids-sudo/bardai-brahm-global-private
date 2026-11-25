-- Shared test helpers. Included by each test file with \ir.
-- ---------------------------------------------------------------- test harness
create schema t;
create table t.ids (name text primary key, id uuid not null);
create table t.results (n serial, name text, ok boolean, info text);

create function t.id(p text) returns uuid language sql stable as $$ select id from t.ids where name = p $$;
create function t.as_user(p text) returns void language sql as $$
    select set_config('app.account_id', coalesce(t.id(p)::text, ''), false) $$;

create function t.ok(p_name text, p_cond boolean) returns void language plpgsql as $$
begin insert into t.results (name, ok, info) values (p_name, coalesce(p_cond, false), null); end $$;

-- Runs p_sql; passes only if it fails with the expected SQLSTATE.
create function t.raises(p_name text, p_sql text, p_state text) returns void language plpgsql as $$
begin
    begin
        execute p_sql;
    exception when others then
        insert into t.results (name, ok, info)
        values (p_name, sqlstate = p_state, case when sqlstate = p_state then null else sqlstate || ' ' || sqlerrm end);
        return;
    end;
    insert into t.results (name, ok, info) values (p_name, false, 'no error raised');
end $$;

-- Runs p_sql; passes if no error.
create function t.succeeds(p_name text, p_sql text) returns void language plpgsql as $$
begin
    execute p_sql;
    insert into t.results (name, ok) values (p_name, true);
exception when others then
    insert into t.results (name, ok, info) values (p_name, false, sqlstate || ' ' || sqlerrm);
end $$;

grant usage on schema t to bbg_api;
grant all on all tables in schema t to bbg_api;
grant all on all sequences in schema t to bbg_api;
grant execute on all functions in schema t to bbg_api;

