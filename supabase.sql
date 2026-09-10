-- ============================================================
-- PAUSE CONSEILLERS - SUPABASE
-- À exécuter dans Supabase > SQL Editor
-- ============================================================

create extension if not exists pgcrypto;

create table if not exists public.pause_breaks (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  start_time timestamptz not null default now()
);

create table if not exists public.pause_queue (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  request_time timestamptz not null default now()
);

create unique index if not exists pause_breaks_name_lower_idx
  on public.pause_breaks (lower(name));

create unique index if not exists pause_queue_name_lower_idx
  on public.pause_queue (lower(name));

-- Important : les conseillers ne doivent pas accéder directement aux tables.
alter table public.pause_breaks enable row level security;
alter table public.pause_queue enable row level security;

revoke all on table public.pause_breaks from anon, authenticated;
revoke all on table public.pause_queue from anon, authenticated;

-- ------------------------------------------------------------
-- Fonction interne : nettoie les pauses > 15 min et fait
-- remonter automatiquement la file d'attente.
-- ------------------------------------------------------------
create or replace function public.reconcile_pauses()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  next_person record;
begin
  -- Verrou logique : évite que deux conseillers modifient
  -- l'état simultanément.
  perform pg_advisory_xact_lock(7483921);

  delete from public.pause_breaks
  where start_time <= now() - interval '15 minutes';

  while (select count(*) from public.pause_breaks) < 7 loop
    select id, name
      into next_person
      from public.pause_queue
      order by request_time asc
      limit 1;

    exit when not found;

    delete from public.pause_queue where id = next_person.id;

    insert into public.pause_breaks(name, start_time)
    values (next_person.name, now());
  end loop;
end;
$$;

-- ------------------------------------------------------------
-- Retourne l'état complet de la page.
-- ------------------------------------------------------------
create or replace function public.get_pause_state()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  breaks jsonb;
  waiting jsonb;
begin
  perform public.reconcile_pauses();

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'name', name,
      'startTime', start_time
    ) order by start_time
  ), '[]'::jsonb)
  into breaks
  from public.pause_breaks;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'name', name,
      'requestTime', request_time
    ) order by request_time
  ), '[]'::jsonb)
  into waiting
  from public.pause_queue;

  return jsonb_build_object(
    'activeBreaks', breaks,
    'queue', waiting
  );
end;
$$;

-- ------------------------------------------------------------
-- Demande de pause.
-- Si une place est libre : pause immédiate.
-- Sinon : file d'attente.
-- ------------------------------------------------------------
create or replace function public.request_pause(p_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_name text := regexp_replace(trim(coalesce(p_name,'')), '\s+', ' ', 'g');
begin
  perform public.reconcile_pauses();

  if clean_name = '' then
    raise exception 'Le prénom est obligatoire';
  end if;

  if length(clean_name) > 30 then
    raise exception 'Le prénom est trop long';
  end if;

  if exists (
    select 1 from public.pause_breaks
    where lower(name) = lower(clean_name)
  ) then
    return public.get_pause_state();
  end if;

  if exists (
    select 1 from public.pause_queue
    where lower(name) = lower(clean_name)
  ) then
    return public.get_pause_state();
  end if;

  if (select count(*) from public.pause_breaks) < 7 then
    insert into public.pause_breaks(name, start_time)
    values (clean_name, now());
  else
    insert into public.pause_queue(name, request_time)
    values (clean_name, now());
  end if;

  return public.get_pause_state();
end;
$$;

-- ------------------------------------------------------------
-- Si la personne est en pause : retour anticipé.
-- Si elle est dans la file : annulation.
-- ------------------------------------------------------------
create or replace function public.cancel_or_return(p_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_name text := regexp_replace(trim(coalesce(p_name,'')), '\s+', ' ', 'g');
begin
  perform public.reconcile_pauses();

  delete from public.pause_breaks
  where lower(name) = lower(clean_name);

  delete from public.pause_queue
  where lower(name) = lower(clean_name);

  perform public.reconcile_pauses();

  return public.get_pause_state();
end;
$$;

-- Les fonctions sont accessibles depuis la page GitHub.
grant execute on function public.get_pause_state() to anon, authenticated;
grant execute on function public.request_pause(text) to anon, authenticated;
grant execute on function public.cancel_or_return(text) to anon, authenticated;

-- Vérification facultative :
-- select public.get_pause_state();

-- ============================================================
-- ADMINISTRATION
-- Pour vider toutes les pauses depuis le SQL Editor :
--
-- delete from public.pause_breaks;
-- delete from public.pause_queue;
--
-- Ne mettez PAS de clé service_role dans index.html.
-- ============================================================
