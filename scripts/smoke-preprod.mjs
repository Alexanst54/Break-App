// Test volontairement limité à la référence de préproduction ; mot de passe reçu sur stdin.
import {createClient} from '@supabase/supabase-js';
import assert from 'node:assert/strict';
import {config,validateConfig} from '../src/config.js';
validateConfig();
let input='';for await(const chunk of process.stdin)input+=chunk;
const {password}=JSON.parse(input);
const clients=[];
async function call(client,name,args={}){const {data,error}=await client.rpc(name,args).abortSignal(AbortSignal.timeout(15000));if(error)throw Error(`${name}: ${error.message}`);return data;}
try {
 for(const email of ['pilotage@break-app.test','conseiller1@break-app.test','conseiller2@break-app.test']){
  const c=createClient(config.url,config.publishableKey,{auth:{persistSession:false,autoRefreshToken:false}});clients.push(c);
  const {error}=await c.auth.signInWithPassword({email,password});if(error)throw Error('Connexion compte de test : '+error.message);
 }
 const [admin,a,b]=clients;
 let s=await call(admin,'ba_state');const team=s.team.id;const original={...s.team};
 await call(admin,'ba_admin_action',{p_action:'reset',p_team:team});
 s=await call(admin,'ba_save_team',{p_team:team,p_values:{...original,max_breaks:1,suspended:false,opens:'00:00',closes:'23:59:59',weekdays:[1,2,3,4,5,6,7]},p_revision:s.team.revision});
 const both=await Promise.all([call(a,'ba_act',{p_action:'request'}),call(b,'ba_act',{p_action:'request'})]);
 const current=await call(admin,'ba_state');assert.equal(current.requests.filter(r=>r.status==='offered').length,1);assert.equal(current.requests.filter(r=>r.status==='waiting').length,1);
 const ai=(await call(a,'ba_state')).myLatest;const bi=(await call(b,'ba_state')).myLatest;
 const owner=ai.status==='offered'?a:b,other=owner===a?b:a,offer=ai.status==='offered'?ai:bi;
 const denied=await other.rpc('ba_act',{p_action:'accept',p_request_id:offer.id});assert.ok(denied.error);
 const active=await call(owner,'ba_act',{p_action:'accept',p_request_id:offer.id});assert.equal(active.myLatest.status,'active');
 const forbidden=await other.rpc('ba_admin_action',{p_action:'reset',p_team:team});assert.ok(forbidden.error);
 await call(owner,'ba_act',{p_action:'return',p_request_id:offer.id});assert.equal((await call(other,'ba_state')).myLatest.status,'offered');
 const anonymous=createClient(config.url,config.publishableKey,{auth:{persistSession:false}});const publicRead=await anonymous.rpc('ba_state');assert.ok(publicRead.error);
 await call(admin,'ba_admin_action',{p_action:'reset',p_team:team});
 s=await call(admin,'ba_state');await call(admin,'ba_save_team',{p_team:team,p_values:original,p_revision:s.team.revision});
 assert.ok((await call(admin,'ba_history',{p_team:team,p_days:1})).total>=2);
 console.log('PASS : Auth réelle, RPC, concurrence, capacité, propriété, droits administrateur, refus anonyme, FIFO et historique. Paramètres restaurés ; demandes de test clôturées.');
}finally{await Promise.allSettled(clients.map(c=>c.auth.signOut({scope:'local'})));}
