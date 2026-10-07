begin;
-- One request per poll. Reuse authorization and hash every observable field except time.
create or replace function break_app.poll(p_team uuid default null, p_version text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare snapshot jsonb; version text;
begin
 snapshot := break_app.state(p_team);
 version := md5((snapshot - 'serverNow')::text);
 if version = p_version then
  return jsonb_build_object('serverNow',snapshot->'serverNow','version',version,'unchanged',true);
 end if;
 return jsonb_build_object('serverNow',snapshot->'serverNow','version',version,'state',snapshot);
end $$;
create or replace function public.ba_poll(p_team uuid default null, p_version text default null) returns jsonb
language sql security invoker set search_path='' as $$ select break_app.poll(p_team,p_version) $$;
revoke all on function break_app.poll(uuid,text), public.ba_poll(uuid,text) from public,anon,authenticated;
grant execute on function break_app.poll(uuid,text), public.ba_poll(uuid,text) to authenticated;
commit;
