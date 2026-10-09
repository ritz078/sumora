import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {parseBondStatement} from '../src/bond-statement';
const raw=readFileSync(new URL('./fixtures/bonds-cas.txt',import.meta.url),'utf8');
const at=new Date('2026-10-10T00:00:00Z');
test('CAS bonds use closing units once, ignoring transaction rows and reconciling debt and account totals',()=>{
 const p=parseBondStatement(raw,at);
 assert.equal(p.statementDate,'2026-08-31');assert.equal(p.total,'448845');assert.equal(p.bonds.length,9);
 assert.deepEqual(p.bonds[0],{isin:'INE109C07139',name:'ARMAN FINANCIAL SERVICES LTD',quantity:'5',price:'10100',value:'50500',coupon:'11.35',maturesOn:'2028-07-29'});
 assert.equal(p.bonds[4].coupon,'0');assert.equal(p.bonds[5].quantity,'50');assert.equal(p.bonds[8].maturesOn,'2026-10-04');
 assert.equal(p.bonds[1].maturesOn,null); // Abbreviated security names are not inferred.
 assert.equal(parseBondStatement(raw.replace('INE0MYJ07112','INE0MY J07112'),at).bonds[8].isin,'INE0MYJ07112');
});
test('CAS rejects incomplete, duplicate, unsupported or inconsistent balances rather than silently dropping holdings',()=>{
 for(const bad of [raw.replace('50,500.00','50,501.00'),raw.replace('9 4,48,845.00','8 4,48,845.00'),raw.replace('Debts 4,48,845.00','Debts 4,48,846.00'),raw.replaceAll('31-08-2026','31-12-2026'),raw.replaceAll('INE0LN107089','INE109C07139'),raw.replace('CREDIT WISE\nCAPITAL PRIVATE\nLIMITED 11.15 NCD','CREDIT WISE\nCAPITAL PRIVATE\nLIMITED EQUITY'),raw.replace('5\n-- --\n-- --\n-- --\n-- --\n-- 5 10100','5\n-- --\n-- --\n-- --\n-- --\n-- 4 10100')])assert.throws(()=>parseBondStatement(bad,at));
});

import {saveBondSnapshot,bondsPortfolio,bondsRoutes,syncBonds,trustedBondMessage} from '../src/bonds';
import {setupGold} from './helpers/database';
import {zerodhaSnapshot} from '../src/zerodha-portfolio';
import {digest,encrypt,decrypt} from '../src/zerodha';
const key=Buffer.alloc(32,1).toString('base64');
const headers=[{name:'From',value:'CDSL <eCAS@cdslstatement.com>'},{name:'Subject',value:'CDSL Consolidated Account Statement (CAS) across Mutual Funds and Depositories for-AUG2026-12345-1-1'},{name:'Authentication-Results',value:'mx.google.com; dmarc=pass header.from=cdslstatement.com'}];
test('bond snapshots isolate owners, replace holdings, deduplicate and preserve last data on conflicts or cancelled imports',async()=>{
 const {env,db}=setupGold(),p=parseBondStatement(raw,at);
 assert.equal(await saveBondSnapshot(env,'owner',p,'m','h',at),'imported');
 assert.equal(await saveBondSnapshot(env,'owner',p,'m','h',at),'duplicate');
 assert.equal(await saveBondSnapshot(env,'owner',{...p,statementDate:'2026-07-31'},'old','old',at),'ignored');
 await assert.rejects(()=>saveBondSnapshot(env,'owner',p,'conflict','conflict',at));
 await assert.rejects(()=>saveBondSnapshot(env,'owner',{...p,statementDate:'2026-09-30'},'cancel','cancel',at,123));
 const base=zerodhaSnapshot('{"status":"success","data":[]}','{"status":"success","data":[]}',at);
 const portfolio=await bondsPortfolio(env,base,'owner',at);
 assert.equal(portfolio.value,'448845');assert.equal(portfolio.allocation[0].assetClass,'bond');assert.equal(portfolio.holdings.length,9);
 assert.equal(portfolio.holdings[8].bondTerms?.redemptionCheck,true);assert.equal(portfolio.holdings[8].gain,null);assert.equal(portfolio.holdings[0].bondTerms?.redemptionCheck,false);
 assert.equal((await bondsPortfolio(env,portfolio,'owner',at)).holdings.length,9);assert.equal((await bondsPortfolio(env,base,'other',at)).value,'0');
 assert.ok(!JSON.stringify(db.prepare('SELECT * FROM bonds_snapshots').all()).includes('IN30000012345678'));
 await saveBondSnapshot(env,'owner',{...p,statementDate:'2026-09-30',bonds:p.bonds.slice(0,1),total:'50500'},'new','new',at);
 assert.equal((await bondsPortfolio(env,base,'owner',at)).holdings.length,1);
});
test('bond import settings authenticate PAN storage and retain balances when disabled',async()=>{
 const {env:base,db}=setupGold(),token='e'.repeat(64),env={...base,KITE_ENCRYPTION_KEY:key} as any;
 db.prepare('INSERT INTO zerodha_sessions VALUES(?,?,?,?,?)').run(await digest(token),'unused','owner',at.getTime()+86400000,0);
 const app=bondsRoutes(fetch,()=>at.getTime());
 const req=(path:string,method='GET',body?:unknown,auth=true)=>app.request(path,{method,headers:{'Content-Type':'application/json',...(auth?{Authorization:'Bearer '+token}:{})},body:body?JSON.stringify(body):undefined},env);
 assert.equal((await req('/password','PUT',{password:'ABCDE1234F'},false)).status,401);
 assert.equal((await req('/password','PUT',{password:'wrong'})).status,400);
 assert.equal((await req('/password','PUT',{password:'abcde1234f'})).status,200);
 assert.equal(await decrypt(String(db.prepare('SELECT encrypted_password FROM bonds_settings').get()?.encrypted_password),key),'ABCDE1234F');
 assert.ok(!(await (await req('/status')).text()).includes('ABCDE1234F'));
 await saveBondSnapshot(env,'owner',parseBondStatement(raw,at),'m','h',at);
 assert.equal((await req('/connection','DELETE')).status,200);
 assert.equal(db.prepare('SELECT count(*) AS n FROM bonds_snapshots').get()?.n,1);
});
test('bond mail requires authenticated CDSL sender and CAS subject',()=>{
 assert.equal(trustedBondMessage({headers}),true);
 for(const bad of [headers.filter(h=>h.name!=='Authentication-Results'),headers.map(h=>({...h,value:h.value.replace('dmarc=pass','dmarc=fail')})),headers.map(h=>h.name==='From'?{...h,value:'eCAS@cdslstatement.com.evil.example'}:h),headers.map(h=>h.name==='Subject'?{...h,value:'Forwarded CAS'}:h)])assert.equal(trustedBondMessage({headers:bad}),false);
});
test('Gmail imports encrypted bin-type CAS PDFs, deduplicates and retains last good data on a wrong password',async()=>{
 const {env:base,db}=setupGold(),env={...base,KITE_ENCRYPTION_KEY:key,GMAIL_CLIENT_ID:'client',GMAIL_CLIENT_SECRET:'secret'} as any;
 db.prepare('INSERT INTO bonds_settings(owner_id,encrypted_password,updated_at) VALUES(?,?,?)').run('owner',await encrypt('ABCDE1234F',key),0);
 db.prepare('INSERT INTO gmail_connections(owner_id,email,encrypted_refresh_token,connected_at) VALUES(?,?,?,?)').run('owner','example@example.com',await encrypt('refresh',key),0);
 const bytes=readFileSync(new URL('./fixtures/bonds-synthetic.pdf',import.meta.url));
 const upstream:typeof fetch=async url=>{
  const address=String(url);
  if(address.includes('oauth2'))return Response.json({access_token:'access'});
  if(address.includes('/attachments/'))return Response.json({data:bytes.toString('base64url')});
  if(address.includes('format=full'))return Response.json({payload:{headers,parts:[{filename:'cas.pdf',mimeType:'bin',body:{attachmentId:'attachment',size:bytes.length}}]}});
  assert.match(decodeURIComponent(address),/eCAS@cdslstatement.com/i);return Response.json({messages:[{id:'message'}]});
 };
 assert.equal((await syncBonds(env,'owner',upstream,at)).imported,1);
 assert.equal((await syncBonds(env,'owner',upstream,at)).imported,0);
 db.prepare('DELETE FROM bonds_imports').run();db.prepare('UPDATE bonds_settings SET encrypted_password=?').run(await encrypt('WRONG1234F',key));
 await assert.rejects(()=>syncBonds(env,'owner',upstream,at));
 assert.equal(db.prepare('SELECT total FROM bonds_snapshots').get()?.total,'448845');assert.equal(db.prepare('SELECT status FROM bonds_imports').get()?.status,'needs_review');
 assert.equal(db.prepare('SELECT lease_until FROM bonds_settings').get()?.lease_until,0);
});

test('an explicit zero debt account with Nil Holding clears redeemed bonds without guessing from maturity',()=>{
 const empty=`CONSOLIDATED ACCOUNT STATEMENT (CAS)
 NSDL Demat Account EXAMPLE BROKER DP Id: IN300000 Client Id :12345678 0 0.00
 Asset Class Value Percentage Debts 0.00 0.00
 DEMAT ACCOUNTS HELD WITH NSDL DPID : IN30000012345678
 STATEMENT OF TRANSACTIONS FOR THE PERIOD FROM 01-09-2026 TO 30-09-2026
 Nil Holding`;
 assert.deepEqual(parseBondStatement(empty,at),{accountID:'IN30000012345678',statementDate:'2026-09-30',total:'0',bonds:[]});
 assert.throws(()=>parseBondStatement(empty.replace('Debts 0.00','Debts 50000.00'),at));
 assert.throws(()=>parseBondStatement(empty.replace('Nil Holding',''),at));
});
test('a settings cancellation at the snapshot write cannot mark a CAS imported',async()=>{
 const {env,db}=setupGold();db.prepare("INSERT INTO bonds_settings(owner_id,encrypted_password,updated_at,lease_until) VALUES('owner','unused',0,123)").run();
 const guarded={DB:{prepare(sql:string){
  const statement=env.DB.prepare(sql),first=statement.first.bind(statement);
  statement.first=async function<T>() {if(sql.startsWith('INSERT INTO bonds_snapshots'))db.prepare('DELETE FROM bonds_settings').run();return first<T>();};return statement;
 }}};
 await assert.rejects(()=>saveBondSnapshot(guarded,'owner',parseBondStatement(raw,at),'m','h',at,123));
 assert.equal(db.prepare('SELECT count(*) AS n FROM bonds_snapshots').get()?.n,0);
 assert.equal(db.prepare('SELECT count(*) AS n FROM bonds_imports').get()?.n,0);
});

test('an import ledger failure rolls back the new snapshot and keeps the previous balances',async()=>{
 const {env,db}=setupGold(),p=parseBondStatement(raw,at);
 await saveBondSnapshot(env,'owner',p,'old','old',at);
 db.exec("CREATE TRIGGER fail_ledger BEFORE INSERT ON bonds_imports BEGIN SELECT RAISE(ABORT,'ledger unavailable'); END;");
 await assert.rejects(()=>saveBondSnapshot(env,'owner',{...p,statementDate:'2026-09-30',total:'50500',bonds:p.bonds.slice(0,1)},'new','new',at));
 assert.equal(db.prepare('SELECT statement_date FROM bonds_snapshots').get()?.statement_date,'2026-08-31');
 assert.equal(db.prepare('SELECT total FROM bonds_snapshots').get()?.total,'448845');
});
