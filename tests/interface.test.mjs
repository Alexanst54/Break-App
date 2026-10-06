import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {JSDOM} from 'jsdom';
import {config,validateConfig} from '../src/config.js';
import {duration,labels,csv,metrics,serialQueue} from '../src/utils.js';
const source=(await readFile('src/app.js','utf8')).replace(/^import .*;\n/gm,'');
const html=await readFile('index.html','utf8');
const wait=()=>new Promise(r=>setTimeout(r,20));
async function harness(authenticated=false){
 const dom=new JSDOM(html,{url:'https://preprod.example.test'}),w=dom.window;
 const team={id:'team-test',name:'Équipe test',max_breaks:1,break_minutes:15,offer_seconds:60,suspended:false,opens:'00:00:00',closes:'23:59:59',weekdays:[1,2,3,4,5,6,7],revision:1};
 let state={serverNow:new Date().toISOString(),member:{display_name:'Pilote test',role:'admin',team_id:team.id},team,teams:[team],requests:[],myLatest:null,open:true};
 const session={access_token:'test',user:{email:'test@example.test'}};const calls=[];let hold=null;
 const client={auth:{onAuthStateChange(){},async getSession(){return{data:{session:authenticated?session:null}};},async signInWithPassword(){return{data:{session}};},async signOut(){return{};}},rpc(name,args){calls.push([name,args]);return{async abortSignal(){if(hold)await hold;
  if(name==='ba_members')return{data:[]};
  if(name==='ba_act'){const status=args.p_action==='request'?'offered':args.p_action==='accept'?'active':'completed';state.myLatest={id:1,status,offer_expires_at:new Date(Date.now()+60000).toISOString(),due_at:new Date(Date.now()+900000).toISOString()};state.requests=status==='completed'?[]:[{id:1,name:'Pilote test',mine:true,status,requestedAt:new Date().toISOString(),offerExpiresAt:state.myLatest.offer_expires_at,dueAt:state.myLatest.due_at}];}
  return{data:structuredClone(state)};
 }}}};
 const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
 await new AsyncFunction('window','document','localStorage','createClient','config','validateConfig','duration','labels','csv','metrics','serialQueue','setTimeout','clearTimeout','setInterval','confirm',source)(w,w.document,w.localStorage,()=>client,config,validateConfig,duration,labels,csv,metrics,serialQueue,()=>0,()=>{},()=>0,()=>true);
 return{dom,w,calls,get state(){return state},setHold(value){hold=value;},close(){w.close();}};
}
test('interface : connexion, demande, départ, retour et blocage des doubles clics',async()=>{
 const h=await harness(),d=h.w.document;try{
  assert.equal(d.getElementById('auth').hidden,false);assert.equal(d.getElementById('app').hidden,true);
  d.getElementById('email').value='test@example.test';d.getElementById('password').value='test-password';d.getElementById('loginForm').dispatchEvent(new h.w.Event('submit',{cancelable:true}));await wait();
  assert.equal(d.getElementById('password').value,'');assert.equal(d.getElementById('app').hidden,false);
  let release;h.setHold(new Promise(r=>release=r));d.getElementById('action').click();d.getElementById('action').click();await wait();
  assert.equal(h.calls.filter(([name])=>name==='ba_act').length,1);assert.equal(d.getElementById('action').disabled,true);release();h.setHold(null);await wait();
  assert.match(d.getElementById('action').textContent,/Je pars/);d.getElementById('action').click();await wait();assert.match(d.getElementById('action').textContent,/retour/);
  d.getElementById('action').click();await wait();assert.equal(d.getElementById('activeCount').textContent,'0');
 }finally{h.close();}
});
test('interface : saisies pilotage préservées pendant un rafraîchissement',async()=>{
 const h=await harness(true),d=h.w.document;try{
  d.getElementById('adminTab').click();await wait();assert.equal(d.getElementById('adminView').hidden,false);
  const field=d.getElementById('settingsForm').elements.max_breaks;field.value='5';field.dispatchEvent(new h.w.Event('input',{bubbles:true}));
  d.getElementById('refresh').click();await wait();assert.equal(field.value,'5');assert.equal(d.getElementById('dirtyLabel').hidden,false);
  d.getElementById('discardSettings').click();assert.equal(field.value,'1');
 }finally{h.close();}
});
