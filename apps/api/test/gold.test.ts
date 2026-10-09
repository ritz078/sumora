import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseGoldPrice, refreshGoldPrice } from '../src/gold-prices';
import { parseGullakStatement } from '../src/gullak-statement';

const at = new Date('2026-10-09T16:00:00Z');
const feed = (date = '2026-10-09', value: unknown = 14956) => ({schema_version:'1.0', dataset:'gold',scope:'in',resolution:'daily',generated_at:date+'T00:30:00Z',unit:{quantity:'gram',currency:'INR'},sources:[{id:'ibja'}],observations:[{date,instrument_id:'XAU.24K.INR.G',value,status:'provisional',source:'ibja'}]});
import {setupGold} from './helpers/database';
test('gold feed accepts only a dated INR/gram 24K observation and preserves its provisional label',()=>{
 const quote=parseGoldPrice(feed(),at);
 assert.equal(quote.price,'14956'); assert.equal(quote.date,'2026-10-09'); assert.equal(quote.kind,'gold'); assert.match(quote.source,/provisional/);
 for(const bad of [feed('2026-10-10'),feed('2026-02-30'),feed('2026-10-09',0),feed('2026-10-09','NaN'),{...feed(),unit:{quantity:'ounce',currency:'USD'}},{...feed(),observations:[...feed().observations,...feed().observations]}]) assert.throws(()=>parseGoldPrice(bad,at));
});
test('gold refresh saves dated history, preserves daily baseline through revisions and survives failed or older feeds',async()=>{
 const {db,env}=setupGold();
 await refreshGoldPrice(env,async()=>Response.json(feed('2026-10-08',14764.6)),new Date('2026-10-08T16:00:00Z'));
 await refreshGoldPrice(env,async()=>Response.json(feed()),at);
 assert.equal(db.prepare("SELECT price FROM market_prices WHERE kind='gold'").get()?.price,'14956');
 assert.equal(db.prepare("SELECT price FROM daily_price_baselines WHERE day='2026-10-09' AND kind='gold'").get()?.price,'14764.6');
 await refreshGoldPrice(env,async()=>Response.json(feed('2026-10-09',14960)),at);
 assert.equal(db.prepare("SELECT price FROM daily_price_baselines WHERE day='2026-10-09' AND kind='gold'").get()?.price,'14764.6');
 await refreshGoldPrice(env,async()=>Response.json(feed('2026-10-07',1)),at);
 await refreshGoldPrice(env,async()=>new Response('no',{status:503}),at);
 assert.equal(db.prepare("SELECT price FROM market_prices WHERE kind='gold'").get()?.price,'14960');
 assert.equal(db.prepare('SELECT count(*) AS n FROM gold_price_history').get()?.n,2);
});
const statement=`Monthly Statement for Example Person
Period : September 1, 2026 - September 30, 2026
Total holdings on October 6, 2026
56.3252 gm 0 gm
Transaction Type Amount Quantity
Total Buy - Gold ₹20000 1.2478 gm
Total Sell - Gold ₹0 0 gm
Total Buy - Silver ₹0 0 gm
Total Sell - Silver ₹0 0 gm
Total Lease - Gold - 1.89 gm
Gold+ Interest - 0.1773 gm
Rewards - (Gold+Silver) ₹0 -
Opening balance on September 1, 2026: Gold: 54.9001 gmSilver: 0 gm
Augmont Goldtech Private Limited`;
test('Gullak monthly checkpoint reconciles exact decimals without adding leased grams',()=>{
 const parsed=parseGullakStatement(statement,at);
 assert.equal(parsed.grams,'56.3252');assert.equal(parsed.openingGrams,'54.9001');assert.equal(parsed.balanceDate,'2026-10-06');assert.equal(parsed.periodEnd,'2026-09-30');
 assert.throws(()=>parseGullakStatement(statement.replace('56.3252','58.2152'),at),/reconcil/i);
 assert.throws(()=>parseGullakStatement(statement.replace('₹0 -','₹10 -'),at),/reward/i);
 assert.throws(()=>parseGullakStatement(statement.replace('October 6, 2026','October 10, 2026'),at));
 assert.throws(()=>parseGullakStatement(statement+statement,at));
});

import { valuedSnapshot, refreshDailyPrices } from '../src/daily-valuation-job';
import { zerodhaSnapshot } from '../src/zerodha-portfolio';
test('gold composes once into cached portfolio, allocations and daily movement with unknown cost',async()=>{
 const {db,env}=setupGold();
 const snapshot=zerodhaSnapshot('{"status":"success","data":[]}','{"status":"success","data":[]}',at);
 db.prepare('INSERT INTO gullak_checkpoints(owner_id,grams,opening_grams,period_start,period_end,balance_date,message_id,content_hash,imported_at) VALUES(?,?,?,?,?,?,?,?,?)').run('owner','56.3252','54.9001','2026-09-01','2026-09-30','2026-10-06','message','hash',at.getTime());
 await refreshGoldPrice(env,async()=>Response.json(feed('2026-10-08',14764.6)),new Date('2026-10-08T16:00:00Z'));
 await refreshGoldPrice(env,async()=>Response.json(feed()),at);
 const result=await valuedSnapshot(env,snapshot,at,'owner');
 assert.equal(result.holdings.length,1);assert.equal(result.holdings[0].quantity,'56.3252');
 assert.equal(result.value,'842399.6912');assert.equal(result.gain,null);assert.equal(result.holdings[0].gain,null);
 assert.equal(result.dailyGain,'10780.64328');assert.equal(result.allocation[0].assetClass,'gold');
 assert.match(result.holdings[0].priceBasis,/2026-10-06/);assert.match(result.holdings[0].priceBasis,/estimated/i);
 assert.equal((await valuedSnapshot(env,result,at,'owner')).holdings.length,1);
 assert.equal((await valuedSnapshot(env,snapshot,at,'other')).holdings.length,0);
 // Equity job must not delete the independently fetched gold quote.
 await refreshDailyPrices(env,async()=>{throw Error('No stock holdings');},at);
 assert.equal(db.prepare("SELECT price FROM market_prices WHERE kind='gold'").get()?.price,'14956');
});
test('missing gold price keeps the balance visible with partial coverage rather than zero value',async()=>{
 const {db,env}=setupGold();const snapshot=zerodhaSnapshot('{"status":"success","data":[]}','{"status":"success","data":[]}',at);
 db.prepare('INSERT INTO gullak_checkpoints(owner_id,grams,opening_grams,period_start,period_end,balance_date,message_id,content_hash,imported_at) VALUES(?,?,?,?,?,?,?,?,?)').run('owner','1','1','2026-09-01','2026-09-30','2026-10-06','m','h',0);
 const result=await valuedSnapshot(env,snapshot,at,'owner');
 assert.equal(result.value,null);assert.equal(result.coverage,'unavailable');assert.equal(result.holdings[0].quote,null);assert.equal(result.dailyGain,null);
});

import { gullakRoutes, saveCheckpoint, trustedGullakMessage } from '../src/gullak';
import { digest, encrypt, decrypt } from '../src/zerodha';
test('Gullak setup is authenticated, password encrypted and never returned; sync is isolated from stock contracts',async()=>{
 const {db,env:base}=setupGold();const key=Buffer.alloc(32,1).toString('base64');const token='b'.repeat(64);
 const env={...base,KITE_ENCRYPTION_KEY:key};
 db.prepare('INSERT INTO zerodha_sessions VALUES(?,?,?,?,?)').run(await digest(token),'unused','owner',at.getTime()+86400000,0);
 const calls:string[]=[];const routes=gullakRoutes(async url=>{calls.push(String(url));return Response.json({messages:[]});},()=>at.getTime());
 const req=(path:string,method='GET',body?:any,auth=true)=>routes.request(path,{method,headers:{'Content-Type':'application/json',...(auth?{Authorization:'Bearer '+token}:{})},body:body?JSON.stringify(body):undefined},env as any);
 assert.equal((await req('/status','GET',undefined,false)).status,401);
 assert.equal((await req('/password','PUT',{mobile:'123'})).status,400);
 assert.equal((await req('/password','PUT',{mobile:'9876543210'})).status,200);
 const stored=db.prepare('SELECT encrypted_password FROM gullak_settings').get()!;
 assert.equal(await decrypt(String(stored.encrypted_password),key),'87654321');
 assert.ok(!(await (await req('/status')).text()).includes('87654321'));
 assert.equal((await req('/sync','POST')).status,409);
 assert.equal((await req('/password','DELETE')).status,200);
 assert.equal(db.prepare('SELECT count(*) AS n FROM gullak_settings').get()?.n,0);
});
test('only authenticated Gullak monthly statements are trusted',()=>{
 const headers=[{name:'From',value:'Gullak <no-reply@gullak.money>'},{name:'Subject',value:'Gullak : Monthly Statement'},{name:'Authentication-Results',value:'mx.google.com; dkim=pass header.d=gullak.money; dmarc=pass header.from=gullak.money'}];
 assert.equal(trustedGullakMessage({headers}),true);
 assert.equal(trustedGullakMessage({headers:headers.slice(0,2)}),false);
 assert.equal(trustedGullakMessage({headers:headers.map(h=>h.name==='From'?{...h,value:'fake@example.com'}:h)}),false);
 assert.equal(trustedGullakMessage({headers:headers.map(h=>({...h,value:h.value.replaceAll('=pass','=fail')}))}),false);
});
test('checkpoint import deduplicates content, rejects continuity gaps and never regresses quantities',async()=>{
 const {db,env}=setupGold();const parsed=parseGullakStatement(statement,at);
 assert.equal(await saveCheckpoint(env,'owner',parsed,'m','hash',at),'imported');
 assert.equal(await saveCheckpoint(env,'owner',parsed,'m2','hash',at),'duplicate');
 assert.equal(await saveCheckpoint(env,'owner',{...parsed,grams:'1',periodStart:'2026-08-01',periodEnd:'2026-08-31',balanceDate:'2026-09-01'},'older','old',at),'ignored');
 await assert.rejects(()=>saveCheckpoint(env,'owner',{...parsed,openingGrams:'60',grams:'60',periodStart:'2026-10-01',periodEnd:'2026-10-31',balanceDate:'2026-11-01'},'new','newhash',at),/continuity/i);
 assert.equal(db.prepare('SELECT grams FROM gullak_checkpoints').get()?.grams,'56.3252');
});

import { syncGullak } from '../src/gullak';
test('Gmail sync decrypts an encrypted PDF, imports once and keeps the balance after upstream failure',async()=>{
 const {db,env:base}=setupGold();const key=Buffer.alloc(32,1).toString('base64');
 const env={...base,KITE_ENCRYPTION_KEY:key,GMAIL_CLIENT_ID:'client',GMAIL_CLIENT_SECRET:'secret'} as any;
 db.prepare('INSERT INTO gullak_settings(owner_id,encrypted_password,updated_at) VALUES(?,?,?)').run('owner',await encrypt('87654321',key),0);
 db.prepare('INSERT INTO gmail_connections(owner_id,email,encrypted_refresh_token,connected_at) VALUES(?,?,?,?)').run('owner','example@example.com',await encrypt('refresh',key),0);
 const payload={headers:[{name:'From',value:'no-reply@gullak.money'},{name:'Subject',value:'Gullak : Monthly Statement'},{name:'Authentication-Results',value:'mx.google.com; dmarc=pass header.from=gullak.money'}],parts:[{filename:'September.pdf',mimeType:'application/pdf',body:{attachmentId:'attachment',size:2000}}]};
 const fetcher:typeof fetch=async url=>{
  const address=String(url);
  if(address.includes('oauth2'))return Response.json({access_token:'access'});
  if(address.includes('/attachments/'))return Response.json({data:readFileSync(new URL('./fixtures/gullak-synthetic.pdf',import.meta.url)).toString('base64url')});
  if(address.includes('format=full'))return Response.json({payload});
  assert.ok(address.includes('gullak.money'));assert.ok(!address.includes('zerodha'));
  return Response.json({messages:[{id:'forwarded'},{id:'message'}]});
 };
 assert.equal((await syncGullak(env,'owner',fetcher,at)).imported,1);
 assert.equal(db.prepare('SELECT silver_grams FROM gullak_checkpoints').get()?.silver_grams,'0');
 // Simulate a checkpoint imported before silver support, then upgrade the same PDF.
 db.prepare('UPDATE gullak_checkpoints SET silver_grams=NULL,opening_silver_grams=NULL').run();
 db.prepare('UPDATE gullak_imports SET parser_version=1').run();
 assert.equal((await syncGullak(env,'owner',fetcher,at)).imported,1);
 assert.equal(db.prepare('SELECT silver_grams FROM gullak_checkpoints').get()?.silver_grams,'0');
 assert.equal((await syncGullak(env,'owner',fetcher,at)).imported,0);
 assert.equal(db.prepare('SELECT grams FROM gullak_checkpoints').get()?.grams,'56.3252');
 await assert.rejects(()=>syncGullak(env,'owner',async()=>new Response('',{status:503}),at));
 assert.equal(db.prepare('SELECT grams FROM gullak_checkpoints').get()?.grams,'56.3252');
 assert.equal(db.prepare('SELECT lease_until FROM gullak_settings').get()?.lease_until,0);
});
test('first gold refresh seeds daily movement from an explicitly dated previous snapshot',async()=>{
 const {db,env}=setupGold();
 await refreshGoldPrice(env,async url=>Response.json(String(url).endsWith('latest.json')?feed():feed('2026-10-08',14764.6)),at);
 assert.equal(db.prepare("SELECT price FROM daily_price_baselines WHERE day='2026-10-09' AND kind='gold'").get()?.price,'14764.6');
});

test('outbound requests use Worker-supported manual redirects and reject redirect responses',async()=>{
 const {env,db}=setupGold();
 let redirect:RequestRedirect|undefined;
 const result=await refreshGoldPrice(env,async(_url,options)=>{redirect=options?.redirect;return new Response('',{status:302,headers:{Location:'https://example.com'}});},at);
 assert.equal(redirect,'manual');
 assert.equal(result.updated,0);assert.equal(db.prepare("SELECT count(*) AS n FROM market_prices WHERE kind='gold'").get()?.n,0);
});

test('a retry recovers if checkpoint saved but import bookkeeping was interrupted',async()=>{
 const {db,env}=setupGold();const parsed=parseGullakStatement(statement,at);
 await saveCheckpoint(env,'owner',parsed,'message','hash',at);
 db.prepare('DELETE FROM gullak_imports').run();
 await saveCheckpoint(env,'owner',parsed,'message','hash',at);
 assert.equal(db.prepare('SELECT grams FROM gullak_checkpoints').get()?.grams,'56.3252');
 assert.equal(db.prepare('SELECT count(*) AS n FROM gullak_imports').get()?.n,1);
});


test('silver summary reconciles bought and sold grams independently from gold',()=>{
 const silver=statement.replace('56.3252 gm 0 gm','56.3252 gm 12.25 gm').replace('Total Buy - Silver ₹0 0 gm','Total Buy - Silver ₹500 3.5 gm').replace('Total Sell - Silver ₹0 0 gm','Total Sell - Silver ₹100 1.25 gm').replace('Silver: 0 gm','Silver: 10 gm');
 const result=parseGullakStatement(silver,at);
 assert.equal(result.silverGrams,'12.25');assert.equal(result.openingSilverGrams,'10');
 assert.throws(()=>parseGullakStatement(silver.replace('12.25 gm','13 gm'),at),/silver.*reconcil/i);
 assert.throws(()=>parseGullakStatement(silver.replace('Total Buy - Silver ₹500 3.5 gm',''),at),/silver/i);
 assert.throws(()=>parseGullakStatement(silver.replace('Silver: 10 gm','Silver: -1 gm'),at),/silver/i);
 assert.equal(parseGullakStatement(statement,at).silverGrams,'0');
});


test('checkpoints retain silver and reject a later silver continuity gap',async()=>{
 const {env,db}=setupGold();const parsed={...parseGullakStatement(statement,at),silverGrams:'12.25',openingSilverGrams:'10'};
 await saveCheckpoint(env,'owner',parsed,'message','hash',at);
 assert.equal(db.prepare('SELECT * FROM gullak_checkpoints').get()?.silver_grams,'12.25');
 const token='c'.repeat(64);db.prepare('INSERT INTO zerodha_sessions VALUES(?,?,?,?,?)').run(await digest(token),'unused','owner',at.getTime()+86400000,0);
 const response=await gullakRoutes(fetch,()=>at.getTime()).request('/status',{headers:{Authorization:'Bearer '+token}},env as any);
 assert.equal((await response.json()).balance.silver_grams,'12.25');
 await assert.rejects(()=>saveCheckpoint(env,'owner',{...parsed,periodStart:'2026-10-01',periodEnd:'2026-10-31',balanceDate:'2026-11-01',openingGrams:parsed.grams,openingSilverGrams:'13'},'next','next',at),/continuity/i);
 assert.equal(db.prepare('SELECT * FROM gullak_checkpoints').get()?.silver_grams,'12.25');
});
