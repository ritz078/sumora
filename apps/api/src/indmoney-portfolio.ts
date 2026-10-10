import {Decimal} from 'decimal.js';
import {parse,isLosslessNumber} from 'lossless-json';
import {APIError,type KiteEnvironment} from './zerodha';
import {indMCP,withIndConnection} from './indmoney-mcp';
import {portfolioTotals,type Portfolio} from './portfolio-valuation';
const Money=Decimal.clone({precision:50});
const invalid=()=>new APIError(502,'INDMONEY_INVALID_HOLDINGS','INDmoney returned incomplete US holdings. Your previous data is retained.');
function amount(value:unknown) {
 const text=isLosslessNumber(value)?value.value:typeof value==='number' || typeof value==='string'?String(value):null;
 if(text===null)throw invalid();
 let result:Decimal;try{result=new Money(text);}catch{throw invalid();}
 if(!result.isFinite() || result.isNegative() || result.gt('1e18'))throw invalid();return result;
}
export function parseIndHoldings(result:any,at:Date):Portfolio['holdings'] {
 let payload=result?.structuredContent?.result;
 if(payload===undefined) {
  const content=result?.content?.filter((c:any)=>c.type==='text');
  if(content?.length!==1)throw invalid();
  payload=content[0].text;
 }
 if(typeof payload!=='string' || payload.length>2*1024*1024)throw invalid();
 let value:any;try{value=parse(payload);}catch{throw invalid();}
 // Some MCP servers wrap the output-schema result in a text content block.
 if(typeof value?.result==='string')try{value=parse(value.result);}catch{throw invalid();}
 if(value?.source_status?.holdings!=='success' || !Array.isArray(value.holdings) || value.holdings.length>1000)throw invalid();
 const seen=new Set<string>(),timestamp=at.toISOString().replace('.000Z','Z');
 const holdings:Portfolio['holdings']=value.holdings.map((row:any)=>{
  if(row?.asset_type!=='US_STOCK' || typeof row.investment_code!=='string' || !/^[A-Z0-9.^_-]{1,32}$/.test(row.investment_code) || typeof row.investment!=='string' || !row.investment || row.investment.length>200 || typeof row.broker!=='string' || !row.broker || row.broker.length>100)throw invalid();
  const id='indmoney:us:'+encodeURIComponent(row.broker)+':'+row.investment_code;
  if(seen.has(id))throw invalid();seen.add(id);
  const quantity=amount(row.total_units),inr=amount(row.market_value),usd=amount(row.current_value_usd);
  if(!quantity.gt(0) || !usd.gt(0) || !inr.gt(0))throw invalid();
  const invested=amount(row.invested_amount??0),known=invested.gt(0),gain=inr.minus(invested);
  const investedUSD=row.invested_value_usd==null?null:amount(row.invested_value_usd),usdCostKnown=investedUSD!==null && investedUSD.gt(0),gainUSD=usdCostKnown?usd.minus(investedUSD):null;
  return {id,name:row.investment,symbol:row.investment_code,assetClass:'usEquity',accountID:'indmoney',quantity:quantity.toFixed(),unit:'shares',
   valueUSD:usd.toFixed(),investedUSD:usdCostKnown?investedUSD.toFixed():null,gainUSD:gainUSD?.toFixed()??null,gainPercentUSD:gainUSD && investedUSD?gainUSD.div(investedUSD).times(100).toFixed():null,
   invested:invested.toFixed(),costBasisKnown:known,value:inr.toFixed(),gain:known?gain.toFixed():null,gainPercent:known?gain.div(invested).times(100).toFixed():null,
   quote:usd.div(quantity).toFixed(),quoteCurrency:'USD',fxRate:inr.div(usd).toFixed(),fxAt:timestamp,quoteAt:timestamp,
   source:'INDmoney · '+row.broker,priceBasis:'Reported US holdings value in INR. USD unit value and implied INR/USD conversion are derived from the same snapshot. Retrieved '+timestamp+'; INDmoney does not provide a market-price or FX quote timestamp. Daily performance uses INDmoney’s trading-session definition and is not included in Sumora’s midnight baseline.',history:[]};
 });
 const total=holdings.reduce((s,h)=>s.plus(h.value!),new Money(0));
 if(total.minus(amount(value.asset_summary?.total_value)).abs().gt(new Money('0.01').times(Math.max(1,holdings.length))))throw invalid();
 return holdings;
}
export async function syncINDmoney(env:KiteEnvironment,owner:string,fetcher:typeof fetch=fetch,at=new Date()) {
 return withIndConnection(env,owner,async(token,connection)=>{
  const client=await indMCP(token,fetcher);
  const holdings=parseIndHoldings(await client.call('networth_holdings',{asset_type:'US_STOCK'}),at);
  // Publish only while this exact connection owns the lease. A reconnect/disconnect
  // must never allow an older in-flight response to reintroduce stale holdings.
  const saved=await env.DB.prepare(`INSERT INTO indmoney_snapshots(owner_id,snapshot,captured_at)
   SELECT owner_id,?,? FROM indmoney_connections WHERE owner_id=? AND generation=? AND lease_until=?
   ON CONFLICT(owner_id) DO UPDATE SET snapshot=excluded.snapshot,captured_at=excluded.captured_at
   WHERE excluded.captured_at>=indmoney_snapshots.captured_at RETURNING owner_id`)
   .bind(JSON.stringify(holdings),at.getTime(),owner,connection.generation,connection.lease).first();
  if(!saved)throw new APIError(409,'INDMONEY_CONNECTION_CHANGED','INDmoney connection changed. Try again.');
  await env.DB.prepare('UPDATE indmoney_connections SET last_sync_at=? WHERE owner_id=? AND generation=? AND lease_until=?').bind(at.getTime(),owner,connection.generation,connection.lease).run();
  return {imported:holdings.length,lastSyncAt:at.getTime()};
 },fetcher,()=>at.getTime());
}
export async function indmoneyPortfolio(env:Pick<KiteEnvironment,'DB'>,snapshot:Portfolio,owner:string,at=new Date()):Promise<Portfolio> {
 const row=await env.DB.prepare('SELECT c.status,c.error,c.last_sync_at,s.snapshot,s.captured_at FROM indmoney_connections c LEFT JOIN indmoney_snapshots s ON s.owner_id=c.owner_id WHERE c.owner_id=?').bind(owner).first<{status:string;error:string|null;last_sync_at:number|null;snapshot:string|null;captured_at:number|null}>();
 const holdings=snapshot.holdings.filter(h=>h.accountID!=='indmoney'),connections=snapshot.connections.filter(c=>c.id!=='indmoney');
 if(!row)return holdings.length===snapshot.holdings.length?snapshot:portfolioTotals({...snapshot,holdings,connections});
 const attention=row.status!=='connected' || !!row.error || row.captured_at===null || at.getTime()-row.captured_at>24*3600000;
 return portfolioTotals({...snapshot,holdings:[...holdings,...JSON.parse(row.snapshot??'[]')],connections:[...connections,{id:'indmoney',name:'INDmoney',symbol:'I',status:attention?'attention':'connected',lastSyncAt:row.last_sync_at===null?null:new Date(row.last_sync_at).toISOString(),description:row.error??(row.snapshot===null?'US holdings have not synced yet.':'US stocks held in INDmoney; reported INR valuation. Latest successful snapshot is retained if sync fails.')}]});
}

// Allow a minute of cron execution jitter while suppressing immediate retries.
export async function scheduledINDmoney(env:KiteEnvironment,fetcher:typeof fetch=fetch,at=new Date()) {
 const row=await env.DB.prepare("SELECT owner_id FROM indmoney_connections WHERE status='connected' AND lease_until<=? AND COALESCE(last_attempt_at,0)<=? ORDER BY COALESCE(last_attempt_at,0) LIMIT 1").bind(at.getTime(),at.getTime()-14*60000).first<{owner_id:string}>();
 if(!row)return;
 try {await syncINDmoney(env,row.owner_id,fetcher,at);}catch { /* Error is persisted; previous holdings remain available. */ }
}
