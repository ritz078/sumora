import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { app } from '../src/index';

test('health endpoint identifies the service', async () => {
  const response = await app.request('/health');
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: 'ok', service: 'sumora-api' });
});

for (const scenario of ['complete', 'partial', 'stale', 'empty', 'unavailable']) {
  test(`${scenario} response preserves the existing Swift snapshot contract`, async () => {
    const response = await app.request(`/v1/demo/portfolio?scenario=${scenario}`);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    const fixture = JSON.parse(await readFile(new URL(`../../ios/Sumora/Resources/Fixtures/${scenario}.json`, import.meta.url), 'utf8'));
    assert.deepEqual(await response.json(), fixture);
  });
}

test('omitted scenario returns complete sample with decimal strings', async () => {
  const response = await app.request('/v1/demo/portfolio');
  assert.equal(response.status, 200);
  assert.equal((await response.json()).value, '4250000');
});

test('unknown scenario is a structured client error', async () => {
  const response = await app.request('/v1/demo/portfolio?scenario=wrong');
  assert.equal(response.status, 400);
  assert.equal((await response.json()).error.code, 'INVALID_SCENARIO');
});

test('failure scenario returns HTTP 503 instead of fake successful data', async () => {
  const response = await app.request('/v1/demo/portfolio?scenario=failure');
  assert.equal(response.status, 503);
  assert.equal((await response.json()).error.code, 'DEMO_UNAVAILABLE');
});

test('unknown route is a JSON 404', async () => {
  const response = await app.request('/v1/portfolio');
  assert.equal(response.status, 404);
  assert.equal((await response.json()).error.code, 'NOT_FOUND');
});

test('retired contract-note and trade endpoints are no longer exposed', async () => {
 for(const [path,method] of [['/v1/gmail/decryption','PUT'],['/v1/trades','GET'],['/v1/trades/imports','POST']]) {
  const response=await app.request(path,{method});
  assert.equal(response.status,404,path);
  assert.equal((await response.json()).error.code,'NOT_FOUND');
 }
});
