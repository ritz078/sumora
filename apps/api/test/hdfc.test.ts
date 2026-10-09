import {test} from 'node:test';
import assert from 'node:assert/strict';
import {parseHDFCStatement} from '../src/hdfc-statement';
export const statement=`Example Person
Statement as on Customer Email Customer ID Account Relationship Summary
: 30/09/2026 : example@example.com : 12345678
INR SAVINGS ACCOUNTS 9000.00 CR 0.00 3000.00 0.00 12000.00
INR TERM DEPOSITS 3000.00 CR
FD DETAILS :- FOR CURRENT FINANCIAL YEAR
Statement as on : 30/09/2026
FD Number FD CCY Original Principal Current FD Amount # Open/Last Renew Date Maturity Date ** Rate Of Interest Lien Amount Maturity Amount (Revised) Available Withdrawable*** Nomination Registered
12345678901234 INR 1000.00 01/09/2025 6.25 0.00 1200.00 YES
1100.00 02/09/2027 1000.00
Page 1 of 2
Example Person Customer ID
FD DETAILS :- FOR CURRENT FINANCIAL YEAR
Statement as on : 30/09/2026
FD Number FD CCY Original Principal Current FD Amount # Open/Last Renew Date Maturity Date ** Rate Of Interest Lien Amount Maturity Amount (Revised) Available Withdrawable*** Nomination Registered
12345678905678 INR 2500.00 01/09/2025 6.25 0.00 2300.00 NO
2100.00 02/09/2027 2000.00
# Current Principal is net of Withdrawals
Details of TD Interest in current Financial Year
12345678901234 INR 100.00 20.00 0.00
Your Combined statement generation frequency is monthly
*** End of Statement ***`;
const at=new Date('2026-10-09T16:00:00Z');
test('HDFC parses multi-page FD records and reconciles withdrawable value without counting savings or interest rows',()=>{
 const result=parseHDFCStatement(statement,at);
 assert.equal(result.date,'2026-09-30');assert.equal(result.total,'3000');assert.equal(result.deposits.length,2);
 assert.deepEqual(result.deposits[0],{number:'12345678901234',originalPrincipal:'1000',currentAmount:'1100',withdrawable:'1000',maturityAmount:'1200',rate:'6.25',openedOn:'2025-09-01',maturesOn:'2027-09-02',lien:'0',nomination:true});
 for(const bad of [statement.replace('3000.00 CR','3100.00 CR'),statement.replace('12345678905678 INR','12345678901234 INR'),statement.replace('30/09/2026','30/10/2026'),statement.replace('2000.00\n#','200.00\n#'),statement.replace('12345678905678 INR','12345678905678 USD')]) assert.throws(()=>parseHDFCStatement(bad,at));
});

import {setupGold} from './helpers/database';
import {saveHDFCSnapshot,hdfcRoutes,syncHDFC,trustedHDFCMessage} from '../src/hdfc';
import {digest,encrypt,decrypt} from '../src/zerodha';
import {valuedSnapshot} from '../src/daily-valuation-job';
import {zerodhaSnapshot} from '../src/zerodha-portfolio';
test('HDFC snapshots are account-isolated, idempotent, replace closed FDs and retain latest on older/conflicting import',async()=>{
 const {db,env}=setupGold();const parsed=parseHDFCStatement(statement,at);
 assert.equal(await saveHDFCSnapshot(env,'owner',parsed,'m','h',at),'imported');
 assert.equal(await saveHDFCSnapshot(env,'owner',parsed,'m2','h',at),'duplicate');
 assert.equal(await saveHDFCSnapshot(env,'owner',{...parsed,date:'2026-08-31'},'m3','old',at),'ignored');
 await assert.rejects(()=>saveHDFCSnapshot(env,'owner',parsed,'m4','conflict',at));
 const snapshot=zerodhaSnapshot('{"status":"success","data":[]}','{"status":"success","data":[]}',at);
 const result=await valuedSnapshot(env,snapshot,at,'owner');
 assert.equal(result.value,'3500');assert.equal(result.holdings.length,2);assert.equal(result.allocation[0].assetClass,'fixedDeposit');
 assert.equal(result.holdings[0].gain,null);assert.equal(result.holdings[0].value,'1200');assert.equal(result.holdings[0].quote,'1200');assert.match(result.holdings[0].priceBasis,/maturity/i);
 assert.ok(!JSON.stringify(result).includes('12345678901234'));
 assert.equal((await valuedSnapshot(env,snapshot,at,'other')).holdings.length,0);
 await saveHDFCSnapshot(env,'owner',{date:'2026-10-31',total:'0',deposits:[]},'closed','closed',at);
 assert.equal((await valuedSnapshot(env,result,at,'owner')).holdings.length,0);
 assert.equal(db.prepare('SELECT total FROM hdfc_snapshots').get()?.total,'0');
});

import {readFileSync} from 'node:fs';
const headers=[{name:'From',value:'HDFC Bank Smart Statement <hdfcbanksmartstatement@hdfcbank.bank.in>'},{name:'Subject',value:'HDFC Bank Combined Email Statement for September-2026'},{name:'Authentication-Results',value:'mx.google.com; dmarc=pass header.from=hdfcbank.bank.in'}];
test('HDFC requires a verified monthly sender and excludes credit card statements',()=>{
 assert.equal(trustedHDFCMessage({headers}),true);
 for(const invalid of [headers.slice(0,2),headers.map(h=>({...h,value:h.value.replace('dmarc=pass','dmarc=fail')})),headers.map(h=>h.name==='From'?{...h,value:'fake@example.com'}:h),headers.map(h=>h.name==='Subject'?{...h,value:'HDFC Credit Card Statement'}:h)])assert.equal(trustedHDFCMessage({headers:invalid}),false);
});
test('HDFC setup is authenticated, password encrypted and never returned; removal retains FDs',async()=>{
 const {db,env:base}=setupGold();const key=Buffer.alloc(32,1).toString('base64'),token='e'.repeat(64);
 const env={...base,KITE_ENCRYPTION_KEY:key} as any;
 db.prepare('INSERT INTO zerodha_sessions VALUES(?,?,?,?,?)').run(await digest(token),'unused','owner',at.getTime()+86400000,0);
 const routes=hdfcRoutes(fetch,()=>at.getTime());
 const req=(path:string,method='GET',body?:unknown,auth=true)=>routes.request(path,{method,headers:{'Content-Type':'application/json',...(auth?{Authorization:'Bearer '+token}:{})},body:body?JSON.stringify(body):undefined},env);
 assert.equal((await req('/status','GET',undefined,false)).status,401);
 assert.equal((await req('/password','PUT',{password:'bad'})).status,400);
 assert.equal((await req('/password','PUT',{password:'12345678'})).status,200);
 const stored=db.prepare('SELECT encrypted_password FROM hdfc_settings').get()!;
 assert.notEqual(stored.encrypted_password,'12345678');assert.equal(await decrypt(String(stored.encrypted_password),key),'12345678');
 assert.ok(!(await (await req('/status')).text()).includes('12345678'));
 assert.equal((await req('/sync','POST')).status,409);
 await saveHDFCSnapshot(env,'owner',parseHDFCStatement(statement,at),'m','h',at);
 const status=await (await req('/status')).json();
 assert.equal(status.balance.count,2);assert.equal(status.balance.total,'3500');assert.equal(status.balance.valuationBasis,'maturity');
 await req('/password','DELETE');assert.equal(db.prepare('SELECT count(*) AS n FROM hdfc_settings').get()?.n,0);
 assert.equal(db.prepare('SELECT total FROM hdfc_snapshots').get()?.total,'3000');
});
test('HDFC Gmail sync decrypts octet-stream PDFs, deduplicates and retains FDs after password and upstream failures',async()=>{
 const {db,env:base}=setupGold();const key=Buffer.alloc(32,1).toString('base64');
 const env={...base,KITE_ENCRYPTION_KEY:key,GMAIL_CLIENT_ID:'client',GMAIL_CLIENT_SECRET:'secret'} as any;
 db.prepare('INSERT INTO hdfc_settings(owner_id,encrypted_password,updated_at) VALUES(?,?,?)').run('owner',await encrypt('12345678',key),0);
 db.prepare('INSERT INTO gmail_connections(owner_id,email,encrypted_refresh_token,connected_at) VALUES(?,?,?,?)').run('owner','example@example.com',await encrypt('refresh',key),0);
 const bytes=readFileSync(new URL('./fixtures/hdfc-synthetic.pdf',import.meta.url));
 const fetcher:typeof fetch=async url=>{
  const address=String(url);
  if(address.includes('oauth2'))return Response.json({access_token:'access'});
  if(address.includes('/attachments/'))return Response.json({data:bytes.toString('base64url')});
  if(address.includes('format=full'))return Response.json({payload:{headers,parts:[{filename:'statement.pdf',mimeType:'application/octet-stream',body:{attachmentId:'attachment',size:bytes.length}}]}});
  assert.match(decodeURIComponent(address),/hdfcbanksmartstatement@hdfcbank.bank.in/);
  return Response.json({messages:[{id:'message'}]});
 };
 assert.equal((await syncHDFC(env,'owner',fetcher,at)).imported,1);
 assert.equal((await syncHDFC(env,'owner',fetcher,at)).imported,0);
 assert.equal(db.prepare('SELECT total FROM hdfc_snapshots').get()?.total,'3000');
 db.prepare('DELETE FROM hdfc_imports').run();
 db.prepare('UPDATE hdfc_settings SET encrypted_password=?').run(await encrypt('wrong-password',key));
 await assert.rejects(()=>syncHDFC(env,'owner',fetcher,at));
 assert.equal(db.prepare('SELECT status FROM hdfc_imports').get()?.status,'needs_review');
 assert.equal(db.prepare('SELECT total FROM hdfc_snapshots').get()?.total,'3000');
 await assert.rejects(()=>syncHDFC(env,'owner',async()=>new Response('',{status:401}),at));
 assert.equal(db.prepare('SELECT status FROM gmail_connections').get()?.status,'reconnect');
 assert.equal(db.prepare('SELECT lease_until FROM hdfc_settings').get()?.lease_until,0);
});
test('HDFC explicit zero FD summary clears closed deposits and interrupted bookkeeping recovers',async()=>{
 const empty=statement.replace('3000.00 CR','0.00 CR').replace(/FD DETAILS :- FOR CURRENT FINANCIAL YEAR[\s\S]*# Current Principal is net of Withdrawals/,'').replace('12345678901234 INR 100.00 20.00 0.00','');
 assert.equal(parseHDFCStatement(empty,at).deposits.length,0);
 const {env,db}=setupGold();const parsed=parseHDFCStatement(statement,at);
 await saveHDFCSnapshot(env,'owner',parsed,'m','h',at);
 db.prepare('DELETE FROM hdfc_imports').run();
 await saveHDFCSnapshot(env,'owner',parsed,'m','h',at);
 assert.equal(db.prepare('SELECT status FROM hdfc_imports').get()?.status,'imported');
});

import {scheduledStatements} from '../src/statement-jobs';
test('scheduled statements rotate between configured sources and skip revoked Gmail connections',async()=>{
 const {db,env:base}=setupGold();const key=Buffer.alloc(32,1).toString('base64');
 const env={...base,KITE_ENCRYPTION_KEY:key,GMAIL_CLIENT_ID:'client',GMAIL_CLIENT_SECRET:'secret'} as any;
 for(const table of ['hdfc_settings','gullak_settings','nps_settings'])db.prepare(`INSERT INTO ${table}(owner_id,encrypted_password,updated_at) VALUES(?,?,?)`).run('owner',await encrypt('12345678',key),0);
 db.prepare('INSERT INTO gmail_connections(owner_id,email,encrypted_refresh_token,connected_at) VALUES(?,?,?,?)').run('owner','example@example.com',await encrypt('refresh',key),0);
 const sources:string[]=[];
 const fetcher:typeof fetch=async url=>{
  if(String(url).includes('oauth2'))return Response.json({access_token:'access'});
  sources.push(String(url).includes('KCRA')?'nps':String(url).includes('gullak')?'gullak':'hdfc');return Response.json({messages:[]});
 };
 await scheduledStatements(env,fetcher,at);
 await scheduledStatements(env,fetcher,new Date(at.getTime()+1000));
 await scheduledStatements(env,fetcher,new Date(at.getTime()+2000));
 assert.deepEqual(new Set(sources),new Set(['gullak','hdfc','nps']));
 db.prepare("UPDATE gmail_connections SET status='reconnect'").run();
 await scheduledStatements(env,fetcher,new Date(at.getTime()+2000));assert.equal(sources.length,3);
});
