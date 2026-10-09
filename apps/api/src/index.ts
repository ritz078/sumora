import { Hono } from 'hono';
import { refreshDailyPrices } from './daily-valuation-job';
import { gmailRoutes, type GmailEnvironment } from './gmail';
import { zerodhaRoutes } from './zerodha';
import complete from '../../ios/Sumora/Resources/Fixtures/complete.json';
import partial from '../../ios/Sumora/Resources/Fixtures/partial.json';
import stale from '../../ios/Sumora/Resources/Fixtures/stale.json';
import empty from '../../ios/Sumora/Resources/Fixtures/empty.json';
import unavailable from '../../ios/Sumora/Resources/Fixtures/unavailable.json';

export const app = new Hono<{ Bindings: GmailEnvironment }>();
const samples = { complete, partial, stale, empty, unavailable };

app.use('*', async (c, next) => {
  c.header('Cache-Control', 'no-store');
  await next();
});
app.get('/health', (c) => c.json({ status: 'ok', service: 'sumora-api' }));
app.route('/v1/zerodha', zerodhaRoutes());
app.route('/v1/gmail', gmailRoutes());
app.get('/v1/demo/portfolio', (c) => {
  const scenario = c.req.query('scenario') ?? 'complete';
  if (scenario === 'failure') {
    return c.json({ error: { code: 'DEMO_UNAVAILABLE', message: 'Sample refresh is temporarily unavailable.' } }, 503);
  }
  if (!Object.hasOwn(samples, scenario)) {
    return c.json({ error: { code: 'INVALID_SCENARIO', message: 'Choose a supported sample scenario.' } }, 400);
  }
  return c.json(samples[scenario as keyof typeof samples]);
});
app.notFound((c) => c.json({ error: { code: 'NOT_FOUND', message: 'Endpoint not found.' } }, 404));
app.onError((_error, c) => c.json({ error: { code: 'INTERNAL_ERROR', message: 'Unable to load the sample portfolio.' } }, 500));
export default {
  fetch: app.fetch,
  async scheduled(_event: unknown, env: GmailEnvironment) {
    const result = await refreshDailyPrices(env);
    console.log(JSON.stringify({ event: 'daily-prices', ...result }));
  },
};
