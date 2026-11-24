-- Run in Supabase SQL Editor. Read-only; no personal records returned.
-- 1. RLS coverage
select schemaname,tablename,rowsecurity
from pg_tables where schemaname in ('public','kostora_private')
order by schemaname,tablename;

-- 2. Policies and their actual predicates
select schemaname,tablename,policyname,roles,cmd,qual,with_check
from pg_policies where schemaname in ('public','kostora_private')
order by schemaname,tablename,policyname;

-- 3. Table privileges
select table_schema,table_name,grantee,privilege_type
from information_schema.role_table_grants
where table_schema in ('public','kostora_private')
and grantee in ('anon','authenticated','PUBLIC')
order by table_schema,table_name,grantee,privilege_type;

-- 4. Function privileges and search paths
select n.nspname as schema_name,p.proname,
pg_get_function_identity_arguments(p.oid) as arguments,
p.prosecdef as security_definer,p.proconfig,
has_function_privilege('anon',p.oid,'EXECUTE') as anon_execute,
has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_execute
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='kostora_private'
or (n.nspname='public' and (p.proname like 'kostora_%' or p.proname='validate_payment'))
order by 1,2;

-- 5. Inspect payment validation implementation
select pg_get_functiondef(p.oid) as function_definition
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname='validate_payment';

-- 6. Triggers and constraints
select event_object_table,trigger_name,event_manipulation,action_statement
from information_schema.triggers where trigger_schema='public'
order by event_object_table,trigger_name;
select conrelid::regclass as table_name,conname,pg_get_constraintdef(oid) as definition
from pg_constraint where connamespace='public'::regnamespace order by 1,2;

-- 7. Scheduler status and last runs (if pg_cron is enabled)
select jobid,jobname,schedule,active from cron.job where jobname='kostora-billing-h7';
select d.status,d.start_time,d.end_time,d.return_message
from cron.job_run_details d join cron.job j on j.jobid=d.jobid
where j.jobname='kostora-billing-h7' order by d.start_time desc limit 10;
