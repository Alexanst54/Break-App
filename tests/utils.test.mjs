import {test} from 'node:test';
import assert from 'node:assert/strict';
import {csvCell,csv,duration,serialQueue,metrics} from '../src/utils.js';
import {config,validateConfig} from '../src/config.js';
test('isolation : configuration de production refusée',()=>{assert.doesNotThrow(()=>validateConfig());assert.throws(()=>validateConfig({...config,url:'https://ferxlbwivyyfhnwgmcja.supabase.co'}),/bloquée/);assert.throws(()=>validateConfig({...config,publishableKey:'sb_secret_invalid'}));});
test('export CSV neutralise les formules et respecte les cellules',()=>{assert.equal(csvCell('=1+1'),'"\'=1+1"');assert.equal(csvCell(' \t@SUM(1)'),'"\' \t@SUM(1)"');assert.equal(csvCell('A"B'),'"A""B"');assert.ok(csv([]).startsWith('\uFEFF'));});
test('les RPC se succèdent même après un échec',async()=>{const queue=serialQueue(),order=[];const a=queue(async()=>{await new Promise(r=>setTimeout(r,15));order.push('a');throw Error('offline');});const b=queue(async()=>order.push('b'));await assert.rejects(a);await b;assert.deepEqual(order,['a','b']);});
test('compteurs et indicateurs',()=>{assert.equal(duration(-61000),'1:01');const m=metrics([{requested_at:'2026-10-01T10:00:00Z',started_at:'2026-10-01T10:05:00Z',due_at:'2026-10-01T10:20:00Z',ended_at:'2026-10-01T10:21:00Z'}]);assert.deepEqual(m,{requests:1,completed:1,averageWait:300000,overdue:1});});
