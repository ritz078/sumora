import { test } from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { zerodhaRoutes, type KiteEnvironment, type Statement } from '../src/zerodha';

function setup(owner = 'AB1234') {
  const db = new DatabaseSync(':memory:');
  db.exec(readFileSync(new URL('../migrations/0001_zerodha.sql', import.meta.url), 'utf8'));
  db.exec(readFileSync(new URL('../migrations/0007_daily_prices.sql', import.meta.url), 'utf8'));
  db.exec(readFileSync(new URL('../migrations/0008_daily_baselines.sql', import.meta.url), 'utf8'));
  db.exec(readFileSync(new URL('../migrations/0009_gold.sql', import.meta.url), 'utf8'));
  db.exec(readFileSync(new URL('../migrations/0010_gullak_silver.sql', import.meta.url), 'utf8'));
  const env: KiteEnvironment = {
    DB: { prepare(sql): Statement {
      let values: any[] = [];
      return { bind(...args) { values = args; return this; },
        async first<T>() { return (db.prepare(sql).get(...values) as T) ?? null; },
        async run() { return db.prepare(sql).run(...values); } };
    } },
    KITE_API_KEY: 'key', KITE_API_SECRET: 'secret',
    KITE_ENCRYPTION_KEY: Buffer.alloc(32, 1).toString('base64'),
  };
  const calls: string[] = [];
  const upstream: typeof fetch = async (url) => {
    calls.push(String(url));
    if (String(url).endsWith('/session/token')) return Response.json({ status: 'success', data: { user_id: owner, access_token: 'broker-secret-token' } });
    return Response.json({ status: 'success', data: [] });
  };
  const app = zerodhaRoutes(upstream, () => Date.parse('2026-10-06T06:00:00Z'));
  const post = (path: string, body: unknown) => app.request(path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }, env);
  return { app, env, db, post, calls, setIdentity(value: string) { owner = value; } };
}

async function sha(text: string) { return Buffer.from(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text))).toString('hex'); }

test('personal data is unavailable without an app session', async () => {
  const { app, env } = setup();
  assert.equal((await app.request('/portfolio', {}, env)).status, 401);
});

test('login challenge rejects malformed input and missing configuration', async () => {
  const { post, env } = setup();
  assert.equal((await post('/start', { challenge: 'short' })).status, 400);
  env.KITE_API_SECRET = '';
  assert.equal((await post('/start', { challenge: 'a'.repeat(64) })).status, 503);
});

test('verified Kite identity can claim a single-use login with verifier; broker token stays encrypted', async () => {
  const { post, app, env, db } = setup();
  const verifier = 'v'.repeat(64);
  const start = await post('/start', { challenge: await sha(verifier) });
  assert.equal(start.status, 200);
  const { state, loginURL } = await start.json();
  assert.ok(loginURL.startsWith('https://kite.zerodha.com/connect/login?'));
  const callback = await app.request(`/callback?state=${state}&status=success&request_token=kite-request`, {}, env);
  assert.equal(callback.status, 302);
  const redirect = new URL(callback.headers.get('location')!);
  const code = redirect.searchParams.get('code');
  assert.ok(code);
  assert.equal((await post('/claim', { code, verifier: 'wrong'.repeat(16) })).status, 401);
  const result = await post('/claim', { code, verifier });
  assert.equal(result.status, 200);
  const { sessionToken } = await result.json();
  assert.ok(sessionToken.length >= 40);
  assert.ok(!JSON.stringify(db.prepare('SELECT * FROM zerodha_sessions').all()).includes('broker-secret-token'));
  assert.equal((await post('/claim', { code, verifier })).status, 401);
  const response = await app.request('/portfolio', { headers: { Authorization: `Bearer ${sessionToken}` } }, env);
  assert.equal(response.status, 200);
  assert.equal((await response.json()).value, '0');
});

test('identity comes from Kite login without owner configuration or client-supplied identity', async () => {
  const { post, app, env, db } = setup('OTHER1');
  const verifier = 'v'.repeat(64);
  const { state } = await (await post('/start', { challenge: await sha(verifier), userID: 'SPOOF1' })).json();
  const response = await app.request(`/callback?state=${state}&status=success&request_token=token&user_id=SPOOF1`, {}, env);
  const code = new URL(response.headers.get('location')!).searchParams.get('code');
  const claim = await post('/claim', { code, verifier, userID: 'SPOOF1' });
  assert.equal(claim.status, 200);
  assert.equal((await claim.json()).userID, 'OTHER1');
  assert.equal(db.prepare('SELECT owner_id FROM zerodha_sessions').get()?.owner_id, 'OTHER1');
});

test('missing verified Kite identity cannot create a session', async () => {
  const { post, app, env } = setup('');
  const { state } = await (await post('/start', { challenge: 'a'.repeat(64) })).json();
  const response = await app.request(`/callback?state=${state}&status=success&request_token=token`, {}, env);
  assert.equal(new URL(response.headers.get('location')!).searchParams.get('error'), 'LOGIN_FAILED');
});

test('invalid callback state never reaches token exchange', async () => {
  const { app, env, calls } = setup();
  await app.request('/callback?state=unknown&status=success&request_token=token', {}, env);
  assert.equal(calls.length, 0);
});

async function login(context: ReturnType<typeof setup>) {
  const verifier = 'v'.repeat(64);
  const { state } = await (await context.post('/start', { challenge: await sha(verifier) })).json();
  const callback = await context.app.request(`/callback?state=${state}&status=success&request_token=request`, {}, context.env);
  const code = new URL(callback.headers.get('location')!).searchParams.get('code');
  return (await (await context.post('/claim', { code, verifier })).json()).sessionToken as string;
}

test('expired broker session keeps last import and requires reconnection', async () => {
  const context = setup();
  const token = await login(context);
  const options = { headers: { Authorization: `Bearer ${token}` } };
  assert.equal((await context.app.request('/portfolio', options, context.env)).status, 200);
  context.db.prepare('UPDATE zerodha_sessions SET provider_expires_at = 0').run();
  const stale = await context.app.request('/portfolio', options, context.env);
  assert.equal(stale.status, 200);
  assert.equal((await stale.json()).connections[0].status, 'attention');
});

test('disconnect removes sessions and persisted financial snapshot', async () => {
  const context = setup();
  const token = await login(context);
  const headers = { Authorization: `Bearer ${token}` };
  await context.app.request('/portfolio', { headers }, context.env);
  assert.equal((await context.app.request('/connection', { method: 'DELETE', headers }, context.env)).status, 200);
  assert.equal((await context.app.request('/portfolio', { headers }, context.env)).status, 401);
  assert.equal(context.db.prepare('SELECT count(*) AS count FROM zerodha_snapshots').get()?.count, 0);
  assert.ok(context.calls.some((url) => url.includes('/session/token?api_key=key&access_token=broker-secret-token')));
});

test('expired login and expired Sumora sessions cannot be used', async () => {
  const context = setup();
  const { state } = await (await context.post('/start', { challenge: 'a'.repeat(64) })).json();
  context.db.prepare('UPDATE zerodha_attempts SET expires_at = 0').run();
  const callback = await context.app.request(`/callback?state=${state}&status=success&request_token=request`, {}, context.env);
  assert.equal(new URL(callback.headers.get('location')!).searchParams.get('error'), 'LOGIN_EXPIRED');
  const token = await login(context);
  context.db.prepare('UPDATE zerodha_sessions SET expires_at = 0').run();
  assert.equal((await context.app.request('/portfolio', { headers: { Authorization: `Bearer ${token}` } }, context.env)).status, 401);
});

test('sessions isolate cached portfolios and disconnect by verified account', async () => {
  const context = setup();
  const firstToken = await login(context);
  const firstHeaders = { Authorization: `Bearer ${firstToken}` };
  const first = await context.app.request('/portfolio', { headers: firstHeaders }, context.env);
  const snapshot = await first.json();
  context.setIdentity('OTHER1');
  const secondToken = await login(context);
  const secondHeaders = { Authorization: `Bearer ${secondToken}` };
  snapshot.value = '777';
  context.db.prepare('INSERT INTO zerodha_snapshots (owner_id, snapshot, synced_at) VALUES (?, ?, ?)').run('OTHER1', JSON.stringify(snapshot), Date.parse('2026-10-06T06:00:00Z'));
  assert.equal((await (await context.app.request('/portfolio', { headers: firstHeaders }, context.env)).json()).value, '0');
  assert.equal((await (await context.app.request('/portfolio', { headers: secondHeaders }, context.env)).json()).value, '777');
  assert.equal((await context.app.request('/connection', { method: 'DELETE', headers: firstHeaders }, context.env)).status, 200);
  assert.equal((await context.app.request('/portfolio', { headers: firstHeaders }, context.env)).status, 401);
  assert.equal((await (await context.app.request('/portfolio', { headers: secondHeaders }, context.env)).json()).value, '777');
});


test('expired Kite connection receives independent closes without changing recorded quantities', async () => {
  const context = setup();
  const token = await login(context);
  const options = { headers: { Authorization: `Bearer ${token}` } };
  const snapshot = await (await context.app.request('/portfolio', options, context.env)).json();
  snapshot.capturedAt = snapshot.holdingsSyncAt = '2026-10-05T06:00:00Z';
  snapshot.holdings = [{ id: 'zerodha:eq:INE000A01010', symbol: 'STOCK', assetClass: 'indianEquity', quantity: '2', invested: '200', value: '220', quote: '110', quoteAt: null }];
  context.db.prepare('UPDATE zerodha_snapshots SET snapshot = ?').run(JSON.stringify(snapshot));
  context.db.prepare('UPDATE zerodha_sessions SET provider_expires_at = 0').run();
  context.db.prepare('INSERT INTO market_prices VALUES (?, ?, ?, ?, ?, ?)').run('indianEquity','INE000A01010','125.5','2026-10-05','NSE daily close',0);
  const response = await context.app.request('/portfolio', options, context.env);
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(result.value, '251');
  assert.equal(result.holdings[0].quantity, '2');
  assert.equal(result.holdingsSyncAt, snapshot.holdingsSyncAt);
  assert.equal(result.connections[0].status, 'attention');
});
