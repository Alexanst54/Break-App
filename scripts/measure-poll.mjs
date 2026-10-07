// Read-only preproduction check. Credentials arrive over stdin, never stored.
import {createClient} from '@supabase/supabase-js';
import assert from 'node:assert/strict';
import {config,validateConfig} from '../src/config.js';
validateConfig();
let input='';for await(const chunk of process.stdin)input+=chunk;
const client=createClient(config.url,config.publishableKey,{auth:{persistSession:false,autoRefreshToken:false}});
const {error}=await client.auth.signInWithPassword({email:'conseiller1@break-app.test',password:JSON.parse(input).password});
if(error)throw error;
try{
 const first=await client.rpc('ba_poll',{p_team:null,p_version:null});
 if(first.error)throw first.error;
 const times=[],sizes=[];
 for(let batch=0;batch<8;batch++)await Promise.all(Array.from({length:10},async()=>{
  const start=performance.now();
  const {data,error}=await client.rpc('ba_poll',{p_team:null,p_version:first.data.version}).abortSignal(AbortSignal.timeout(15000));
  if(error)throw error;
  assert.equal(data.unchanged,true);
  times.push(performance.now()-start);sizes.push(Buffer.byteLength(JSON.stringify(data)));
 }));
 times.sort((a,b)=>a-b);
 console.log(JSON.stringify({requests:80,concurrency:10,distinctUsers:1,fullStateBytes:Buffer.byteLength(JSON.stringify(first.data.state)),unchangedMeanBytes:sizes.reduce((a,b)=>a+b)/80,p95ms:Math.round(times[75]),maxMs:Math.round(times[79])}));
}finally{await client.auth.signOut({scope:'local'});}
