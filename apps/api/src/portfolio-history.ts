import {Hono} from 'hono';
import {Decimal} from 'decimal.js';
import {APIError,appSession,type KiteEnvironment} from './zerodha';
import {istDate} from './daily-prices';
import {validDay} from './gold-prices';
import {portfolioTotals,type Portfolio} from './portfolio-valuation';
import {zerodhaSnapshot} from './zerodha-portfolio';
import {valuedSnapshot} from './daily-valuation-job';

type Environment=Pick<KiteEnvironment,'DB'>;
const Money=Decimal.clone({precision:50});
const classes=['indianEquity','mutualFund','usEquity','gold','fixedDeposit','bond','nps','realEstate'] as const;
function sourceDay(value:string|null|undefined) {
 if(!value || !Number.isFinite(Date.parse(value)))return null;
 return istDate(new Date(value));
}

/** Today's latest observation, not an inferred end-of-day or historical market value. */
export async function capturePortfolioDay(env:Environment,owner:string,input:Portfolio,at=new Date()) {
 const day=istDate(at),portfolio=portfolioTotals(input);
 const holdingDates=portfolio.holdings.map(h=>{
  const retrievalOnly=h.accountID==='indmoney' || h.quoteTimestampIsRetrieval===true;
  const valuationAsOf=retrievalOnly?null:h.quoteAt??null,valuationDay=sourceDay(valuationAsOf);
  const statementQuantity=h.assetClass==='nps' || h.assetClass==='fixedDeposit';
  const quantityAsOf=statementQuantity?h.quoteAt??null:h.propertyTerms?new Date(h.propertyTerms.updatedAt).toISOString():portfolio.connections.find(c=>c.id===h.accountID)?.lastSyncAt??(retrievalOnly?h.quoteAt??null:portfolio.holdingsSyncAt);
  return {id:h.id,valuationAsOf,quantityAsOf,sourceRetrievedAt:retrievalOnly?h.quoteAt??null:null,
   carriedForward:valuationDay===null || valuationDay>day?null:valuationDay<day};
 });
 const instruments=classes.map(assetClass=>{
  const holdings=portfolio.holdings.filter(h=>h.assetClass===assetClass),valued=holdings.filter(h=>h.value!==null);
  const dates=holdingDates.filter(d=>holdings.some(h=>h.id===d.id));
  return {assetClass,holdingCount:holdings.length,valuedHoldingCount:valued.length,
   value:holdings.length && !valued.length?null:valued.reduce((sum,h)=>sum.plus(h.value!),new Money(0)).toFixed(),
   coverage:valued.length===holdings.length?'complete':valued.length?'partial':'unavailable',
   carriedForwardCount:dates.filter(d=>d.carriedForward===true).length,unknownValuationDateCount:dates.filter(d=>d.carriedForward===null).length};
 });
 const record={schemaVersion:1,day,capturedAt:at.toISOString(),reportingCurrency:portfolio.reportingCurrency,value:portfolio.value,coverage:portfolio.coverage,instruments,holdingDates,portfolio};
 await env.DB.prepare(`INSERT INTO portfolio_daily_snapshots(owner_id,day,captured_at,data) VALUES(?,?,?,?)
  ON CONFLICT(owner_id,day) DO UPDATE SET captured_at=excluded.captured_at,data=excluded.data
  WHERE excluded.captured_at>portfolio_daily_snapshots.captured_at`).bind(owner,day,at.getTime(),JSON.stringify(record)).run();
 return record;
}

/** One owner per invocation bounds D1 work; attempt rotation also moves past failing sources. */
export async function scheduledPortfolioSnapshots(env:Environment,at=new Date()) {
 // D1 bounds compound SELECT terms; keep each UNION group small.
 const next=await env.DB.prepare(`WITH core_owners AS (
  SELECT owner_id FROM zerodha_snapshots UNION SELECT owner_id FROM properties
  UNION SELECT owner_id FROM gullak_checkpoints UNION SELECT owner_id FROM hdfc_snapshots
 ), other_owners AS (
  SELECT owner_id FROM nps_snapshots UNION SELECT owner_id FROM bonds_snapshots
  UNION SELECT owner_id FROM indmoney_snapshots
 ), owners AS (SELECT owner_id FROM core_owners UNION SELECT owner_id FROM other_owners)
 SELECT o.owner_id,z.snapshot FROM owners o
 LEFT JOIN zerodha_snapshots z ON z.owner_id=o.owner_id
 LEFT JOIN portfolio_snapshot_jobs j ON j.owner_id=o.owner_id
 ORDER BY COALESCE(j.last_attempt_at,0),o.owner_id LIMIT 1`).first<{owner_id:string;snapshot:string|null}>();
 if(!next)return {captured:0,failed:0};
 await env.DB.prepare(`INSERT INTO portfolio_snapshot_jobs(owner_id,last_attempt_at,last_error) VALUES(?,?,NULL)
  ON CONFLICT(owner_id) DO UPDATE SET last_attempt_at=excluded.last_attempt_at`).bind(next.owner_id,at.getTime()).run();
 try {
  const base=next.snapshot===null?zerodhaSnapshot('{"status":"success","data":[]}','{"status":"success","data":[]}',at):JSON.parse(next.snapshot) as Portfolio;
  if(next.snapshot===null)base.connections=[];
  const snapshot=await valuedSnapshot(env,base,at,next.owner_id);
  await capturePortfolioDay(env,next.owner_id,snapshot,at);
  await env.DB.prepare('UPDATE portfolio_snapshot_jobs SET last_error=NULL WHERE owner_id=? AND last_attempt_at=?').bind(next.owner_id,at.getTime()).run();
  return {captured:1,failed:0};
 }catch {
  await env.DB.prepare('UPDATE portfolio_snapshot_jobs SET last_error=? WHERE owner_id=? AND last_attempt_at=?').bind('Snapshot failed; previous history is retained.',next.owner_id,at.getTime()).run();
  return {captured:0,failed:1};
 }
}

export function portfolioHistoryRoutes(now=Date.now) {
 const app=new Hono<{Bindings:KiteEnvironment}>();
 app.onError((error,c)=>{const e=error instanceof APIError?error:new APIError(500,'HISTORY_UNAVAILABLE','Unable to load saved portfolio history.');return c.json({error:{code:e.code,message:e.message}},e.status);});
 app.get('/',async c=>{
  const auth=await appSession(c.env,c.req.header('Authorization'),now);
  const today=istDate(new Date(now())),to=c.req.query('to')??today;
  const from=c.req.query('from')??(validDay(to)?new Date(Date.parse(to+'T00:00:00Z')-29*86400000).toISOString().slice(0,10):'');
  if(!validDay(from) || !validDay(to) || from>to || to>today || Date.parse(to)-Date.parse(from)>89*86400000)throw new APIError(400,'INVALID_HISTORY_RANGE','Choose a valid date range of up to 90 days, ending today or earlier.');
  const row=await c.env.DB.prepare(`SELECT json_group_array(json_object('day',day,'capturedAt',json_extract(data,'$.capturedAt'),
   'reportingCurrency',json_extract(data,'$.reportingCurrency'),'value',json_extract(data,'$.value'),
   'coverage',json_extract(data,'$.coverage'),'instruments',json(json_extract(data,'$.instruments')))) AS snapshots
   FROM (SELECT day,data FROM portfolio_daily_snapshots WHERE owner_id=? AND day>=? AND day<=? ORDER BY day)`)
   .bind(auth.owner_id,from,to).first<{snapshots:string}>();
  const first=await c.env.DB.prepare('SELECT MIN(day) AS day FROM portfolio_daily_snapshots WHERE owner_id=?').bind(auth.owner_id).first<{day:string|null}>();
  return c.json({timezone:'Asia/Kolkata',from,to,firstRecordedDay:first?.day??null,snapshots:JSON.parse(row?.snapshots??'[]')});
 });
 app.get('/:day',async c=>{
  const auth=await appSession(c.env,c.req.header('Authorization'),now),day=c.req.param('day');
  if(!validDay(day))throw new APIError(400,'INVALID_HISTORY_DATE','Choose a valid snapshot date.');
  const row=await c.env.DB.prepare('SELECT data FROM portfolio_daily_snapshots WHERE owner_id=? AND day=?').bind(auth.owner_id,day).first<{data:string}>();
  if(!row)throw new APIError(404,'HISTORY_NOT_FOUND','No portfolio snapshot was recorded for this day.');
  return c.json(JSON.parse(row.data));
 });
 return app;
}
