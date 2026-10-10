import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {parseWintEmail,trustedWintMessage} from '../src/wint-email';
const at=new Date('2026-10-10T00:00:00Z');
const purchase=readFileSync(new URL('./fixtures/wint-purchase.txt',import.meta.url),'utf8');
const paid='The Monthly Interest for your investment has been credited. Total amount credited: ₹333 Interest amount (Pre-TDS) ₹370 TDS deducted ₹37 ISIN INE101Q07BK8 Date of payout 01-Oct-2026 Next payout date 01-Nov-2026 Total Payout: Including this payout, you have received a total of ₹2983';
const redeemed='Your investment has matured. Total amount credited: ₹50623.85 Principal repaid ₹50000 Interest amount (Pre-TDS) ₹693.14 TDS deducted ₹69.3 ISIN INE0MYJ07112 Interest amount credited ₹623.84 Date of payout 01-Oct-2026';
test('settled Wint purchases reconcile cash paid, accrued interest and units and do not confuse an order receipt with settlement',()=>{
 const p=parseWintEmail('Investment Successful for Example Finance',purchase,at);
 assert.equal(p.kind,'purchase');if(p.kind!=='purchase')throw Error();
 assert.equal(p.confirmed,true);assert.equal(p.date,'2026-08-03');assert.equal(p.invested,'49964.61');assert.equal(p.cleanCost,'49874.2');assert.equal(p.accrued,'90.41');assert.equal(p.frequency,'Monthly');
 const receipt=parseWintEmail('Your order receipt for Example Finance is here',purchase.replace('SETTLEMENT DATE AND TIME 03-Aug-2026 6:55 PM ',''),at);
 assert.equal(receipt.kind==='purchase' && receipt.confirmed,false);
 for(const bad of [purchase.replace('₹49964.61','₹59964.61'),purchase.replace('NUMBER OF UNITS 5','NUMBER OF UNITS 6'),purchase.replace('03-Aug-2026','03-Aug-2027'),purchase.replace('credited to your Wint Wealth Demat Account','not settled')])assert.throws(()=>parseWintEmail('Investment Successful for Example Finance',bad,at));
});
test('payouts separate gross interest, TDS, principal and net cash without treating cumulative totals as new income',()=>{
 const p=parseWintEmail('💸 Just Credited: Monthly Interest for Muthoot MCred',paid,at);
 assert.equal(p.kind,'interest');assert.equal(p.gross,'370');assert.equal(p.tds,'37');assert.equal(p.net,'333');assert.equal(p.nextPayout,'2026-11-01');assert.equal(p.principal,'0');
 const r=parseWintEmail('💸 Asset Matured: Principal and Interest credited for Progfin',redeemed,at);
 assert.equal(r.kind,'redemption');assert.equal(r.principal,'50000');assert.equal(r.net,'623.84');
 assert.throws(()=>parseWintEmail('💸 Just Credited: Monthly Interest for Muthoot MCred',paid.replace('₹333','₹343'),at));
});
test('Wint requires exact transaction or receipt senders and authenticated Gmail DMARC',()=>{
 const headers=[{name:'From',value:'Team Wint Wealth <transactions@wintwealth.com>'},{name:'Subject',value:'Investment Successful for Example Finance'},{name:'Authentication-Results',value:'mx.google.com; dmarc=pass header.from=wintwealth.com'}];
 assert.equal(trustedWintMessage({headers}),true);
 assert.equal(trustedWintMessage({headers:headers.filter(h=>h.name!=='Authentication-Results')}),false);
 assert.equal(trustedWintMessage({headers:headers.map(h=>({...h,value:h.value.replace('transactions@wintwealth.com','transactions@wintwealth.com.evil.example')}))}),false);
});

import {saveWintEvent,readWintEvents} from '../src/wint-events';
import {reconcileBonds} from '../src/bond-reconciliation';
import {setupGold} from './helpers/database';
import {digest} from '../src/zerodha';
import {parseBondStatement} from '../src/bond-statement';
const cas=parseBondStatement(readFileSync(new URL('./fixtures/bonds-cas.txt',import.meta.url),'utf8'),at);
test('settled orders upgrade receipts once, isolate owners and never persist the full account identifier',async()=>{
 const {env,db}=setupGold();const confirmed=parseWintEmail('Investment Successful for Example Finance',purchase,at);
 const receipt=parseWintEmail('Your order receipt for Example Finance is here',purchase,at);
 assert.equal(await saveWintEvent(env,'owner',receipt,'r',at),'imported');
 assert.equal(await saveWintEvent(env,'owner',confirmed,'c',at),'imported');
 assert.equal(await saveWintEvent(env,'owner',confirmed,'duplicate',at),'duplicate');
 assert.equal((await readWintEvents(env,'owner')).length,1);assert.equal((await readWintEvents(env,'other')).length,0);
 assert.ok(!JSON.stringify(db.prepare('SELECT * FROM wint_events').all()).includes('IN30000012345678'));
 await assert.rejects(()=>saveWintEvent(env,'owner',{...confirmed,invested:'60000'} as any,'conflict',at));
 const saved=(await readWintEvents(env,'owner'))[0].event;assert.equal(saved.kind==='purchase' && saved.invested,'49964.61');
});
test('CAS defines current holdings while purchases enrich matching lots and never add later purchases',async()=>{
 const {env}=setupGold();let p=parseWintEmail('Investment Successful for Example Finance',purchase,at);if(p.kind!=='purchase')throw Error();
 await saveWintEvent(env,'owner',p,'p',at);
 await saveWintEvent(env,'owner',parseWintEmail('💸 Just Credited: Monthly Interest for Example Finance',paid.replace('INE101Q07BK8','INE14H407116'),at),'interest',at);
 const accountHash=await digest('owner:bonds:'+cas.accountID);
 let result=reconcileBonds(cas,accountHash,await readWintEvents(env,'owner'),at);
 let b=result.holdings.find(h=>h.symbol==='INE14H407116')!;
 assert.equal(b.bondTerms?.investedAmount,'49964.61');assert.equal(b.bondTerms?.interestGross,'370');assert.equal(b.bondTerms?.interestNet,'333');assert.equal(b.bondTerms?.tds,'37');assert.equal(b.value,'50000');assert.equal(b.gain,null);
 await saveWintEvent(env,'owner',{...p,key:'purchase:new',isin:'INE734I07115',date:'2026-09-02',orderDate:'2026-08-28'},'new',at);
 result=reconcileBonds(cas,accountHash,await readWintEvents(env,'owner'),at);
 assert.equal(result.holdings.length,9);assert.ok(!result.holdings.some(h=>h.symbol==='INE734I07115'));
 assert.equal(reconcileBonds(null,null,await readWintEvents(env,'owner'),at).holdings.length,0);
});
test('receipts alone cannot add holdings; CAS quantity can corroborate a matching receipt, but missing or excessive units leave investment unknown',async()=>{
 const {env}=setupGold();const receipt=parseWintEmail('Your order receipt for Example Finance is here',purchase,at);if(receipt.kind!=='purchase')throw Error();
 await saveWintEvent(env,'owner',receipt,'r',at);
 const hash=await digest('owner:bonds:'+cas.accountID);
 let result=reconcileBonds(cas,hash,await readWintEvents(env,'owner'),at);
 assert.equal(result.holdings.find(h=>h.symbol===receipt.isin)?.bondTerms?.investedAmount,'49964.61');
 const without={...cas,bonds:cas.bonds.filter(b=>b.isin!==receipt.isin)};
 assert.ok(!reconcileBonds(without,hash,await readWintEvents(env,'owner'),at).holdings.some(h=>h.symbol===receipt.isin));
 await saveWintEvent(env,'owner',{...receipt,key:'purchase:extra'},'extra',at);
 result=reconcileBonds(cas,hash,await readWintEvents(env,'owner'),at);
 assert.equal(result.holdings.find(h=>h.symbol===receipt.isin)?.bondTerms?.investedAmount,null);
});
test('confirmed full repayment after CAS removes a holding without creating cash; partial repayment is reported without fabricating a new price',async()=>{
 const {env}=setupGold();let p=parseWintEmail('Investment Successful for Example Finance',purchase,at);if(p.kind!=='purchase')throw Error();
 p={...p,isin:'INE0MYJ07112',key:'purchase:progfin',date:'2026-02-09',orderDate:'2026-02-06',maturesOn:'2026-10-04'};
 await saveWintEvent(env,'owner',p,'p',at);const red=parseWintEmail('💸 Asset Matured: Principal and Interest credited for Progfin',redeemed,at);
 await saveWintEvent(env,'owner',red,'red',at);
 const hash=await digest('owner:bonds:'+cas.accountID),result=reconcileBonds(cas,hash,await readWintEvents(env,'owner'),at);
 assert.equal(result.holdings.length,8);assert.ok(!result.holdings.some(h=>h.symbol===p.isin));assert.equal(result.redeemed.length,1);assert.equal(result.redeemed[0].principal,'50000');
 const partial={...red,kind:'principal',key:'principal:partial',principal:'10000'} as any;
 const other=reconcileBonds(cas,hash,[{accountHash:hash,event:p},{accountHash:null,event:partial}],at);
 assert.equal(other.holdings.find(h=>h.symbol===p.isin)?.value,'50000');assert.equal(other.holdings.find(h=>h.symbol===p.isin)?.bondTerms?.principalReceived,'10000');
});

test('minor reported payout differences are preserved explicitly rather than inventing net interest',()=>{
 const p=parseWintEmail('💸 Just Credited: Monthly Interest for Muthoot MCred',paid.replace('₹333','₹344').replace('₹370','₹381.8').replace('₹37 ','₹38 '),at);
 if(p.kind==='purchase')throw Error();assert.equal(p.net,'344');assert.equal(p.reconciliationDifference,'0.2');
});

import {syncBonds,bondsPortfolio,saveBondSnapshot} from '../src/bonds';
import {encrypt} from '../src/zerodha';
import {zerodhaSnapshot} from '../src/zerodha-portfolio';
test('Gmail bond sync imports bounded Wint batches with pagination, receipt dedup and real portfolio enrichment',async()=>{
 const {env:base,db}=setupGold(),key=Buffer.alloc(32,1).toString('base64');
 const env={...base,KITE_ENCRYPTION_KEY:key,GMAIL_CLIENT_ID:'client',GMAIL_CLIENT_SECRET:'secret'} as any;
 db.prepare("INSERT INTO bonds_settings(owner_id,encrypted_password,updated_at,scan_kind) VALUES('owner','unused',0,'wint')").run();
 db.prepare('INSERT INTO gmail_connections(owner_id,email,encrypted_refresh_token,connected_at) VALUES(?,?,?,?)').run('owner','example@example.com',await encrypt('refresh',key),0);
 const headers=[{name:'From',value:'transactions@wintwealth.com'},{name:'Subject',value:'Investment Successful for Example Finance'},{name:'Authentication-Results',value:'mx.google.com; dmarc=pass header.from=wintwealth.com'}];
 const upstream:typeof fetch=async url=>{
  const address=String(url);
  if(address.includes('oauth2'))return Response.json({access_token:'access'});
  if(address.includes('format=full'))return Response.json({payload:{mimeType:'text/html',headers,body:{data:Buffer.from('<p>'+purchase+'</p>').toString('base64url')}}});
  return Response.json(address.includes('pageToken=next')?{messages:[{id:'second'}]}:{messages:[{id:'first'}],nextPageToken:'next'});
 };
 await saveBondSnapshot(env,'owner',cas,'cas','cas',at);
 assert.equal((await syncBonds(env,'owner',upstream,at)).status,'scan_pending');
 assert.equal((await syncBonds(env,'owner',upstream,at)).status,'up_to_date');
 assert.equal(db.prepare('SELECT count(*) AS n FROM wint_events').get()?.n,1);
 assert.equal(db.prepare('SELECT count(*) AS n FROM wint_imports').get()?.n,2);
 const snapshot=zerodhaSnapshot('{"status":"success","data":[]}','{"status":"success","data":[]}',at);
 assert.equal((await bondsPortfolio(env,snapshot,'owner',at)).holdings.find(h=>h.symbol==='INE14H407116')?.bondTerms?.investedAmount,'49964.61');
});

test('principal and interest before the matched ownership window cannot redeem the current CAS lot',async()=>{
 const p=parseWintEmail('Investment Successful for Example Finance',purchase,at);if(p.kind!=='purchase')throw Error();
 const hash=await digest('owner:bonds:'+cas.accountID);
 const prior={kind:'principal',key:'old',isin:p.isin,date:'2026-06-01',principal:'40000',gross:'500',tds:'50',net:'450',nextPayout:null,reconciliationDifference:'0'} as const;
 const partial={...prior,kind:'redemption',key:'new',date:'2026-09-01',principal:'10000',gross:'100',tds:'10',net:'90'} as const;
 const result=reconcileBonds(cas,hash,[{accountHash:hash,event:p},{accountHash:null,event:prior},{accountHash:null,event:partial}],at);
 assert.equal(result.holdings.find(h=>h.symbol===p.isin)?.value,'50000');
 assert.equal(result.holdings.find(h=>h.symbol===p.isin)?.bondTerms?.principalReceived,'10000');
 assert.equal(result.holdings.find(h=>h.symbol===p.isin)?.bondTerms?.interestNet,'90');
 assert.equal(result.redeemed.length,0);
});

test('event ledger failure rolls back receipt upgrades and cancelled settings cannot save new events',async()=>{
 const {env,db}=setupGold(),receipt=parseWintEmail('Your order receipt for Example Finance is here',purchase,at);
 await saveWintEvent(env,'owner',receipt,'r',at);
 db.exec("CREATE TRIGGER fail_wint BEFORE INSERT ON wint_imports BEGIN SELECT RAISE(ABORT,'ledger failed'); END;");
 await assert.rejects(()=>saveWintEvent(env,'owner',parseWintEmail('Investment Successful for Example Finance',purchase,at),'c',at));
 const stored=(await readWintEvents(env,'owner'))[0].event;assert.equal(stored.kind==='purchase' && stored.confirmed,false);
 db.exec('DROP TRIGGER fail_wint');
 await assert.rejects(()=>saveWintEvent(env,'owner',parseWintEmail('💸 Just Credited: Monthly Interest for Muthoot MCred',paid,at),'cancel',at,123));
 assert.equal((await readWintEvents(env,'owner')).length,1);
});
test('five-message Wint batches stay within the free Worker database query budget',async()=>{
 const {env:base,db}=setupGold(),key=Buffer.alloc(32,1).toString('base64');let queries=0;
 const env={DB:{prepare(sql:string){queries++;return base.DB.prepare(sql);}},KITE_ENCRYPTION_KEY:key,GMAIL_CLIENT_ID:'client',GMAIL_CLIENT_SECRET:'secret'} as any;
 db.prepare("INSERT INTO bonds_settings(owner_id,encrypted_password,updated_at,scan_kind) VALUES('owner','unused',0,'wint')").run();
 db.prepare('INSERT INTO gmail_connections(owner_id,email,encrypted_refresh_token,connected_at) VALUES(?,?,?,?)').run('owner','example@example.com',await encrypt('refresh',key),0);
 const upstream:typeof fetch=async url=>{
  const address=String(url);
  if(address.includes('oauth2'))return Response.json({access_token:'access'});
  if(address.includes('format=full')){
   const id=/messages\/(m\d)/.exec(address)![1],body=purchase.replace('Order ID 123456','Order ID 12345'+id.slice(1));
   return Response.json({payload:{mimeType:'text/plain',headers:[{name:'From',value:'transactions@wintwealth.com'},{name:'Subject',value:'Investment Successful for Example Finance'},{name:'Authentication-Results',value:'mx.google.com; dmarc=pass header.from=wintwealth.com'}],body:{data:Buffer.from(body).toString('base64url')}}});
  }
  assert.equal(new URL(address).searchParams.get('maxResults'),'5');
  return Response.json({messages:Array.from({length:5},(_,i)=>({id:'m'+i}))});
 };
 const result=await syncBonds(env,'owner',upstream,at);
 assert.equal(result.imported,5);assert.equal(db.prepare('SELECT count(*) AS n FROM wint_events').get()?.n,5);assert.ok(queries<=50,`used ${queries} queries`);
});

// Wrong rate, duration, or receipt backfill must not silently alter the projection.
test('YTM is extracted separately from coupon and invalid or ambiguous yields require review',()=>{
 const p=parseWintEmail('Investment Successful for Example Finance',purchase,at);if(p.kind!=='purchase')throw Error();
 assert.equal(p.ytm,'11.75');assert.equal(p.coupon,'11');
 for(const raw of [purchase.replace('11.75%','-1%'),purchase.replace('11.75%','NaN%'),purchase.replace('11.75%','101%'),purchase+' YTM RATE (YTM AFTER BROKERAGE) 12%'])assert.throws(()=>parseWintEmail('Investment Successful for Example Finance',raw,at));
 const legacy=parseWintEmail('Investment Successful for Example Finance',purchase.replace('YTM RATE (YTM AFTER BROKERAGE) 11.75% ',''),at);assert.equal(legacy.kind==='purchase' && legacy.ytm,null);
});
test('projection compounds matched settled lots separately without changing CAS value or counting coupons twice',async()=>{
 const hash=await digest('owner:bonds:'+cas.accountID);
 const p=parseWintEmail('Investment Successful for Example Finance',purchase,at);if(p.kind!=='purchase')throw Error();
 const lot={...p,quantity:'5',invested:'10000',date:'2026-08-03',maturesOn:'2028-08-02',ytm:'10'};
 const result=reconcileBonds(cas,hash,[{accountHash:hash,event:lot}],at);
 const h=result.holdings.find(h=>h.symbol===p.isin)!;
 assert.equal(h.bondTerms?.projectedMaturityValue,'12100');assert.equal(h.bondTerms?.ytm,'10');assert.equal(h.value,'50000');assert.equal(h.gain,null);
 const lots=[{...lot,quantity:'2',invested:'10000'},{...lot,key:'other',quantity:'3',invested:'20000',ytm:'20'}];
 const combined=reconcileBonds(cas,hash,lots.map(event=>({accountHash:hash,event})),at).holdings.find(h=>h.symbol===p.isin)!;
 assert.equal(combined.bondTerms?.projectedMaturityValue,'40900');assert.equal(combined.bondTerms?.ytm,null);
 for(const event of [{...lot,ytm:null}])assert.equal(reconcileBonds(cas,hash,[{accountHash:hash,event}],at).holdings.find(h=>h.symbol===p.isin)?.bondTerms?.projectedMaturityValue,null);
});
test('YTM backfill upgrades legacy events atomically without regressing confirmed settlement or accepting conflicting yields',async()=>{
 const {env,db}=setupGold();const p=parseWintEmail('Investment Successful for Example Finance',purchase,at);if(p.kind!=='purchase')throw Error();
 const {ytm,...legacy}=p;
 await saveWintEvent(env,'owner',legacy,'old',at);
 assert.equal(await saveWintEvent(env,'owner',{...p,confirmed:false,date:p.orderDate},'receipt',at),'imported');
 const saved=(await readWintEvents(env,'owner'))[0].event;if(saved.kind!=='purchase')throw Error();
 assert.equal(saved.ytm,'11.75');assert.equal(saved.confirmed,true);assert.equal(saved.date,'2026-08-03');
 await assert.rejects(()=>saveWintEvent(env,'owner',{...p,ytm:'12'},'conflict-ytm',at));
 const {env:other,db:otherDB}=setupGold();await saveWintEvent(other,'owner',legacy,'legacy',at);
 otherDB.exec("CREATE TRIGGER fail_ytm BEFORE INSERT ON wint_imports BEGIN SELECT RAISE(ABORT,'ledger failed'); END;");
 await assert.rejects(()=>saveWintEvent(other,'owner',p,'upgrade',at));
 assert.equal((await readWintEvents(other,'owner'))[0].event.kind,'purchase');
 assert.equal(JSON.parse(String(otherDB.prepare('SELECT data FROM wint_events').get()?.data)).ytm,undefined);
});

test('CAS-corroborated receipt projections use order date and switch to confirmed settlement when available',async()=>{
 const hash=await digest('owner:bonds:'+cas.accountID);
 const p=parseWintEmail('Your order receipt for Example Finance is here',purchase,at);if(p.kind!=='purchase')throw Error();
 const lot={...p,invested:'10000',ytm:'10',orderDate:'2025-08-03',date:'2025-08-03',maturesOn:'2028-08-02'};
 const holding=(event:typeof lot)=>reconcileBonds(cas,hash,[{accountHash:hash,event}],at).holdings.find(h=>h.symbol===p.isin)!;
 assert.equal(holding(lot).bondTerms?.projectedMaturityValue,'13310');
 assert.equal(holding(lot).bondTerms?.projectionUsesOrderDate,true);
 const settled=holding({...lot,confirmed:true,date:'2026-08-03'});
 assert.equal(settled.bondTerms?.projectedMaturityValue,'12100');assert.equal(settled.bondTerms?.projectionUsesOrderDate,false);
 assert.equal(settled.value,'50000');
 assert.equal(holding({...lot,quantity:'4'}).bondTerms?.projectedMaturityValue,null);
});
