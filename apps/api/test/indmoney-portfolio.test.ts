import {test} from 'node:test';
import assert from 'node:assert/strict';
import {setupGold} from './helpers/database';
import {encrypt} from '../src/zerodha';
import {parseIndHoldings,syncINDmoney,indmoneyPortfolio} from '../src/indmoney-portfolio';
import {zerodhaSnapshot} from '../src/zerodha-portfolio';
const at=new Date('2026-10-10T03:00:00Z'),key=Buffer.alloc(32,1).toString('base64');
// Same fields as the authorized US_STOCK response; fictional financial values.
const sample={holdings:[{investment_code:'NVDA',investment:'NVIDIA Corporation',asset_type:'US_STOCK',assetclass_l2:'global_equity',invested_amount:800,market_value:1200,holding_percent:100,total_pnl:400,pnl_per:50,total_units:0.125,unit_price:9600,broker:'Drivewealth',market_cap:'large',one_day_change:40,one_day_change_percentage:3.448,invested_value_usd:10,current_value_usd:12,one_day_change_usd:0.4}],asset_summary:{total_value:1200,invested:800,one_day_change:40,one_day_change_percentage:3.448,total_value_usd:12,invested_usd:10,one_day_change_usd:0.4},source_status:{holdings:'success'}};
const envelope=(value:unknown)=>({structuredContent:{result:JSON.stringify(value)},content:[]});
test('US import preserves fractional shares and uses reported INR value and acquisition cost without reconverting',()=>{
 const h=parseIndHoldings(envelope(sample),at)[0];
 assert.equal(h.quantity,'0.125');assert.equal(h.value,'1200');assert.equal(h.invested,'800');assert.equal(h.gain,'400');
 assert.equal(h.quote,'96');assert.equal(h.quoteCurrency,'USD');assert.equal(h.fxRate,'100');
 assert.equal(h.costBasisKnown,true);
 assert.equal(h.valueUSD,'12');assert.equal(h.investedUSD,'10');assert.equal(h.gainUSD,'2');assert.equal(h.gainPercentUSD,'20');
 const unknown=structuredClone(sample);unknown.holdings[0].invested_amount=0;
 assert.equal(parseIndHoldings(envelope(unknown),at)[0].gain,null);
});
test('US import rejects duplicate holdings, missing/partial responses and mismatched totals instead of erasing old data',()=>{
 for(const value of [{}, {...sample,source_status:{holdings:'failed'}},{...sample,holdings:[...sample.holdings,...sample.holdings]},{...sample,asset_summary:{...sample.asset_summary,total_value:1300}},{...sample,holdings:[{...sample.holdings[0],total_units:-1}]},{...sample,holdings:[{...sample.holdings[0],asset_type:'IND_STOCK'}]}])assert.throws(()=>parseIndHoldings(envelope(value),at));
 const empty={holdings:[],asset_summary:{total_value:0},source_status:{holdings:'success'}};
 assert.deepEqual(parseIndHoldings(envelope(empty),at),[]);
});
async function context() {
 const {db,env:base}=setupGold(),env={...base,KITE_ENCRYPTION_KEY:key} as any;
 const creds={client_id:'client',client_secret:'secret',access_token:'access',refresh_token:'refresh',expires_at:at.getTime()+3600000};
 db.prepare('INSERT INTO indmoney_connections(owner_id,generation,encrypted_credentials,connected_at) VALUES(?,?,?,?)').run('owner','generation',await encrypt(JSON.stringify(creds),key),at.getTime());
 return {db,env};
}
function upstream(value:unknown):typeof fetch {return async(_url,options)=>{
 const rpc=JSON.parse(String(options?.body));
 if(rpc.method==='notifications/initialized')return new Response(null,{status:202});
 if(rpc.method==='initialize')return Response.json({jsonrpc:'2.0',id:rpc.id,result:{protocolVersion:'2025-03-26'}});
 assert.equal(rpc.method,'tools/call');assert.equal(rpc.params.name,'networth_holdings');assert.deepEqual(rpc.params.arguments,{asset_type:'US_STOCK'});
 return Response.json({jsonrpc:'2.0',id:rpc.id,result:envelope(value)});
};}
test('sync composes owner-scoped US allocation once and retains the previous snapshot after an upstream failure',async()=>{
 const {db,env}=await context();
 await syncINDmoney(env,'owner',upstream(sample),at);
 const base=zerodhaSnapshot('{"status":"success","data":[]}','{"status":"success","data":[]}',at);
 const first=await indmoneyPortfolio(env,base,'owner',at);
 assert.equal(first.holdings[0].valueUSD,'12');assert.equal(JSON.parse(String(db.prepare('SELECT snapshot FROM indmoney_snapshots').get()?.snapshot))[0].valueUSD,'12');
 assert.equal(first.value,'1200');assert.equal(first.allocation[0].assetClass,'usEquity');
 assert.equal((await indmoneyPortfolio(env,first,'owner',at)).holdings.length,1);
 assert.equal((await indmoneyPortfolio(env,base,'someone-else',at)).value,'0');
 await assert.rejects(()=>syncINDmoney(env,'owner',upstream({}),new Date(at.getTime()+60000)));
 const retained=await indmoneyPortfolio(env,base,'owner',at);
 assert.equal(retained.value,'1200');assert.equal(retained.connections.find((c:any)=>c.id==='indmoney')?.status,'attention');
 assert.equal(db.prepare('SELECT last_sync_at FROM indmoney_connections').get()?.last_sync_at,at.getTime());
});
test('disconnect or reconnect during sync prevents an older request from publishing its holdings',async()=>{
 const {db,env}=await context(),fetcher=upstream(sample);
 await assert.rejects(()=>syncINDmoney(env,'owner',async(url,options)=>{
  const rpc=JSON.parse(String(options?.body));
  if(rpc.method==='tools/call')db.prepare("UPDATE indmoney_connections SET generation='new',lease_until=0").run();
  return fetcher(url,options);
 },at));
 assert.equal(db.prepare('SELECT count(*) AS n FROM indmoney_snapshots').get()?.n,0);
});

import {scheduledINDmoney} from '../src/indmoney-portfolio';
test('background sync imports connected US holdings and skips revoked accounts',async()=>{
 const {db,env}=await context();
 await scheduledINDmoney(env,upstream(sample),at);
 assert.equal(db.prepare('SELECT count(*) AS n FROM indmoney_snapshots').get()?.n,1);
 await scheduledINDmoney(env,upstream(sample),new Date(at.getTime()+15*60000-1));
 assert.equal(db.prepare('SELECT last_sync_at FROM indmoney_connections').get()?.last_sync_at,at.getTime()+15*60000-1);
 db.prepare("UPDATE indmoney_connections SET status='reconnect'").run();
 await scheduledINDmoney(env,async()=>{throw Error('must not fetch');},new Date(at.getTime()+60000));
 assert.equal(db.prepare('SELECT error FROM indmoney_connections').get()?.error,null);
});
