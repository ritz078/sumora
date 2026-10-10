import {test} from 'node:test';
import assert from 'node:assert/strict';
import {setupGold} from './helpers/database';
import {zerodhaSnapshot} from '../src/zerodha-portfolio';
import {digest} from '../src/zerodha';
import worker,{app} from '../src/index';
import * as history from '../src/portfolio-history';

function base(){return zerodhaSnapshot('{"status":"success","data":[]}','{"status":"success","data":[]}',new Date('2026-10-10T10:00:00Z'));}
function holding(assetClass:string,value:string|null,extra:Record<string,unknown>={}) {return {id:assetClass,name:assetClass,symbol:assetClass,assetClass,accountID:assetClass,quantity:'2',unit:'units',invested:'0',costBasisKnown:false,value,gain:null,gainPercent:null,quote:null,quoteCurrency:'INR',fxRate:'1',fxAt:null,quoteAt:'2026-10-09T00:00:00Z',source:'Saved source',priceBasis:'Recorded valuation',history:[],...extra} as any;}
function cached(db:any,owner:string,snapshot=base()){db.prepare('INSERT INTO zerodha_snapshots VALUES(?,?,?) ON CONFLICT(owner_id) DO UPDATE SET snapshot=excluded.snapshot').run(owner,JSON.stringify(snapshot),0);}

test('daily snapshots retain all instrument values, exact decimals, quantities and dated valuation provenance',async()=>{
 const {env,db}=setupGold();
 const snapshot=base();snapshot.holdings=[holding('indianEquity','100.01'),holding('mutualFund','200.02'),holding('usEquity','300.03'),holding('gold','400.04'),holding('fixedDeposit','500.05'),holding('bond','600.06',{bondTerms:{valuationBasis:'projectedMaturity',ytm:'10',projectedMaturityValue:'600.06'}}),holding('nps','700.07'),holding('realEstate','800.08',{quoteAt:null})];
 await history.capturePortfolioDay(env,'one',snapshot,new Date('2026-10-10T18:29:00Z'));
 const saved=JSON.parse(db.prepare('SELECT data FROM portfolio_daily_snapshots').get()!.data as string);
 assert.equal(saved.day,'2026-10-10');assert.equal(saved.value,'3600.36');assert.equal(saved.instruments.length,8);
 assert.equal(saved.instruments.find((x:any)=>x.assetClass==='bond').value,'600.06');
 assert.equal(saved.portfolio.holdings[5].bondTerms.valuationBasis,'projectedMaturity');
 assert.equal(saved.portfolio.holdings[0].quantity,'2');assert.equal(saved.portfolio.holdings[0].priceBasis,'Recorded valuation');
 assert.equal(saved.holdingDates[0].valuationAsOf,'2026-10-09T00:00:00Z');assert.equal(saved.holdingDates[0].carriedForward,true);
 assert.equal(saved.holdingDates[7].carriedForward,null);
});

test('same-day retries replace only older observations and midnight creates a separate day without rewriting history',async()=>{
 const {env,db}=setupGold();const p=base();p.holdings=[holding('gold','10')];
 await history.capturePortfolioDay(env,'one',p,new Date('2026-10-10T18:00:00Z'));
 p.holdings[0].value='20';await history.capturePortfolioDay(env,'one',p,new Date('2026-10-10T18:20:00Z'));
 p.holdings[0].value='5';await history.capturePortfolioDay(env,'one',p,new Date('2026-10-10T18:10:00Z'));
 p.holdings[0].value='30';await history.capturePortfolioDay(env,'one',p,new Date('2026-10-10T18:30:00Z'));
 const rows=db.prepare('SELECT day,data FROM portfolio_daily_snapshots ORDER BY day').all();
 assert.equal(rows.length,2);assert.equal(JSON.parse(rows[0].data as string).value,'20');assert.equal(rows[1].day,'2026-10-11');assert.equal(JSON.parse(rows[1].data as string).value,'30');
});

test('unpriced holdings remain unavailable and partial totals are marked rather than inventing zero prices',async()=>{
 const {env,db}=setupGold();const p=base();p.holdings=[holding('gold',null),holding('nps','50'),holding('nps',null,{id:'nps-two'})];
 await history.capturePortfolioDay(env,'one',p,new Date('2026-10-10T12:00:00Z'));
 const saved=JSON.parse(db.prepare('SELECT data FROM portfolio_daily_snapshots').get()!.data as string);
 assert.equal(saved.coverage,'partial');assert.equal(saved.value,'50');
 assert.equal(saved.instruments.find((x:any)=>x.assetClass==='gold').value,null);
 assert.equal(saved.instruments.find((x:any)=>x.assetClass==='nps').coverage,'partial');
 assert.equal(saved.instruments.find((x:any)=>x.assetClass==='bond').holdingCount,0);
});

test('scheduled capture composes stored sources without broker access and rotates owners within the query budget',async()=>{
 const {env,db}=setupGold();cached(db,'one');cached(db,'two');
 db.prepare('INSERT INTO properties VALUES(?,?,?,?)').run('one','p',JSON.stringify({id:'p',name:'Home',estimatedValue:'10000000',ownershipPercent:'50',valuationDate:'2026-10-01',purchaseCost:null,updatedAt:0}),0);
 assert.equal((await history.scheduledPortfolioSnapshots(env,new Date('2026-10-10T12:00:00Z'))).captured,1);
 assert.equal((await history.scheduledPortfolioSnapshots(env,new Date('2026-10-10T12:15:00Z'))).captured,1);
 const rows=db.prepare('SELECT owner_id,data FROM portfolio_daily_snapshots ORDER BY owner_id').all();
 assert.equal(rows.length,2);assert.equal(JSON.parse(rows[0].data as string).value,'5000000');assert.equal(JSON.parse(rows[1].data as string).value,'0');
 // Missing broker snapshot must not prevent manual-only accounts from recording history.
 db.prepare('DELETE FROM zerodha_snapshots WHERE owner_id=?').run('one');
 await history.scheduledPortfolioSnapshots(env,new Date('2026-10-10T12:30:00Z'));
 assert.equal(JSON.parse(db.prepare('SELECT data FROM portfolio_daily_snapshots WHERE owner_id=?').get('one')!.data as string).value,'5000000');
});

test('malformed source failures keep previous daily data and do not publish a fake empty portfolio',async()=>{
 const {env,db}=setupGold();cached(db,'one');await history.scheduledPortfolioSnapshots(env,new Date('2026-10-10T12:00:00Z'));
 const before=db.prepare('SELECT data FROM portfolio_daily_snapshots').get()!.data;
 db.prepare('UPDATE zerodha_snapshots SET snapshot=?').run('{bad');
 assert.equal((await history.scheduledPortfolioSnapshots(env,new Date('2026-10-10T12:15:00Z'))).failed,1);
 assert.equal(db.prepare('SELECT data FROM portfolio_daily_snapshots').get()!.data,before);
});

test('history endpoints authenticate, isolate accounts and validate bounded calendar ranges',async()=>{
 const {env,db}=setupGold();const token='1'.repeat(64);
 db.prepare('INSERT INTO zerodha_sessions VALUES(?,?,?,?,?)').run(await digest(token),'unused','one',Date.now()+86400000,0);
 const p=base();p.holdings=[holding('gold','10')];await history.capturePortfolioDay(env,'one',p,new Date('2026-10-10T12:00:00Z'));
 p.holdings[0].value='999';await history.capturePortfolioDay(env,'two',p,new Date('2026-10-09T12:00:00Z'));
 const call=(path:string,auth=true)=>app.request('/v1/portfolio/history'+path,{headers:auth?{Authorization:'Bearer '+token}:{}},env as any);
 assert.equal((await call('',false)).status,401);
 const list=await (await call('?from=2026-10-01&to=2026-10-10')).json() as any;
 assert.equal(list.snapshots.length,1);assert.equal(list.snapshots[0].value,'10');assert.equal(list.snapshots[0].portfolio,undefined);
 assert.equal((await call('/2026-10-09')).status,404);
 const detail=await (await call('/2026-10-10')).json() as any;assert.equal(detail.portfolio.holdings[0].value,'10');
 for(const query of ['?from=2026-02-30','?from=2025-01-01&to=2026-10-10','?from=2026-10-10&to=2026-10-01'])assert.equal((await call(query)).status,400);
});

test('the existing scheduled event records history without an open app and stays below the free D1 query limit',async()=>{
 const {env,db}=setupGold();const p=base();p.holdings=Array.from({length:100},(_,i)=>holding('indianEquity','1.01',{id:'stock-'+i}));cached(db,'one',p);
 let queries=0;const prepare=env.DB.prepare.bind(env.DB);env.DB.prepare=(query:string)=>{queries++;return prepare(query);};
 await worker.scheduled({cron:'*/15 * * * *'},env as any);
 const row=db.prepare('SELECT data FROM portfolio_daily_snapshots WHERE owner_id=?').get('one');
 assert.ok(row);assert.equal(JSON.parse(row.data as string).value,'101');assert.ok(queries<50,`Used ${queries} queries`);
});

test('a failed owner does not starve another account on the next scheduled attempt',async()=>{
 const {env,db}=setupGold();cached(db,'one');cached(db,'two');db.prepare('UPDATE zerodha_snapshots SET snapshot=? WHERE owner_id=?').run('{bad','one');
 assert.equal((await history.scheduledPortfolioSnapshots(env,new Date('2026-10-10T12:00:00Z'))).failed,1);
 assert.equal((await history.scheduledPortfolioSnapshots(env,new Date('2026-10-10T12:15:00Z'))).captured,1);
 assert.equal(db.prepare('SELECT owner_id FROM portfolio_daily_snapshots').get()!.owner_id,'two');
});

test('NPS tier dates remain separate and US retrieval time is not presented as a market valuation date',async()=>{
 const {env,db}=setupGold();const p=base();
 p.connections=[{id:'nps',name:'NPS',symbol:'N',status:'connected',lastSyncAt:'2026-10-10T00:00:00Z',description:''}];
 p.holdings=[holding('nps','10',{id:'tier-I',accountID:'nps',quoteAt:'2026-09-30T00:00:00Z'}),holding('nps','20',{id:'tier-II',accountID:'nps',quoteAt:'2026-10-10T00:00:00Z'}),holding('usEquity','30',{accountID:'indmoney',quoteAt:'2026-10-10T10:00:00Z'})];
 await history.capturePortfolioDay(env,'one',p,new Date('2026-10-10T12:00:00Z'));
 const saved=JSON.parse(db.prepare('SELECT data FROM portfolio_daily_snapshots').get()!.data as string);
 assert.equal(saved.holdingDates[0].quantityAsOf,'2026-09-30T00:00:00Z');
 assert.equal(saved.holdingDates[1].quantityAsOf,'2026-10-10T00:00:00Z');
 assert.equal(saved.holdingDates[2].valuationAsOf,null);assert.equal(saved.holdingDates[2].carriedForward,null);
 assert.equal(saved.holdingDates[2].sourceRetrievedAt,'2026-10-10T10:00:00Z');
});

test('fresh US retrievals cannot hide independent stock closes behind a newer portfolio timestamp',async()=>{
 const {env,db}=setupGold();const p=base();p.capturedAt=p.holdingsSyncAt='2026-10-01T00:00:00Z';
 p.holdings=[holding('indianEquity','100',{id:'zerodha:eq:INE000A01010',quantity:'1',quote:'100',quoteAt:null})];cached(db,'one',p);
 db.prepare('INSERT INTO market_prices VALUES(?,?,?,?,?,?)').run('indianEquity','INE000A01010','120','2026-10-09','NSE daily close',0);
 db.prepare('INSERT INTO indmoney_connections(owner_id,generation,encrypted_credentials,connected_at,last_sync_at,status) VALUES(?,?,?,?,?,?)').run('one','g','unused',0,Date.parse('2026-10-10T10:00:00Z'),'connected');
 db.prepare('INSERT INTO indmoney_snapshots VALUES(?,?,?)').run('one',JSON.stringify([holding('usEquity','30',{id:'us',accountID:'indmoney',quoteAt:'2026-10-10T10:00:00Z'})]),Date.parse('2026-10-10T10:00:00Z'));
 await history.scheduledPortfolioSnapshots(env,new Date('2026-10-10T12:00:00Z'));
 const saved=JSON.parse(db.prepare('SELECT data FROM portfolio_daily_snapshots').get()!.data as string);
 assert.equal(saved.portfolio.holdings[0].value,'120');assert.equal(saved.portfolio.holdings[0].dailyGain,'0');assert.equal(saved.value,'150');
});

test('instrument totals preserve the same high precision as net worth',async()=>{
 const {env,db}=setupGold();const p=base();p.holdings=[holding('usEquity','123456789012345678.123456789')];
 await history.capturePortfolioDay(env,'one',p,new Date('2026-10-10T12:00:00Z'));
 const saved=JSON.parse(db.prepare('SELECT data FROM portfolio_daily_snapshots').get()!.data as string);
 assert.equal(saved.value,'123456789012345678.123456789');assert.equal(saved.instruments.find((i:any)=>i.assetClass==='usEquity').value,'123456789012345678.123456789');
});

test('undated broker quotes retain unknown valuation dates and manual-only accounts do not invent a broker connection',async()=>{
 const {env,db}=setupGold();const p=base();p.capturedAt='2026-10-10T10:00:00Z';p.holdings=[holding('indianEquity','100',{accountID:'zerodha',quote:'50',quoteAt:null})];cached(db,'one',p);
 await history.scheduledPortfolioSnapshots(env,new Date('2026-10-10T12:00:00Z'));
 let saved=JSON.parse(db.prepare('SELECT data FROM portfolio_daily_snapshots').get()!.data as string);
 assert.equal(saved.holdingDates[0].valuationAsOf,null);assert.equal(saved.holdingDates[0].carriedForward,null);assert.equal(saved.holdingDates[0].sourceRetrievedAt,'2026-10-10T10:00:00Z');
 db.prepare('DELETE FROM zerodha_snapshots').run();db.prepare('INSERT INTO properties VALUES(?,?,?,?)').run('one','p',JSON.stringify({id:'p',name:'Home',estimatedValue:'100',ownershipPercent:'100',valuationDate:'2026-10-01',purchaseCost:null,updatedAt:0}),0);
 await history.scheduledPortfolioSnapshots(env,new Date('2026-10-10T12:15:00Z'));
 saved=JSON.parse(db.prepare('SELECT data FROM portfolio_daily_snapshots').get()!.data as string);
 assert.equal(saved.portfolio.connections.some((c:any)=>c.id==='zerodha'),false);
});
