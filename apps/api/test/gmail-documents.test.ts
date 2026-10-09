import {test} from 'node:test';
import assert from 'node:assert/strict';
import {setupGold} from './helpers/database';
import {gmailRoutes} from '../src/gmail';
import {digest,encrypt} from '../src/zerodha';
const at=new Date('2026-10-10T00:00:00Z');
async function setup(){
 const {env:base,db}=setupGold(),key=Buffer.alloc(32,1).toString('base64'),token='a'.repeat(64);
 db.prepare('INSERT INTO zerodha_sessions VALUES(?,?,?,?,?)').run(await digest(token),'unused','owner',at.getTime()+86400000,0);
 const env={...base,KITE_ENCRYPTION_KEY:key,GMAIL_CLIENT_ID:'client',GMAIL_CLIENT_SECRET:'secret'} as any;
 db.prepare('INSERT INTO gmail_connections(owner_id,email,encrypted_refresh_token,connected_at) VALUES(?,?,?,?)').run('owner','example@example.com',await encrypt('refresh',key),0);
 for(const table of ['gullak_settings','hdfc_settings','nps_settings'])db.prepare(`INSERT INTO ${table}(owner_id,encrypted_password,updated_at) VALUES(?,?,?)`).run('owner',await encrypt('123456789012',key),0);
 const fetcher:typeof fetch=async url=>String(url).includes('oauth2')?Response.json({access_token:'access'}):decodeURIComponent(String(url)).includes('hdfc')?new Response('',{status:503}):Response.json({messages:[]});
 const app=gmailRoutes(fetcher,()=>at.getTime());
 const request=(body?:unknown,auth=true)=>app.request('/sync',{method:'POST',headers:{'Content-Type':'application/json',...(auth?{Authorization:'Bearer '+token}:{})},body:body?JSON.stringify(body):undefined},env);
 return {request,db};
}
test('one Gmail sync discovers only this owner’s enabled document sources and requires sign-in',async()=>{
 const {request,db}=await setup();
 assert.equal((await request(undefined,false)).status,401);
 db.prepare("DELETE FROM hdfc_settings WHERE owner_id='owner'").run();
 db.prepare("INSERT INTO hdfc_settings(owner_id,encrypted_password,updated_at) VALUES('other','private',0)").run();
 assert.deepEqual((await (await request()).json()).sources,['gold','nps']);
 assert.equal((await request({source:'hdfc'})).status,409);
 assert.equal((await request({source:'trades'})).status,400);
});
test('a failed source returns an isolated result and other Gmail sources still sync',async()=>{
 const {request,db}=await setup();
 const sources=(await (await request()).json()).sources;
 const results=[];for(const source of sources)results.push(await (await request({source})).json());
 assert.deepEqual(results.map(r=>r.source),['gold','hdfc','nps']);
 assert.equal(results[0].status,'up_to_date');assert.equal(results[0].pending,false);
 assert.equal(results[1].status,'failed');assert.ok(results[1].error);assert.equal(results[1].pending,false);
 assert.equal(results[2].status,'up_to_date');assert.equal(results[2].pending,false);
 assert.equal(db.prepare("SELECT last_sync_at FROM nps_settings WHERE owner_id='owner'").get()?.last_sync_at,at.getTime());
 assert.ok(!JSON.stringify(results).includes('123456789012'));
});
test('gold and HDFC document batches continue beyond ten already-imported messages',async()=>{
 const {env:base,db}=setupGold(),key=Buffer.alloc(32,1).toString('base64'),token='c'.repeat(64);
 db.prepare('INSERT INTO zerodha_sessions VALUES(?,?,?,?,?)').run(await digest(token),'unused','owner',at.getTime()+86400000,0);
 const env={...base,KITE_ENCRYPTION_KEY:key,GMAIL_CLIENT_ID:'client',GMAIL_CLIENT_SECRET:'secret'} as any;
 db.prepare('INSERT INTO gmail_connections(owner_id,email,encrypted_refresh_token,connected_at) VALUES(?,?,?,?)').run('owner','example@example.com',await encrypt('refresh',key),0);
 for(const kind of ['gullak','hdfc']){
  db.prepare(`INSERT INTO ${kind}_settings(owner_id,encrypted_password,updated_at) VALUES(?,?,?)`).run('owner',await encrypt('12345678',key),0);
  for(let i=0;i<10;i++)db.prepare(`INSERT INTO ${kind}_imports(owner_id,content_hash,message_id,status,imported_at${kind==='gullak'?',parser_version':''}) VALUES(?,?,?,'imported',0${kind==='gullak'?',2':''})`).run('owner','h'+i,'m'+i);
 }
 const fetcher:typeof fetch=async url=>String(url).includes('oauth2')?Response.json({access_token:'access'}):String(url).includes('pageToken=next')?Response.json({messages:[]}):Response.json({messages:Array.from({length:10},(_,i)=>({id:'m'+i})),nextPageToken:'next'});
 const app=gmailRoutes(fetcher,()=>at.getTime());
 for(const source of ['gold','hdfc']){
  const call=()=>app.request('/sync',{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify({source})},env);
  assert.equal((await (await call()).json()).pending,true);
  assert.equal((await (await call()).json()).pending,false);
 }
});

test('the unified sync discovers and executes configured bond imports',async()=>{
 const {request,db}=await setup();
 db.prepare("INSERT INTO bonds_settings(owner_id,encrypted_password,updated_at) VALUES('owner','unused',0)").run();
 assert.deepEqual((await (await request()).json()).sources,['gold','hdfc','nps','bonds']);
 assert.deepEqual(await (await request({source:'bonds'})).json(),{source:'bonds',imported:0,status:'up_to_date',pending:false,error:null});
});
