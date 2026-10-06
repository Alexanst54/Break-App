-- Exécution indépendante du navigateur. Seulement sur Break-App-Preprod.
begin;
do $$ begin
 if to_regclass('public.pause_breaks') is not null or to_regclass('break_app.teams') is null then
  raise exception 'Base de préproduction V2 attendue';
 end if;
end $$;
create extension if not exists pg_cron;
select cron.schedule('break-app-preprod-reconcile','15 seconds','select break_app.reconcile()');
select cron.schedule('break-app-preprod-retention','20 2 * * *','select break_app.maintenance()');
-- Limiter aussi l'historique technique du planificateur.
select cron.schedule('break-app-preprod-cron-retention','30 2 * * *',
 $$delete from cron.job_run_details where end_time < now()-interval '7 days' and jobid in (select jobid from cron.job where jobname like 'break-app-preprod-%')$$);
commit;
