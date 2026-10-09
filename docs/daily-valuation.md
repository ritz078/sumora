# Independent daily valuation

Recorded Zerodha equity shares and Coin fund units are repriced using NSE UDiFF closing prices and AMFI NAVAll. Neither feed requires an API key. Exact ISIN matching is mandatory; unsupported/unmatched holdings retain their last reported price. Quantities still require a broker sync after purchases, sales or corporate actions.

Worker cron: `30 18 * * *` (00:00 IST) and `30 0 * * *` (06:00 IST). Both target the previous Indian calendar day. Stock archives fall back up to seven calendar days, skipping weekends; morning runs retry delayed NAVs. Feeds fail independently. Only currently held instruments' latest prices are stored. No historical contract-note importer is restored; Gmail linking remains available.

`market_prices` is separate from `zerodha_snapshots`. Portfolio responses apply only newer prices, or fill missing prices, and recompute valuation/allocation using decimal arithmetic. `holdingsSyncAt` stays unchanged; `capturedAt` reflects the latest applied valuation. Expired Kite tokens still allow saved holdings to be repriced while the 30-day Sumora session remains valid. A new Kite sync with newer quotes takes precedence over older closes.

The `daily_price_job` singleton records last run, failure source names and a five-minute lease. Prices are stored in one SQL statement per feed, avoiding the free Worker's 50-query limit. Feed download limit: 8 MiB; expanded NSE CSV limit: 32 MiB. There are two scheduled runs daily and no paid feed or new paid Cloudflare service. Free Worker CPU limits still apply; source-network access and CPU need production confirmation. Last good prices survive failed refreshes.

## Rollout

Production still runs the older backend with stock contract imports paused. Deploying the local tree also applies the previously requested removal of stock contract/trade routes, while retaining Gmail OAuth. The prior deployment approval rejection must be resolved before that rollout.

After rollout approval, from `apps/api`:

1. Apply `0007_daily_prices.sql` to D1 (`wrangler d1 migrations apply sumora-private --remote`).
2. Deploy the Worker (`wrangler deploy`).
3. Wait for the scheduled run or exercise its scheduled handler locally with `wrangler dev --test-scheduled` and `GET /__scheduled`.
4. Inspect `daily_price_job.result` for updated count/source failures; compare price dates and portfolio values without logging credentials or personal holdings.
5. Confirm the next midnight/morning run succeeds, including Worker CPU usage. Source outages retain old quotes; no promise of a guaranteed publication time or live intraday prices.

Local checks: 39 backend tests, typecheck, Worker dry-run, 26 iOS simulator tests, and a workerd scheduled-handler/portfolio smoke test using real downloaded feeds and synthetic holdings. Public NSE and AMFI feeds dated 8 October 2026 were downloaded and parsed successfully during implementation.
