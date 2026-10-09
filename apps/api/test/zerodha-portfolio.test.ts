import { test } from 'node:test';
import assert from 'node:assert/strict';
import { zerodhaSnapshot } from '../src/zerodha-portfolio';

const at = new Date('2026-10-06T06:00:00Z');
test('equities and funds use decimal arithmetic and existing snapshot contract', () => {
  const equity = '{"status":"success","data":[{"tradingsymbol":"RELIANCE","exchange":"NSE","isin":"INE001","quantity":3,"t1_quantity":1,"used_quantity":1,"average_price":100.01,"last_price":110.02}]}';
  const funds = '{"status":"success","data":[{"fund":"Sample Fund","tradingsymbol":"INF001","folio":"123","quantity":1.23456789,"average_price":78.43,"last_price":84.86,"last_price_date":"2026-10-05"}]}';
  const snapshot: any = zerodhaSnapshot(equity, funds, at);
  assert.equal(snapshot.holdings[0].quantity, '3');
  assert.equal(snapshot.holdings[0].invested, '300.03');
  assert.equal(snapshot.holdings[0].value, '330.06');
  assert.equal(snapshot.holdings[1].value, '104.7654311454');
  assert.equal(snapshot.holdings[1].quoteAt, '2026-10-04T18:30:00Z');
  assert.equal(snapshot.capturedAt, '2026-10-06T06:00:00Z');
  assert.equal(snapshot.value, '434.8254311454');
  assert.deepEqual(snapshot.history, []);
  assert.equal(snapshot.connections.length, 1);
});

test('unavailable prices stay null and excluded from covered cost', () => {
  const snapshot: any = zerodhaSnapshot('{"status":"success","data":[{"tradingsymbol":"X","exchange":"NSE","quantity":2,"average_price":5,"last_price":0}]}', '{"status":"success","data":[]}', at);
  assert.equal(snapshot.coverage, 'unavailable');
  assert.equal(snapshot.value, null);
  assert.equal(snapshot.holdings[0].gain, null);
  assert.equal(snapshot.invested, '10');
  assert.equal(snapshot.coveredInvested, '0');
});

test('malformed upstream data fails rather than publishing empty holdings', () => {
  assert.throws(() => zerodhaSnapshot('{"status":"error","data":[]}', '{}', at));
});

test('duplicate exchanges for the same ISIN are not silently added together', () => {
  const data = '{"status":"success","data":[{"tradingsymbol":"X","exchange":"NSE","isin":"INE001","quantity":2,"average_price":5,"last_price":6},{"tradingsymbol":"X","exchange":"BSE","isin":"INE001","quantity":2,"average_price":5,"last_price":6}]}';
  assert.throws(() => zerodhaSnapshot(data, '{"status":"success","data":[]}', at));
});
