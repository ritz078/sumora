import { Decimal } from 'decimal.js';
import { istDate, type MarketPrice } from './daily-prices';
import type { KiteEnvironment } from './zerodha';
export const GOLD_ID = 'XAU.24K.INR.G';
export const GOLD_URL = 'https://snapdata.dev/api/v1/gold/in/latest.json';
export function validDay(value: unknown): value is string {
 return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) && Number.isFinite(Date.parse(value+'T00:00:00Z')) && new Date(value+'T00:00:00Z').toISOString().slice(0,10) === value;
}
export function parseGoldPrice(value: unknown, at = new Date()): MarketPrice {
 const data = value as any;
 if (!data || data.schema_version !== '1.0' || data.dataset !== 'gold' || data.scope !== 'in' || data.resolution !== 'daily' || data.unit?.currency !== 'INR' || data.unit?.quantity !== 'gram' || !Array.isArray(data.observations) || !data.sources?.some((s:any)=>s.id==='ibja')) throw new Error('Unexpected gold feed schema or units.');
 const matches = data.observations.filter((p:any)=>p.instrument_id===GOLD_ID);
 if(matches.length!==1) throw new Error('Missing or ambiguous 24K quote.');
 const p=matches[0];
 if(!validDay(p.date) || p.date>istDate(at) || p.source!=='ibja' || !['provisional','final','observed'].includes(p.status) || !['number','string'].includes(typeof p.value) || !/^\d+(?:\.\d+)?$/.test(String(p.value))) throw new Error('Invalid gold observation.');
 const price=new Decimal(p.value);
 if(!price.isFinite() || price.lte(0) || price.gt(10000000)) throw new Error('Invalid gold price.');
 return {kind:'gold',isin:GOLD_ID,price:price.toFixed(),date:p.date,source:'Snapdata / IBJA daily benchmark'+(p.status==='provisional'?' (provisional)':'')};
}
export async function boundedJSON(response: Response, limit = 256*1024): Promise<any> {
 if(!response.ok || !response.body || Number(response.headers.get('content-length'))>limit) {await response.body?.cancel();throw new Error('Feed unavailable or too large.');}
 const reader=response.body.getReader();let length=0;const chunks:Uint8Array[]=[];
 try {while(true){const {done,value}=await reader.read();if(done)break;length+=value.length;if(length>limit)throw new Error('Response too large.');chunks.push(value);}}finally{await reader.cancel();}
 const bytes=new Uint8Array(length);let offset=0;for(const c of chunks){bytes.set(c,offset);offset+=c.length;}
 return JSON.parse(new TextDecoder().decode(bytes));
}
export async function refreshGoldPrice(env: Pick<KiteEnvironment,'DB'>, fetcher:typeof fetch=fetch, at=new Date()) {
 const lease=at.getTime()+120000;
 const lock=await env.DB.prepare('UPDATE gold_price_job SET running_until=? WHERE id=1 AND running_until<=? RETURNING id').bind(lease,at.getTime()).first();
 if(!lock)return {updated:0,skipped:true};
 let error:string|null=null;
 try {
  const quote=parseGoldPrice(await boundedJSON(await fetcher(GOLD_URL,{signal:AbortSignal.timeout(15000),redirect:'manual'})),at);
  // Freeze the previous persisted day before replacing the latest quote.
  await env.DB.prepare(`INSERT INTO daily_price_baselines(day,kind,isin,price,price_date,source)
   SELECT ?,kind,isin,price,date,source FROM market_prices WHERE kind='gold' AND date<?
   ON CONFLICT(day,kind,isin) DO UPDATE SET price=excluded.price,price_date=excluded.price_date,source=excluded.source WHERE excluded.price_date>daily_price_baselines.price_date`).bind(istDate(at),istDate(at)).run();
  const baseline=await env.DB.prepare("SELECT price FROM daily_price_baselines WHERE day=? AND kind='gold' AND isin=?").bind(istDate(at),GOLD_ID).first();
  if(!baseline) {
   let previous=await env.DB.prepare('SELECT date,price,source FROM gold_price_history WHERE date<? ORDER BY date DESC LIMIT 1').bind(istDate(at)).first<{date:string;price:string;source:string}>();
   if(!previous)for(let days=1;days<=7;days++) {
    const date=istDate(new Date(at.getTime()-days*86400000));
    try {
     const historic=parseGoldPrice(await boundedJSON(await fetcher(`https://snapdata.dev/api/v1/gold/in/${date}.json`,{signal:AbortSignal.timeout(5000),redirect:'manual'})),at);
     if(historic.date!==date)continue;
     previous=historic;
     await env.DB.prepare('INSERT INTO gold_price_history(date,price,source,fetched_at) VALUES(?,?,?,?) ON CONFLICT DO NOTHING').bind(historic.date,historic.price,historic.source,at.getTime()).run();
     break;
    }catch{/* A missing historic snapshot must not block today's price. */}
   }
   if(previous)await env.DB.prepare("INSERT INTO daily_price_baselines(day,kind,isin,price,price_date,source) VALUES(?,'gold',?,?,?,?) ON CONFLICT DO NOTHING").bind(istDate(at),GOLD_ID,previous.price,previous.date,previous.source).run();
  }
  const current=await env.DB.prepare("SELECT date FROM market_prices WHERE kind='gold' AND isin=?").bind(GOLD_ID).first<{date:string}>();
  if(current && quote.date<current.date)return {updated:0};
  await env.DB.prepare(`INSERT INTO gold_price_history(date,price,source,fetched_at) VALUES(?,?,?,?) ON CONFLICT(date) DO UPDATE SET price=excluded.price,source=excluded.source,fetched_at=excluded.fetched_at`).bind(quote.date,quote.price,quote.source,at.getTime()).run();
  await env.DB.prepare(`INSERT INTO market_prices(kind,isin,price,date,source,updated_at) VALUES('gold',?,?,?,?,?) ON CONFLICT(kind,isin) DO UPDATE SET price=excluded.price,date=excluded.date,source=excluded.source,updated_at=excluded.updated_at WHERE excluded.date>=market_prices.date`).bind(GOLD_ID,quote.price,quote.date,quote.source,at.getTime()).run();
  return {updated:1};
 }catch{error='Gold price could not be updated. Keeping the last available price.';return {updated:0,error};}
 finally{await env.DB.prepare('UPDATE gold_price_job SET running_until=0,last_run_at=?,error=? WHERE id=1 AND running_until=?').bind(at.getTime(),error,lease).run();}
}
