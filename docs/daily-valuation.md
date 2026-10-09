# Independent daily valuation

Recorded Zerodha equity shares and Coin fund units are repriced using NSE UDiFF closing prices and AMFI NAVAll. Neither feed requires an API key. Exact ISIN matching is mandatory; unsupported/unmatched holdings retain their last reported price. Quantities still require a broker sync after purchases, sales or corporate actions.

Worker cron: `30 18 * * *` (00:00 IST) and `30 0 * * *` (06:00 IST). Both target the previous Indian calendar day. Stock archives fall back up to seven calendar days, skipping weekends; morning runs retry delayed NAVs. Feeds fail independently. Latest prices are kept only for currently held instruments. Each IST day's previous-close baseline is persisted separately for 30 days. No historical contract-note importer is restored; Gmail linking remains available.

`market_prices` is separate from `zerodha_snapshots`. Portfolio responses apply only newer prices, or fill missing prices, and recompute valuation/allocation using decimal arithmetic. `holdingsSyncAt` stays unchanged; `capturedAt` reflects the latest applied valuation. Expired Kite tokens still allow saved holdings to be repriced while the 30-day Sumora session remains valid. A new Kite sync with newer quotes takes precedence over older closes.

The `daily_price_job` singleton records last run, failure source names and a five-minute lease. Prices are stored in one SQL statement per feed, avoiding the free Worker's 50-query limit. Feed download limit: 8 MiB; expanded NSE CSV limit: 32 MiB. There are two scheduled runs daily and no paid feed or new paid Cloudflare service. Free Worker CPU limits still apply; source-network access and CPU need production confirmation. Last good prices survive failed refreshes.

## Daily returns

`daily_price_baselines` records the previous available close/NAV by IST day, asset class, and ISIN. Cron runs and portfolio reads populate it from `market_prices`; today's intraday prices never become today's baseline. Same-date retries cannot change a saved baseline. A delayed newer prior-day publication can replace an older fallback reference. Weekends and holidays carry the most recent available close. Missing references stay unavailable, and stale quotes cannot carry yesterday's gain into today.

Daily gain is `current recorded quantity × (latest price − baseline price)`, with percentage measured against those quantities valued at the baseline. This measures price movement of currently held assets: purchases, sales, and deposits aren't counted as gains, but it does not include realized gains on shares already sold or intraday cash-flow-adjusted portfolio returns. A complete portfolio total requires a baseline and usable quote for every holding. The iOS homepage displays the daily amount and percentage; older cached responses without daily fields remain readable.

## Rollout

Cloudflare Builds is connected to `ritz078/sumora`, branch `main`, root `apps/api`. It runs `npm ci`, then `npx wrangler d1 migrations apply sumora-private --remote && npx wrangler deploy`. Migration `0008_daily_baselines.sql` adds baseline storage after the existing pricing migration. Existing market prices can initialize today's baseline immediately; a fresh installation needs its first successful closing-price fetch.

Verify `daily_price_job.result` after midnight/morning runs, confirm quote and baseline dates in authenticated portfolio responses, and monitor Worker CPU usage. Source failures retain previous prices; publication time and intraday updates are not guaranteed. Independent sources provide end-of-day prices; fresh intraday quotes still depend on Kite.

## GitHub CI

`.github/workflows/api-ci.yml` runs `npm ci`, `npm test`, and `npm run typecheck` with Node 24. It covers backend and shared fixture changes on `main` pushes and pull requests. Cloudflare Builds should use `apps/api` as its root, `npm ci` as its build command, and apply D1 migrations before `wrangler deploy`. GitHub CI and Cloudflare's Git-triggered deployment run independently; CI does not gate deployment without additional merge/deployment controls.
