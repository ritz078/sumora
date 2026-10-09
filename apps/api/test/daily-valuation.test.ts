import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseAMFI, parseNSE } from '../src/daily-prices';
import { revalue } from '../src/portfolio-valuation';
import { zerodhaSnapshot } from '../src/zerodha-portfolio';

const nse = 'TradDt,ISIN,SctySrs,ClsPric\n2026-10-08,INE000A01010,EQ,125.50\n2026-10-08,INE000A01010,BE,125.50';
const amfi = 'Scheme Code;ISIN Div Payout/ ISIN Growth;ISIN Div Reinvestment;Scheme Name;Plan;Option;Net Asset Value;Date\n123;INF000A01010;-;Fund;Direct;Growth;20.1234;08-Oct-2026';
const date = '2026-10-08';
const response = (data: unknown[]) => JSON.stringify({ status: 'success', data });
export function sample() {
  return zerodhaSnapshot(response([{ tradingsymbol: 'STOCK', isin: 'INE000A01010', exchange: 'NSE', quantity: 2, average_price: 100, last_price: 110 }]), response([{ tradingsymbol: 'INF000A01010', fund: 'Fund', quantity: 1.2345, average_price: 10, last_price: 15, last_price_date: '2026-10-07' }]), new Date('2026-10-07T12:00:00Z'));
}
test('official feeds parse exact ISINs, current AMFI columns and matching duplicate NSE series', () => {
  assert.equal(parseNSE(nse, date).length, 1);
  assert.equal(parseNSE(nse, date)[0].price, '125.5');
  assert.equal(parseAMFI(amfi, date)[0].price, '20.1234');
  assert.equal(parseAMFI(amfi.replace(';Plan;Option', '').replace(';Direct;Growth', ''), date).length, 1);
});
test('invalid, future and ambiguous quotes are excluded', () => {
  assert.equal(parseNSE(nse.replaceAll('125.50', '-1'), date).length, 0);
  assert.equal(parseNSE(nse, '2026-10-07').length, 0);
  assert.equal(parseNSE(nse.replace('BE,125.50', 'BE,126'), date).length, 0);
  assert.equal(parseAMFI(amfi.replace('20.1234', 'N.A.'), date).length, 0);
  assert.equal(parseAMFI(amfi.replace('08-Oct', '32-Oct'), '2026-11-08').length, 0);
});
test('daily valuation preserves quantities and sync date, recomputes decimal totals and allocation', () => {
  const original = sample();
  const result = revalue(original, [...parseNSE(nse, date), ...parseAMFI(amfi, date)]);
  assert.equal(result.holdings[1].quantity, '1.2345');
  assert.equal(result.holdingsSyncAt, original.holdingsSyncAt);
  assert.equal(result.capturedAt, '2026-10-08T18:29:00Z');
  assert.equal(result.value, '275.8423373');
  assert.equal(result.gain, '63.4973373');
  assert.equal(result.allocation[0].value, '251');
  assert.equal(original.holdings[0].quote, '110');
  assert.match(result.holdings[0].source, /NSE/);
});
test('missing prices retain last good data and older closes cannot replace newer broker quotes', () => {
  const original = sample();
  assert.deepEqual(revalue(original, []), original);
  const newer = { ...original, capturedAt: '2026-10-09T06:00:00Z' };
  assert.equal(revalue(newer, parseNSE(nse, date)).holdings[0].quote, '110');
  const onlyStock = revalue(original, parseNSE(nse, date));
  assert.equal(onlyStock.holdings[1].quote, '15');
});

test('feed parsing can select only held ISINs without accepting partial identifier matches', () => {
  assert.equal(parseNSE(nse, date, new Set(['INE000A01010'])).length, 1);
  assert.equal(parseNSE(nse, date, new Set(['INE000A0101'])).length, 0);
  assert.equal(parseAMFI(amfi, date, new Set(['INF000A01010'])).length, 1);
  assert.equal(parseAMFI(amfi, date, new Set()).length, 0);
});

test('a fresh quantity sync with no broker price still uses the last available independent close', () => {
  const original = sample(); original.capturedAt = '2026-10-09T06:00:00Z';
  original.holdings[0].quote = original.holdings[0].value = null;
  assert.equal(revalue(original, parseNSE(nse, date)).holdings[0].value, '251');
});
