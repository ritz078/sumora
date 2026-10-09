import { test } from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { zipSync, strToU8 } from 'fflate';
import { refreshDailyPrices, valuedSnapshot } from '../src/daily-valuation-job';
import type { Statement } from '../src/zerodha';
import { zerodhaSnapshot } from '../src/zerodha-portfolio';
function setup() {
  const db = new DatabaseSync(':memory:');
  for (const name of ['0001_zerodha.sql','0007_daily_prices.sql','0008_daily_baselines.sql']) db.exec(readFileSync(new URL(`../migrations/${name}`, import.meta.url), 'utf8'));
  const env = { DB: { prepare(sql: string): Statement { let values: any[] = []; return {
    bind(...args) { values = args; return this; }, async first<T>() { return db.prepare(sql).get(...values) as T ?? null; }, async run() { return db.prepare(sql).run(...values); }
  }; } } };
  const snapshot = zerodhaSnapshot(JSON.stringify({ status: 'success', data: [{ tradingsymbol: 'STOCK', isin: 'INE000A01010', exchange: 'NSE', quantity: 2, average_price: 100, last_price: 110 }] }), '{"status":"success","data":[]}', new Date('2026-10-07T12:00:00Z'));
  db.prepare('INSERT INTO zerodha_snapshots VALUES (?, ?, ?)').run('owner', JSON.stringify(snapshot), 0);
  return { db, env, snapshot };
}
const at = new Date('2026-10-09T00:30:00Z');
const archive = zipSync({ 'BhavCopy.csv': strToU8('TradDt,ISIN,SctySrs,ClsPric\n2026-10-08,INE000A01010,EQ,125.50\n2026-10-08,INE999A01010,EQ,999') });
test('scheduled refresh stores only held ISINs and independently values saved quantities', async () => {
  const { db, env, snapshot } = setup();
  const fetcher: typeof fetch = async (_url, options) => { assert.equal(options?.redirect, 'manual'); return new Response(archive); };
  const result = await refreshDailyPrices(env, fetcher, at);
  assert.equal(result.updated, 1);
  assert.equal(db.prepare('SELECT count(*) AS n FROM market_prices').get()?.n, 1);
  assert.equal((await valuedSnapshot(env, snapshot)).value, '251');
  assert.equal(JSON.parse(db.prepare('SELECT snapshot FROM zerodha_snapshots').get()?.snapshot as string).value, '220');
  await refreshDailyPrices(env, fetcher, at);
  assert.equal(db.prepare('SELECT count(*) AS n FROM market_prices').get()?.n, 1);
});
test('failed feeds and holidays retain last good quotes, report failures, and permit retry', async () => {
  const { db, env, snapshot } = setup();
  await refreshDailyPrices(env, async () => new Response(archive), at);
  const calls: string[] = [];
  const result = await refreshDailyPrices(env, async url => { calls.push(String(url)); return new Response('', { status: 404 }); }, new Date('2026-10-12T00:30:00Z'));
  assert.equal(result.failed.length, 1);
  assert.ok(calls.every(url => !url.includes('_20261011_') && !url.includes('_20261010_')));
  assert.equal((await valuedSnapshot(env, snapshot)).value, '251');
  assert.equal(db.prepare('SELECT running_until FROM daily_price_job').get()?.running_until, 0);
});
test('fund update succeeds when stocks fail, older NAV cannot regress, empty portfolios make no requests', async () => {
  const { db, env, snapshot } = setup();
  const funds = zerodhaSnapshot('{"status":"success","data":[]}', '{"status":"success","data":[{"tradingsymbol":"INF000A01010","fund":"Fund","quantity":1.5,"average_price":10,"last_price":11,"last_price_date":"2026-10-07"}]}', new Date('2026-10-07T12:00:00Z'));
  db.prepare('INSERT INTO zerodha_snapshots VALUES (?, ?, ?)').run('other', JSON.stringify(funds), 0);
  const nav = 'Scheme Code;ISIN Div Payout/ ISIN Growth;ISIN Div Reinvestment;Scheme Name;Net Asset Value;Date\n1;INF000A01010;-;Fund;20;08-Oct-2026';
  const fetcher: typeof fetch = async url => String(url).includes('amfi') ? new Response(nav) : new Response('', { status: 403 });
  assert.equal((await refreshDailyPrices(env, fetcher, at)).updated, 1);
  assert.equal((await valuedSnapshot(env, funds)).value, '30');
  assert.equal((await valuedSnapshot(env, snapshot)).value, '220');
  await refreshDailyPrices(env, async () => new Response(nav.replace(';20;08-', ';19;07-')), at);
  assert.equal((await valuedSnapshot(env, funds)).value, '30');
  db.prepare('DELETE FROM zerodha_snapshots').run();
  await refreshDailyPrices(env, async () => { throw new Error('Should not fetch'); }, at);
  assert.equal(db.prepare('SELECT count(*) AS n FROM market_prices').get()?.n, 0);
});
test('overlapping cron invocation cannot fetch twice', async () => {
  const { db, env } = setup();
  db.prepare('UPDATE daily_price_job SET running_until = ?').run(at.getTime() + 60000);
  const result = await refreshDailyPrices(env, async () => { throw new Error('Should not fetch'); }, at);
  assert.equal(result.skipped, true);
});

test('large portfolios do not exhaust the free Worker D1 query budget', async () => {
  const { env, db, snapshot } = setup();
  const holdings = Array.from({ length: 80 }, (_, i) => ({ ...snapshot.holdings[0], id: `zerodha:eq:INE${String(i).padStart(8, '0')}0` }));
  db.prepare('UPDATE zerodha_snapshots SET snapshot = ?').run(JSON.stringify({ ...snapshot, holdings }));
  const zip = zipSync({ 'prices.csv': strToU8('TradDt,ISIN,ClsPric\n' + holdings.map(h => `2026-10-08,${h.id.slice(11)},125`).join('\n')) });
  let queries = 0;
  const counted = { DB: { prepare(sql: string) { queries++; if (queries > 50) throw new Error('D1 query limit'); return env.DB.prepare(sql); } } };
  const result = await refreshDailyPrices(counted, async () => new Response(zip), at);
  assert.equal(result.updated, 80);
  assert.ok(queries < 10);
});

// These exercise persisted prices through the portfolio boundary, including restarts/retries.
test('daily baseline survives repeated refreshes and measures price movement on current quantities', async () => {
  const { db, env, snapshot } = setup();
  await refreshDailyPrices(env, async () => new Response(archive), at);
  const live = { ...snapshot, capturedAt: '2026-10-09T06:00:00Z', holdings: [{ ...snapshot.holdings[0], quantity: '3', quote: '130', value: '390' }] };
  let result = await valuedSnapshot(env, live, new Date('2026-10-09T06:00:00Z'));
  assert.equal(result.dailyGain, '13.5');
  assert.equal(result.dailyBaselineDate, '2026-10-09');
  assert.equal(result.holdings[0].dailyBaselinePrice, '125.5');
  // Same-date publication corrections must not move an established reference.
  db.prepare('UPDATE market_prices SET price = ?').run('126');
  assert.equal((await valuedSnapshot(env, live, new Date('2026-10-09T06:00:00Z'))).dailyGain, '13.5');
  // A retry carrying an older close must not reset the baseline.
  const older = zipSync({ 'prices.csv': strToU8('TradDt,ISIN,ClsPric\n2026-10-07,INE000A01010,120') });
  await refreshDailyPrices(env, async () => new Response(older), at);
  result = await valuedSnapshot(env, live, new Date('2026-10-09T06:00:00Z'));
  assert.equal(result.dailyGain, '13.5');
  assert.equal(db.prepare('SELECT count(*) AS n FROM daily_price_baselines').get()?.n, 1);
});
test('IST midnight rolls the baseline forward and failed feeds retain the last trading close', async () => {
  const { env, snapshot } = setup();
  await refreshDailyPrices(env, async () => new Response(archive), at);
  const next = zipSync({ 'prices.csv': strToU8('TradDt,ISIN,ClsPric\n2026-10-09,INE000A01010,130') });
  const midnight = new Date('2026-10-09T18:30:00Z');
  await refreshDailyPrices(env, async () => new Response(next), midnight);
  assert.equal((await valuedSnapshot(env, snapshot, midnight)).dailyGain, '0');
  const monday = new Date('2026-10-12T00:30:00Z');
  await refreshDailyPrices(env, async () => new Response('', { status: 404 }), monday);
  const result = await valuedSnapshot(env, snapshot, monday);
  assert.equal(result.dailyGain, '0');
  assert.equal(result.dailyBaselineDate, '2026-10-12');
  assert.equal(result.holdings[0].dailyBaselinePriceDate, '2026-10-09');
});
test('missing baseline or stale broker price never fabricates a daily return', async () => {
  const { env, snapshot } = setup();
  assert.equal((await valuedSnapshot(env, snapshot, at)).dailyGain, null);
  await refreshDailyPrices(env, async () => new Response(archive), at);
  const unmatched = { ...snapshot, holdings: [{ ...snapshot.holdings[0], id: 'zerodha:eq:INE999A01010' }] };
  assert.equal((await valuedSnapshot(env, unmatched, at)).dailyGain, null);
});

test('daily return preserves decimal losses for funds and does not reuse yesterday’s gain', async () => {
  const { db, env } = setup();
  const funds = zerodhaSnapshot('{"status":"success","data":[]}', '{"status":"success","data":[{"tradingsymbol":"INF000A01010","fund":"Fund","quantity":1.5,"average_price":10,"last_price":19.5,"last_price_date":"2026-10-09"}]}', new Date('2026-10-09T12:00:00Z'));
  db.prepare('INSERT INTO market_prices VALUES (?, ?, ?, ?, ?, ?)').run('mutualFund','INF000A01010','20','2026-10-08','AMFI daily NAV',0);
  const result = await valuedSnapshot(env, funds, new Date('2026-10-09T12:00:00Z'));
  assert.equal(result.dailyGain, '-0.75');
  assert.equal(result.dailyGainPercent, '-2.5');
  assert.equal((await valuedSnapshot(env, funds, new Date('2026-10-10T12:00:00Z'))).dailyGain, null);
});
