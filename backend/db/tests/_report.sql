-- Shared result report; fails the run if any test failed. Included last with \ir.
-- ---------------------------------------------------------------- report
\o
\pset footer off
select n, case when ok then 'PASS' else 'FAIL' end as result, name, coalesce(info, '') as info
from t.results order by n;

do $$
declare f int; total int;
begin
    select count(*) filter (where not ok), count(*) into f, total from t.results;
    raise notice '% tests, % failed', total, f;
    if f > 0 then
        raise exception 'test failures: %', f;
    end if;
end $$;
