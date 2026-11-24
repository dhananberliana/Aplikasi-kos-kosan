-- Kostora v0.8: schedule daily H-7 billing at 08:00 WITA (00:00 UTC).
-- Run in Supabase SQL Editor as postgres after billing_v06.sql.
begin;
create extension if not exists pg_cron;
do $$
declare j bigint;
begin
 for j in select jobid from cron.job where jobname='kostora-billing-h7' loop
  perform cron.unschedule(j);
 end loop;
end $$;
select cron.schedule('kostora-billing-h7','0 0 * * *',
 'select kostora_private.generate_invoices(null::uuid);');
commit;
-- Verify:
select jobid, jobname, schedule, active from cron.job where jobname='kostora-billing-h7';
