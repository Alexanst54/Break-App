-- V2: installation sur une base de PREPRODUCTION neuve uniquement.
-- Le test PGlite définit break_app.test=true ; une base contenant les tables V1 est refusée.
begin;
do $$ begin
  if to_regclass('public.pause_breaks') is not null or to_regclass('public.pause_admins') is not null then
    raise exception 'Installation refusée sur une base V1 : utiliser une base de préproduction neuve';
  end if;
end $$;
create schema break_app;
revoke all on schema break_app from public, anon, authenticated;
grant usage on schema break_app to authenticated;

create table break_app.teams (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (length(name) between 1 and 60),
  max_breaks int not null default 7 check (max_breaks between 1 and 100),
  break_minutes int not null default 15 check (break_minutes between 1 and 180),
  offer_seconds int not null default 60 check (offer_seconds between 20 and 600),
  suspended boolean not null default false,
  opens time not null default '00:00', closes time not null default '23:59:59',
  weekdays int[] not null default array[1,2,3,4,5,6,7],
  revision int not null default 1,
  check(opens < closes), check(cardinality(weekdays) between 1 and 7 and weekdays <@ array[1,2,3,4,5,6,7])
);
create table break_app.members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check(length(display_name) between 1 and 60),
  team_id uuid not null references break_app.teams(id),
  role text not null default 'advisor' check(role in ('advisor','admin')),
  enabled boolean not null default true
);
create index members_team on break_app.members(team_id);
create table break_app.requests (
  id bigint generated always as identity primary key,
  user_id uuid not null references break_app.members(user_id),
  team_id uuid not null references break_app.teams(id),
  display_name text not null,
  status text not null check(status in ('waiting','offered','active','completed','cancelled','expired')),
  requested_at timestamptz not null default clock_timestamp(),
  offered_at timestamptz, offer_expires_at timestamptz,
  started_at timestamptz, due_at timestamptz, ended_at timestamptz,
  ended_by uuid, reason text,
  check ((status='active' and started_at is not null and due_at is not null) or status <> 'active'),
  check ((status='offered' and offer_expires_at is not null) or status <> 'offered')
);
create unique index one_open_request on break_app.requests(user_id) where status in ('waiting','offered','active');
create index requests_team_queue on break_app.requests(team_id,requested_at,id) where status in ('waiting','offered','active');
create index requests_user_history on break_app.requests(user_id,requested_at desc);
create index requests_team_history on break_app.requests(team_id,requested_at desc);
create table break_app.audit (
  id bigint generated always as identity primary key,
  occurred_at timestamptz not null default clock_timestamp(), actor uuid,
  action text not null, details jsonb not null default '{}'::jsonb
);
-- Schéma non exposé, tables sans droits directs ; RLS en défense supplémentaire.
alter table break_app.teams enable row level security;
alter table break_app.members enable row level security;
alter table break_app.requests enable row level security;
alter table break_app.audit enable row level security;
revoke all on all tables in schema break_app from public,anon,authenticated;
revoke all on all sequences in schema break_app from public,anon,authenticated;
alter default privileges in schema break_app revoke execute on functions from public,anon,authenticated;

create function break_app.require_member() returns break_app.members
language plpgsql security definer set search_path='' as $$
declare m break_app.members;
begin
  select * into m from break_app.members where user_id=auth.uid() and enabled;
  if m.user_id is null then raise exception 'Compte non autorisé. Demandez au pilotage de vous ajouter.' using errcode='42501'; end if;
  return m;
end $$;
create function break_app.require_admin() returns void
language plpgsql security definer set search_path='' as $$
begin
  if (break_app.require_member()).role <> 'admin' then raise exception 'Accès réservé au pilotage.' using errcode='42501'; end if;
end $$;
create function break_app.is_open(t break_app.teams) returns boolean
language sql stable set search_path='' as $$
 select not t.suspended and extract(isodow from statement_timestamp() at time zone 'Europe/Paris')::int=any(t.weekdays)
 and (statement_timestamp() at time zone 'Europe/Paris')::time >= t.opens
 and (statement_timestamp() at time zone 'Europe/Paris')::time < t.closes
$$;
create function break_app.reconcile() returns void
language plpgsql security definer set search_path='' as $$
declare t break_app.teams; capacity int; active_count int; reserved_count int;
begin
 perform pg_advisory_xact_lock(7483922);
 update break_app.requests set status='expired',ended_at=clock_timestamp(),reason='offre_expiree'
 where status='offered' and offer_expires_at<=clock_timestamp();
 update break_app.requests set status='cancelled',ended_at=clock_timestamp(),reason='attente_plus_de_12h'
 where status='waiting' and requested_at<clock_timestamp()-interval '12 hours';
 for t in select * from break_app.teams order by id loop
   select count(*) into active_count from break_app.requests where team_id=t.id and status='active';
   capacity:=case when break_app.is_open(t) then greatest(0,t.max_breaks-active_count) else 0 end;
   -- Une réduction de capacité révoque d'abord les réservations les plus récentes.
   update break_app.requests set status='waiting',offered_at=null,offer_expires_at=null
   where id in (select id from break_app.requests where team_id=t.id and status='offered' order by requested_at,id offset capacity);
   select count(*) into reserved_count from break_app.requests where team_id=t.id and status='offered';
   update break_app.requests set status='offered',offered_at=clock_timestamp(),offer_expires_at=clock_timestamp()+make_interval(secs=>t.offer_seconds)
   where id in (select id from break_app.requests where team_id=t.id and status='waiting' order by requested_at,id limit greatest(0,capacity-reserved_count));
 end loop;
end $$;
create function break_app.maintenance() returns void
language plpgsql security definer set search_path='' as $$
begin
 perform break_app.reconcile();
 delete from break_app.requests where ended_at<clock_timestamp()-interval '90 days';
 delete from break_app.audit where occurred_at<clock_timestamp()-interval '90 days';
end $$;
create function break_app.state(p_team uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare m break_app.members; t break_app.teams; result jsonb; latest jsonb;
begin
 m:=break_app.require_member();
 if p_team is not null and p_team<>m.team_id and m.role<>'admin' then raise exception 'Équipe non autorisée.' using errcode='42501'; end if;
 perform break_app.reconcile();
 select * into t from break_app.teams where id=coalesce(p_team,m.team_id);
 if t.id is null then raise exception 'Équipe introuvable.'; end if;
 select to_jsonb(r) into latest from break_app.requests r where r.user_id=m.user_id order by id desc limit 1;
 result:=jsonb_build_object('serverNow',clock_timestamp(),'member',to_jsonb(m),'team',to_jsonb(t),'open',break_app.is_open(t),
   'teams',(select coalesce(jsonb_agg(to_jsonb(a) order by a.name),'[]') from break_app.teams a where m.role='admin' or a.id=m.team_id),
   'requests',(select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'name',r.display_name,'status',r.status,'requestedAt',r.requested_at,'offeredAt',r.offered_at,'offerExpiresAt',r.offer_expires_at,'startedAt',r.started_at,'dueAt',r.due_at,'mine',r.user_id=m.user_id) order by r.requested_at,r.id),'[]') from break_app.requests r where r.team_id=t.id and r.status in ('waiting','offered','active')),
   'myLatest',latest);
 return result;
end $$;
create function break_app.act(p_action text,p_request_id bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare m break_app.members; r break_app.requests; t break_app.teams; message text;
begin
 m:=break_app.require_member();
 perform pg_advisory_xact_lock(7483922);
 perform break_app.reconcile();
 select * into t from break_app.teams where id=m.team_id;
 if p_action='request' then
   if exists(select 1 from break_app.requests where user_id=m.user_id and status in ('waiting','offered','active')) then
     return break_app.state()||jsonb_build_object('message','Votre demande est déjà enregistrée.');
   end if;
   if not break_app.is_open(t) then raise exception 'Les départs sont suspendus ou hors plage horaire.'; end if;
   if exists(select 1 from break_app.requests where user_id=m.user_id and requested_at>clock_timestamp()-interval '5 seconds')
      or (select count(*) from break_app.requests where user_id=m.user_id and requested_at>clock_timestamp()-interval '1 hour')>=10 then
     raise exception 'Trop de demandes rapprochées. Patientez avant de réessayer.';
   end if;
   insert into break_app.requests(user_id,team_id,display_name,status) values(m.user_id,m.team_id,m.display_name,'waiting');
   message:='Demande enregistrée.';
 elsif p_action in ('accept','cancel','return') then
   select * into r from break_app.requests where id=p_request_id and user_id=m.user_id;
   if r.id is null then raise exception 'Cette demande ne vous appartient pas.' using errcode='42501'; end if;
   if p_action='accept' then
     if r.status<>'offered' then
       return break_app.state()||jsonb_build_object('message','Cette proposition a expiré ou a été retirée. Consultez votre statut.');
     end if;
     if not break_app.is_open(t) or (select count(*) from break_app.requests where team_id=t.id and status='active')>=t.max_breaks then
       return break_app.state()||jsonb_build_object('message','Aucune place disponible. Votre statut a été actualisé.');
     end if;
     update break_app.requests set status='active',started_at=clock_timestamp(),due_at=clock_timestamp()+make_interval(mins=>t.break_minutes) where id=r.id;
     message:='Bon repos ! Confirmez votre retour en revenant.';
   elsif p_action='return' then
     if r.status<>'active' then return break_app.state()||jsonb_build_object('message','Votre retour a déjà été enregistré ou la pause a été clôturée.'); end if;
     update break_app.requests set status='completed',ended_at=clock_timestamp(),ended_by=m.user_id,reason='retour_conseiller' where id=r.id;
     message:='Retour enregistré. Merci !';
   else
     if r.status not in ('waiting','offered') then return break_app.state()||jsonb_build_object('message','Cette demande ne peut plus être annulée.'); end if;
     update break_app.requests set status='cancelled',ended_at=clock_timestamp(),ended_by=m.user_id,reason='annulation_conseiller' where id=r.id;
     message:='Demande annulée. Vous pouvez en refaire une plus tard.';
   end if;
 else raise exception 'Action inconnue.';
 end if;
 return break_app.state()||jsonb_build_object('message',message);
end $$;
create function break_app.save_team(p_team uuid,p_values jsonb,p_revision int) returns jsonb
language plpgsql security definer set search_path='' as $$
declare t break_app.teams;
begin
 perform break_app.require_admin(); perform pg_advisory_xact_lock(7483922);
 if p_team is null then
   insert into break_app.teams(name) values(trim(p_values->>'name')) returning * into t;
 else
   select * into t from break_app.teams where id=p_team;
   if t.id is null then raise exception 'Équipe introuvable.'; end if;
   if t.revision is distinct from p_revision then raise exception 'Les paramètres ont été modifiés par un autre pilote. Rechargez-les avant d’enregistrer.'; end if;
 end if;
 update break_app.teams set name=trim(p_values->>'name'),max_breaks=(p_values->>'max_breaks')::int,
 break_minutes=(p_values->>'break_minutes')::int,offer_seconds=(p_values->>'offer_seconds')::int,
 suspended=(p_values->>'suspended')::boolean,opens=(p_values->>'opens')::time,closes=(p_values->>'closes')::time,
 weekdays=array(select jsonb_array_elements_text(p_values->'weekdays')::int),revision=revision+1 where id=t.id;
 insert into break_app.audit(actor,action,details) values(auth.uid(),'parametres_equipe',jsonb_build_object('team',t.id,'before',to_jsonb(t),'after',p_values));
 return break_app.state(t.id)||jsonb_build_object('message','Paramètres enregistrés. Les pauses commencées gardent leur durée.');
end $$;
create function break_app.admin_action(p_action text,p_team uuid,p_request_id bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare changed int;
begin
 perform break_app.require_admin(); perform pg_advisory_xact_lock(7483922);
 if p_action not in ('remove','clear_queue','reset') then raise exception 'Action inconnue.'; end if;
 update break_app.requests set status=case when status='active' then 'completed' else 'cancelled' end,
 ended_at=clock_timestamp(),ended_by=auth.uid(),reason='pilotage_'||p_action
 where team_id=p_team and status in ('waiting','offered','active') and
 ((p_action='remove' and id=p_request_id) or (p_action='clear_queue' and status in ('waiting','offered')) or p_action='reset');
 get diagnostics changed=row_count;
 insert into break_app.audit(actor,action,details) values(auth.uid(),p_action,jsonb_build_object('team',p_team,'request',p_request_id,'count',changed));
 return break_app.state(p_team)||jsonb_build_object('message',changed||' élément(s) mis à jour.');
end $$;
create function break_app.members_list() returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 perform break_app.require_admin();
 return coalesce((select jsonb_agg(to_jsonb(m)||jsonb_build_object('email',u.email) order by m.display_name) from break_app.members m join auth.users u on u.id=m.user_id),'[]');
end $$;
create function break_app.save_member(p_email text,p_name text,p_team uuid,p_role text,p_enabled boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare target uuid; previous break_app.members;
begin
 perform break_app.require_admin(); perform pg_advisory_xact_lock(7483922);
 select id into target from auth.users where lower(email)=lower(trim(p_email));
 if target is null then raise exception 'Compte introuvable. Créez d’abord ce compte dans Supabase Authentication.'; end if;
 select * into previous from break_app.members where user_id=target;
 if target=auth.uid() and (not p_enabled or p_role<>'admin') then raise exception 'Vous ne pouvez pas retirer votre propre accès administrateur.'; end if;
 if exists(select 1 from break_app.requests where user_id=target and status in ('active','waiting','offered')) and (not p_enabled or previous.team_id is distinct from p_team) then
   raise exception 'Clôturez la demande ou la pause de ce conseiller avant ce changement.';
 end if;
 insert into break_app.members(user_id,display_name,team_id,role,enabled)
 values(target,regexp_replace(trim(p_name),'\s+',' ','g'),p_team,p_role,p_enabled)
 on conflict(user_id) do update set display_name=excluded.display_name,team_id=excluded.team_id,role=excluded.role,enabled=excluded.enabled;
 insert into break_app.audit(actor,action,details) values(auth.uid(),'membre',jsonb_build_object('user',target,'role',p_role,'enabled',p_enabled));
 return break_app.members_list();
end $$;
create function break_app.history(p_team uuid,p_days int default 7) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 perform break_app.require_admin();
 if p_days not between 1 and 90 then raise exception 'Période invalide.'; end if;
 return jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(q)) from (
  select r.*,t.name as team_name from break_app.requests r join break_app.teams t on t.id=r.team_id
  where r.team_id=p_team and r.requested_at>=clock_timestamp()-make_interval(days=>p_days) order by r.requested_at desc,r.id desc limit 5000
 ) q),'[]'),'total',(select count(*) from break_app.requests where team_id=p_team and requested_at>=clock_timestamp()-make_interval(days=>p_days)),
 'audit',coalesce((select jsonb_agg(to_jsonb(q)) from (select a.occurred_at,a.action,a.details,m.display_name as actor from break_app.audit a left join break_app.members m on m.user_id=a.actor where a.occurred_at>=clock_timestamp()-make_interval(days=>p_days) order by a.id desc limit 100) q),'[]'));
end $$;
-- RPC publiques sans élévation de droits ; les points d'entrée privés vérifient auth.uid().
create function public.ba_state(p_team uuid default null) returns jsonb language sql security invoker set search_path='' as $$ select break_app.state(p_team) $$;
create function public.ba_act(p_action text,p_request_id bigint default null) returns jsonb language sql security invoker set search_path='' as $$ select break_app.act(p_action,p_request_id) $$;
create function public.ba_save_team(p_team uuid,p_values jsonb,p_revision int) returns jsonb language sql security invoker set search_path='' as $$ select break_app.save_team(p_team,p_values,p_revision) $$;
create function public.ba_admin_action(p_action text,p_team uuid,p_request_id bigint default null) returns jsonb language sql security invoker set search_path='' as $$ select break_app.admin_action(p_action,p_team,p_request_id) $$;
create function public.ba_members() returns jsonb language sql security invoker set search_path='' as $$ select break_app.members_list() $$;
create function public.ba_save_member(p_email text,p_name text,p_team uuid,p_role text,p_enabled boolean) returns jsonb language sql security invoker set search_path='' as $$ select break_app.save_member(p_email,p_name,p_team,p_role,p_enabled) $$;
create function public.ba_history(p_team uuid,p_days int default 7) returns jsonb language sql security invoker set search_path='' as $$ select break_app.history(p_team,p_days) $$;
revoke all on all functions in schema break_app from public,anon,authenticated;
grant execute on function break_app.state(uuid),break_app.act(text,bigint),break_app.save_team(uuid,jsonb,int),break_app.admin_action(text,uuid,bigint),break_app.members_list(),break_app.save_member(text,text,uuid,text,boolean),break_app.history(uuid,int) to authenticated;
revoke all on function public.ba_state(uuid),public.ba_act(text,bigint),public.ba_save_team(uuid,jsonb,int),public.ba_admin_action(text,uuid,bigint),public.ba_members(),public.ba_save_member(text,text,uuid,text,boolean),public.ba_history(uuid,int) from public,anon,authenticated;
grant execute on function public.ba_state(uuid),public.ba_act(text,bigint),public.ba_save_team(uuid,jsonb,int),public.ba_admin_action(text,uuid,bigint),public.ba_members(),public.ba_save_member(text,text,uuid,text,boolean),public.ba_history(uuid,int) to authenticated;
insert into break_app.teams(name) values('Équipe de test');
commit;
