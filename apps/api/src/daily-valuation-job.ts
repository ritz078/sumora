import {hdfcPortfolio} from './hdfc';
import { goldPortfolio } from './gold-portfolio';
import { dailyPerformance } from './daily-performance';
import { unzipSync, strFromU8 } from 'fflate';
import { istDate, parseAMFI, parseNSE, type MarketPrice } from './daily-prices';
import { holdingISIN, revalue, type Portfolio } from './portfolio-valuation';
import type { KiteEnvironment } from './zerodha';

type Environment = Pick<KiteEnvironment, 'DB'>;
type Result = { updated: number; failed: string[]; skipped?: boolean };
const MAX_FEED = 8 * 1024 * 1024;
async function download(fetcher: typeof fetch, url: string) {
  const response = await fetcher(url, { signal: AbortSignal.timeout(15000), redirect: 'manual', headers: { 'User-Agent': 'Mozilla/5.0 (compatible; Sumora/1.0)' } });
  if (!response.ok) { await response.body?.cancel(); return { status: response.status, bytes: null }; }
  if (Number(response.headers.get('content-length')) > MAX_FEED) { await response.body?.cancel(); throw new Error('Price feed too large.'); }
  if (!response.body) throw new Error('Empty price feed.');
  const reader = response.body.getReader(); const chunks: Uint8Array[] = []; let length = 0;
  try {
    while (true) {
      const { done, value } = await reader.read(); if (done) break;
      length += value.byteLength; if (length > MAX_FEED) throw new Error('Price feed too large.');
      chunks.push(value);
    }
  } finally { await reader.cancel(); }
  const bytes = new Uint8Array(length); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  return { status: response.status, bytes };
}
function nseCSV(bytes: Uint8Array) {
  let expanded = 0;
  const files = unzipSync(bytes, { filter(file) {
    if (!file.name.toLowerCase().endsWith('.csv')) return false;
    expanded += file.originalSize;
    if (expanded > 32 * 1024 * 1024) throw new Error('Expanded price feed too large.');
    return true;
  } });
  const csvs = Object.values(files);
  if (csvs.length !== 1) throw new Error('Expected one NSE price CSV.');
  return strFromU8(csvs[0]);
}
async function savedPrices(env: Environment): Promise<MarketPrice[]> {
  const row = await env.DB.prepare("SELECT json_group_array(json_object('isin', isin, 'kind', kind, 'price', price, 'date', date, 'source', source)) AS prices FROM market_prices").first<{ prices: string }>();
  return JSON.parse(row?.prices ?? '[]');
}
async function captureBaselines(env: Environment, at: Date) {
  const day = istDate(at);
  // Retry can fill a missing/delayed prior close, but same-date corrections and
  // intraday quote updates cannot move the day's reference price.
  await env.DB.prepare(`INSERT INTO daily_price_baselines (day, kind, isin, price, price_date, source)
    SELECT ?, kind, isin, price, date, source FROM market_prices WHERE date < ?
    ON CONFLICT(day, kind, isin) DO UPDATE SET price = excluded.price, price_date = excluded.price_date, source = excluded.source
    WHERE excluded.price_date > daily_price_baselines.price_date`).bind(day, day).run();
}
export async function valuedSnapshot(env: Environment, snapshot: Portfolio, at = new Date(), owner?: string) {
  if (owner) { snapshot = await goldPortfolio(env, snapshot, owner); snapshot = await hdfcPortfolio(env, snapshot, owner); }
  await captureBaselines(env, at);
  const row = await env.DB.prepare("SELECT json_group_array(json_object('isin', isin, 'kind', kind, 'price', price, 'date', price_date, 'source', source)) AS prices FROM daily_price_baselines WHERE day = ?").bind(istDate(at)).first<{ prices: string }>();
  return dailyPerformance(revalue(snapshot, await savedPrices(env)), JSON.parse(row?.prices ?? '[]'), istDate(at));
}
export async function refreshDailyPrices(env: Environment, fetcher: typeof fetch = fetch, at = new Date()): Promise<Result> {
  const lease = at.getTime() + 300000;
  const locked = await env.DB.prepare('UPDATE daily_price_job SET running_until = ? WHERE id = 1 AND running_until <= ? RETURNING id').bind(lease, at.getTime()).first<{ id: number }>();
  if (!locked) return { updated: 0, failed: [], skipped: true };
  const result: Result = { updated: 0, failed: [] };
  try {
    const rows = await env.DB.prepare('SELECT json_group_array(json(snapshot)) AS snapshots FROM zerodha_snapshots').first<{ snapshots: string }>();
    const portfolios = JSON.parse(rows?.snapshots ?? '[]') as Portfolio[];
    const wanted = new Set(portfolios.flatMap(p => p.holdings.flatMap(h => { const isin = holdingISIN(h); return isin ? [`${h.assetClass}:${isin}`] : []; })));
    // Keep latest prices bounded to currently held instruments.
    await env.DB.prepare("DELETE FROM market_prices WHERE kind != 'gold' AND kind || ':' || isin NOT IN (SELECT value FROM json_each(?))").bind(JSON.stringify([...wanted])).run();
    // Both midnight and morning runs target the previous completed Indian calendar day.
    const maxDate = istDate(new Date(at.getTime() - 86400000));
    for (const kind of ['indianEquity', 'mutualFund'] as const) {
      if (![...wanted].some(key => key.startsWith(`${kind}:`))) continue;
      try {
        let prices: MarketPrice[] | null = null;
        if (kind === 'mutualFund') {
          const feed = await download(fetcher, 'https://portal.amfiindia.com/spages/NAVAll.txt');
          if (feed.bytes) prices = parseAMFI(strFromU8(feed.bytes), maxDate, new Set([...wanted].filter(k => k.startsWith('mutualFund:')).map(k => k.slice(11))));
        } else {
          for (let days = 0; days < 7; days++) {
            const date = new Date(`${maxDate}T00:00:00Z`); date.setUTCDate(date.getUTCDate() - days);
            if (date.getUTCDay() === 0 || date.getUTCDay() === 6) continue;
            const dateText = date.toISOString().slice(0,10);
            const feed = await download(fetcher, `https://nsearchives.nseindia.com/content/cm/BhavCopy_NSE_CM_0_0_0_${dateText.replaceAll('-', '')}_F_0000.csv.zip`);
            if (feed.bytes) { prices = parseNSE(nseCSV(feed.bytes), dateText, new Set([...wanted].filter(k => k.startsWith('indianEquity:')).map(k => k.slice(13)))).filter(p => p.date === dateText); break; }
            if (feed.status !== 404) break;
          }
        }
        if (!prices?.length) throw new Error('No valid closing prices.');
        // One D1 statement per feed keeps even large portfolios below the free
        // Worker's 50-query invocation limit. Upserts cannot regress quote dates.
        await env.DB.prepare(`INSERT INTO market_prices (kind, isin, price, date, source, updated_at)
          SELECT json_extract(value, '$.kind'), json_extract(value, '$.isin'), json_extract(value, '$.price'), json_extract(value, '$.date'), json_extract(value, '$.source'), ?
          FROM json_each(?) WHERE true
          ON CONFLICT(kind, isin) DO UPDATE SET price = excluded.price, date = excluded.date, source = excluded.source, updated_at = excluded.updated_at WHERE excluded.date >= market_prices.date`)
          .bind(at.getTime(), JSON.stringify(prices)).run();
        result.updated += prices.length;
      } catch { result.failed.push(kind); }
    }
    await captureBaselines(env, at);
    // A short retention window supports diagnostics without an unbounded history.
    await env.DB.prepare('DELETE FROM daily_price_baselines WHERE day < ?').bind(istDate(new Date(at.getTime() - 30 * 86400000))).run();
    return result;
  } finally {
    await env.DB.prepare('UPDATE daily_price_job SET running_until = 0, last_run_at = ?, result = ? WHERE id = 1 AND running_until = ?').bind(at.getTime(), JSON.stringify(result), lease).run();
  }
}
