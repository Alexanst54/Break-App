import { test } from 'node:test';
import assert from 'node:assert/strict';
import { PGlite } from '@electric-sql/pglite';
import { readFile, readdir } from 'node:fs/promises';
const migration = (await readdir('supabase/migrations')).find(x=>x.endsWith('_break_app_preprod_v2.sql'));
const sql = await readFile(`supabase/migrations/${migration}`,'utf8');
const ids = ['00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000004'];
async function fixture() {
 const db=new PGlite();
 await db.exec(`create role anon; create role authenticated; create schema auth; create table auth.users(id uuid primary key,email text); create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$; grant usage on schema auth to authenticated; grant execute on function auth.uid() to authenticated;`);
 await db.exec(sql);
 const team=(await db.query('select id from break_app.teams')).rows[0].id;
 for(let i=0;i<4;i++) {
  await db.query('insert into auth.users values($1,$2)',[ids[i],`test${i}@example.test`]);
  if(i<3) await db.query('insert into break_app.members(user_id,display_name,team_id,role) values($1,$2,$3,$4)',[ids[i],`Test ${i}`,team,i===0?'admin':'advisor']);
 }
 await db.query('update break_app.teams set max_breaks=1');
 const rpc=async(i,name,args=[])=>{
  await db.exec('set role authenticated');
  await db.query("select set_config('request.jwt.claim.sub',$1,false)",[ids[i]]);
  try{return (await db.query(`select public.${name}(${args.map((_,j)=>'$'+(j+1)).join(',')}) as data`,args)).rows[0].data;}
  finally{await db.exec('reset role');}
 };
 return {db,team,rpc};
}
test('auth, FIFO, propriété, capacité, retour réel et idempotence',async()=>{
 const {db,team,rpc}=await fixture();
 try{
  await db.exec('set role anon');
  await assert.rejects(db.query('select public.ba_state()'),/permission denied/);
  await db.exec('reset role');
  await assert.rejects(rpc(3,'ba_state'),/Compte non autorisé/);
  await assert.rejects(rpc(1,'ba_admin_action',['reset',team,null]),/pilotage/);
  const a=await rpc(1,'ba_act',['request',null]);const aid=a.myLatest.id;
  assert.equal(a.myLatest.status,'offered');
  const twice=await rpc(1,'ba_act',['request',null]);assert.equal(twice.myLatest.id,aid);
  const b=await rpc(2,'ba_act',['request',null]);assert.equal(b.myLatest.status,'waiting');
  await assert.rejects(rpc(2,'ba_act',['accept',aid]),/appartient/);
  const active=await rpc(1,'ba_act',['accept',aid]);assert.equal(active.myLatest.status,'active');
  await db.query("update break_app.requests set started_at=clock_timestamp()-interval '20 minutes',due_at=clock_timestamp()-interval '5 minutes' where id=$1",[aid]);
  const overdue=await rpc(1,'ba_state');assert.equal(overdue.myLatest.status,'active');
  assert.equal((await rpc(2,'ba_state')).myLatest.status,'waiting');
  await rpc(1,'ba_act',['return',aid]);
  assert.equal((await rpc(2,'ba_state')).myLatest.status,'offered');
  await rpc(1,'ba_act',['return',aid]);
  const history=await rpc(0,'ba_history',[team,7]);assert.equal(history.rows.find(r=>r.id===aid).reason,'retour_conseiller');
  await db.exec('set role authenticated');await assert.rejects(db.query('select * from break_app.requests'),/permission denied/);await db.exec('reset role');
 }finally{await db.close();}
});
test('réglages : durée figée, réduction capacité, concurrence optimiste et suspension',async()=>{
 const {db,team,rpc}=await fixture();
 try{
  let s=await rpc(0,'ba_state');
  const save=(values,rev=s.team.revision)=>rpc(0,'ba_save_team',[team,{...s.team,...values},rev]);
  s=await save({max_breaks:2});
  let a=await rpc(1,'ba_act',['request',null]);let b=await rpc(2,'ba_act',['request',null]);
  s=await save({max_breaks:1});
  assert.equal((await rpc(2,'ba_state')).myLatest.status,'waiting');
  a=await rpc(1,'ba_act',['accept',a.myLatest.id]);const deadline=a.myLatest.due_at;
  s=await save({break_minutes:3});assert.equal((await rpc(1,'ba_state')).myLatest.due_at,deadline);
  await assert.rejects(save({max_breaks:9},1),/autre pilote/);
  s=await save({suspended:true});await rpc(1,'ba_act',['return',a.myLatest.id]);
  assert.equal((await rpc(2,'ba_state')).myLatest.status,'waiting');
  await assert.rejects(rpc(1,'ba_act',['request',null]),/suspendus/);
  s=await save({suspended:false});assert.equal((await rpc(2,'ba_state')).myLatest.status,'offered');
 }finally{await db.close();}
});
test('expiration conservée, antispam, désactivation et cloisonnement équipes',async()=>{
 const {db,team,rpc}=await fixture();
 try{
  let s=await rpc(1,'ba_act',['request',null]);
  await db.query("update break_app.requests set offer_expires_at=clock_timestamp()-interval '1 second' where id=$1",[s.myLatest.id]);
  s=await rpc(1,'ba_act',['accept',s.myLatest.id]);assert.equal(s.myLatest.status,'expired');assert.match(s.message,/expiré/);
  await assert.rejects(rpc(1,'ba_act',['request',null]),/rapprochées/);
  const other=(await db.query("insert into break_app.teams(name) values('Autre') returning id")).rows[0].id;
  await assert.rejects(rpc(1,'ba_state',[other]),/Équipe non autorisée/);
  await assert.rejects(rpc(0,'ba_save_member',['test0@example.test','Admin',team,'advisor',true]),/propre accès/);
  await rpc(0,'ba_save_member',['test1@example.test','  Test    Un  ',team,'advisor',false]);
  await assert.rejects(rpc(1,'ba_state'),/Compte non autorisé/);
  assert.equal((await db.query('select display_name from break_app.members where user_id=$1',[ids[1]])).rows[0].display_name,'Test Un');
 }finally{await db.close();}
});
test('migration refuse la base de production V1',async()=>{
 const db=new PGlite();try {await db.exec('create table public.pause_breaks(id int)');await assert.rejects(db.exec(sql),/Installation refusée/);}finally{await db.close();}
});
