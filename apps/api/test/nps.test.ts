import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {parseNPSStatement} from '../src/nps-statement';
import {saveNPSSnapshot,npsPortfolio,trustedNPSMessage,npsRoutes,syncNPS} from '../src/nps';
import {setupGold} from './helpers/database';
import {zerodhaSnapshot} from '../src/zerodha-portfolio';
import {digest,encrypt,decrypt} from '../src/zerodha';
const raw=readFileSync(new URL('./fixtures/nps-statement.txt',import.meta.url),'utf8');
const at=new Date('2026-10-10T00:00:00Z'),key=Buffer.alloc(32,1).toString('base64');
const headers=[{name:'X-Apiheader',value:'SCH_SOT_CRA_123456789012_12345'},{name:'From',value:'KCRA@kfintech.com'},{name:'Subject',value:'Monthly Transaction Statement for your NPS account with KFintech-CRA'},{name:'Authentication-Results',value:'mx.google.com; dmarc=pass header.from=kfintech.com'},{name:'X-Apiheader',value:'SCH_SOT_CRA_123456789012_12345'}];
test('NPS reads only scheme closing balances and reconciles totals and NAV with the valuation date',()=>{
 const value=parseNPSStatement(raw,at);
 assert.equal(value.tier,'I');assert.equal(value.statementDate,'2026-10-04');assert.equal(value.valuationDate,'2026-09-30');assert.equal(value.total,'2000');
 assert.equal(value.schemes.length,2);assert.equal(value.schemes[0].quantity,'100');assert.equal(value.schemes[0].nav,'10');assert.equal(value.schemes[0].value,'1000');
 for(const text of [raw.replace('Total 2000.00','Total 2100.00'),raw.replace('100.0000','101.0000'),raw.replace('30-09-2026','30-10-2026'),raw.replace('50.0000 20.0000 1000.00','broken row'),raw.replace('SCHEME G -','SCHEME E -'),raw.replace('Changes made during selected period',''),raw.replace('4 1500.00 0.00 5.00 2000.00 500.00','4 1500.00 0.00 5.00 2100.00 500.00')])assert.throws(()=>parseNPSStatement(text,at));
});
test('NPS imports replace whole tier snapshots without counting contribution history or storing PRAN',async()=>{
 const {env,db}=setupGold();const parsed=parseNPSStatement(raw,at);
 assert.equal(await saveNPSSnapshot(env,'owner',parsed,'m','h',at),'imported');
 assert.equal(await saveNPSSnapshot(env,'owner',parsed,'m','h',at),'duplicate');
 assert.equal(await saveNPSSnapshot(env,'owner',{...parsed,valuationDate:'2026-08-31'},'old','old',at),'ignored');
 await assert.rejects(()=>saveNPSSnapshot(env,'owner',parsed,'conflict','other',at));
 const base=zerodhaSnapshot('{"status":"success","data":[]}','{"status":"success","data":[]}',at);
 const p=await npsPortfolio(env,base,'owner');assert.equal(p.value,'2000');assert.equal(p.allocation[0].assetClass,'nps');assert.equal(p.holdings[0].gain,null);assert.equal(p.holdings[0].quoteAt,'2026-09-30T00:00:00Z');
 assert.equal((await npsPortfolio(env,p,'owner')).holdings.length,2);assert.equal((await npsPortfolio(env,base,'other')).value,'0');
 assert.ok(!JSON.stringify(db.prepare('SELECT * FROM nps_snapshots').all()).includes('123456789012'));
});
test('NPS requires an authenticated KFintech statement sender and rejects forwarded lookalikes',()=>{
 assert.equal(trustedNPSMessage({headers}),true);
 for(const bad of [headers.filter(h=>h.name!=='Authentication-Results'),headers.map(h=>({...h,value:h.value.replace('dmarc=pass','dmarc=fail')})),headers.map(h=>h.name==='From'?{...h,value:'attacker@example.com'}:h),headers.map(h=>h.name==='Subject'?{...h,value:'Confirmation for subsequent contribution in your NPS account'}:h)])assert.equal(trustedNPSMessage({headers:bad}),false);
});
test('NPS enable and password override are authenticated; password never returned and stopping imports retains balances',async()=>{
 const {env:base,db}=setupGold(),token='f'.repeat(64),env={...base,KITE_ENCRYPTION_KEY:key} as any;
 db.prepare('INSERT INTO zerodha_sessions VALUES(?,?,?,?,?)').run(await digest(token),'unused','owner',at.getTime()+86400000,0);
 const app=npsRoutes(fetch,()=>at.getTime());
 const req=(path:string,method='GET',body?:unknown,auth=true)=>app.request(path,{method,headers:{'Content-Type':'application/json',...(auth?{Authorization:'Bearer '+token}:{})},body:body?JSON.stringify(body):undefined},env);
 assert.equal((await req('/status','GET',undefined,false)).status,401);
 assert.equal((await req('/connection','PUT')).status,200);
 assert.equal((await req('/password','PUT',{password:'wrong'})).status,400);
 assert.equal((await req('/password','PUT',{password:'123456789012'})).status,200);
 assert.equal(await decrypt(String(db.prepare('SELECT encrypted_password FROM nps_settings').get()?.encrypted_password),key),'123456789012');
 assert.ok(!(await (await req('/status')).text()).includes('123456789012'));
 await saveNPSSnapshot(env,'owner',parseNPSStatement(raw,at),'m','h',at);
 assert.equal((await req('/connection','DELETE')).status,200);
 assert.equal(db.prepare('SELECT count(*) AS n FROM nps_snapshots').get()?.n,1);
});
test('NPS Gmail sync discovers the PDF password from verified headers, decrypts, deduplicates and keeps last data on error',async()=>{
 const {env:base,db}=setupGold(),env={...base,KITE_ENCRYPTION_KEY:key,GMAIL_CLIENT_ID:'client',GMAIL_CLIENT_SECRET:'secret'} as any;
 db.prepare('INSERT INTO nps_settings(owner_id,updated_at) VALUES(?,?)').run('owner',0);
 db.prepare('INSERT INTO gmail_connections(owner_id,email,encrypted_refresh_token,connected_at) VALUES(?,?,?,?)').run('owner','example@example.com',await encrypt('refresh',key),0);
 const bytes=readFileSync(new URL('./fixtures/nps-synthetic.pdf',import.meta.url));
 const upstream:typeof fetch=async url=>{
  const address=String(url);
  if(address.includes('oauth2'))return Response.json({access_token:'access'});
  if(address.includes('/attachments/'))return Response.json({data:bytes.toString('base64url')});
  if(address.includes('format=full'))return Response.json({payload:{headers,parts:[{filename:'statement.pdf',mimeType:'application/pdf',body:{attachmentId:'attachment',size:bytes.length}}]}});
  assert.match(decodeURIComponent(address),/KCRA@kfintech.com/i);return Response.json({messages:[{id:'message'}]});
 };
 assert.equal((await syncNPS(env,'owner',upstream,at)).imported,1);
 assert.equal((await syncNPS(env,'owner',upstream,at)).imported,0);
 assert.equal(await decrypt(String(db.prepare('SELECT encrypted_password FROM nps_settings').get()?.encrypted_password),key),'123456789012');
 db.prepare('DELETE FROM nps_imports').run();db.prepare('UPDATE nps_settings SET encrypted_password=?').run(await encrypt('999999999999',key));
 await assert.rejects(()=>syncNPS(env,'owner',upstream,at));
 assert.equal(db.prepare('SELECT total FROM nps_snapshots').get()?.total,'2000');assert.equal(db.prepare('SELECT status FROM nps_imports').get()?.status,'needs_review');
 assert.equal(db.prepare('SELECT lease_until FROM nps_settings').get()?.lease_until,0);
});
test('NPS recovers interrupted bookkeeping, separates tiers, and rejects a cancelled sync',async()=>{
 const {env,db}=setupGold(),parsed=parseNPSStatement(raw,at);
 await saveNPSSnapshot(env,'owner',parsed,'m','h',at);
 db.prepare('DELETE FROM nps_imports').run();
 assert.equal(await saveNPSSnapshot(env,'owner',parsed,'m','h',at),'duplicate');
 assert.equal(db.prepare('SELECT status FROM nps_imports').get()?.status,'imported');
 await saveNPSSnapshot(env,'owner',parseNPSStatement(raw.replaceAll('Tier I','Tier II').replaceAll('TIER I','TIER II'),at),'ii','ii',at);
 assert.equal(db.prepare('SELECT count(*) AS n FROM nps_snapshots').get()?.n,2);
 await assert.rejects(()=>saveNPSSnapshot(env,'owner',{...parsed,valuationDate:'2026-10-01'},'cancelled','cancelled',at,123));
 assert.equal(db.prepare("SELECT valuation_date FROM nps_snapshots WHERE tier='I'").get()?.valuation_date,'2026-09-30');
});
test('cancelling between lease validation and snapshot write cannot mark a PDF imported',async()=>{
 const {env,db}=setupGold();db.prepare('INSERT INTO nps_settings(owner_id,updated_at,lease_until) VALUES(?,?,?)').run('owner',0,123);
 const guarded={DB:{prepare(sql:string){
  const statement=env.DB.prepare(sql);
  const first=statement.first.bind(statement);
  statement.first=async function<T>() {if(sql.startsWith('INSERT INTO nps_snapshots'))db.prepare('DELETE FROM nps_settings').run();return first<T>();};
  return statement;
 }}};
 await assert.rejects(()=>saveNPSSnapshot(guarded,'owner',parseNPSStatement(raw,at),'m','h',at,123));
 assert.equal(db.prepare('SELECT count(*) AS n FROM nps_snapshots').get()?.n,0);
 assert.equal(db.prepare('SELECT count(*) AS n FROM nps_imports').get()?.n,0);
});
test('NPS skips spoofed search matches and scans subsequent pages without unbounded work',async()=>{
 const {env:base,db}=setupGold(),env={...base,KITE_ENCRYPTION_KEY:key,GMAIL_CLIENT_ID:'client',GMAIL_CLIENT_SECRET:'secret'} as any;
 db.prepare('INSERT INTO nps_settings(owner_id,updated_at) VALUES(?,?)').run('owner',0);
 db.prepare('INSERT INTO gmail_connections(owner_id,email,encrypted_refresh_token,connected_at) VALUES(?,?,?,?)').run('owner','example@example.com',await encrypt('refresh',key),0);
 const bytes=readFileSync(new URL('./fixtures/nps-synthetic.pdf',import.meta.url));let pages=0;
 const upstream:typeof fetch=async url=>{
  const address=String(url);
  if(address.includes('oauth2'))return Response.json({access_token:'access'});
  if(address.includes('/attachments/'))return Response.json({data:bytes.toString('base64url')});
  if(address.includes('format=full'))return Response.json({payload:{headers:address.includes('/spoof')?headers.filter(h=>h.name!=='Authentication-Results'):headers,parts:[{filename:'statement.pdf',mimeType:'application/pdf',body:{attachmentId:'attachment',size:bytes.length}}]}});
  pages++;return Response.json(address.includes('pageToken=next')?{messages:[{id:'valid'}]}:{messages:Array.from({length:10},(_,i)=>({id:'spoof'+i})),nextPageToken:'next'});
 };
 assert.equal((await syncNPS(env,'owner',upstream,at)).imported,0);
 assert.equal((await syncNPS(env,'owner',upstream,new Date(at.getTime()+1000))).imported,1);
 assert.equal(pages,2);assert.equal(db.prepare('SELECT total FROM nps_snapshots').get()?.total,'2000');
});
