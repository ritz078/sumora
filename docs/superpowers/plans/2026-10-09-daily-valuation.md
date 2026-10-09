# Daily Valuation Implementation Plan

> **For agentic workers:** Use executing-plans for inline implementation.

**Goal:** Revalue recorded shares and mutual-fund units using independent free closing prices.

**Architecture:** A twice-daily Worker cron stores only prices matching recorded ISINs. Portfolio responses overlay newer prices onto saved quantities, preserving quantity-sync timestamps and last good data.

**Tech Stack:** Hono, D1, decimal.js, fflate, NSE UDiFF, AMFI NAV.

**Spec:** User-approved scope recorded below.

## Global Constraints
- Midnight IST refresh and 06:00 IST retry; no paid feed or broker token required.
- Exact ISIN matching; no symbol/name guessing, no historical contract imports.
- Preserve Gmail, existing holdings and prices on feed errors.
- Do not replace a newer broker valuation with an older closing price.
- Save only latest prices for held instruments; no historical trajectory feature.

## Review Focus
- Holidays and unavailable stock archives retain prior prices.
- Fractional units use decimal arithmetic without rounding loss.
- Ambiguous ISIN rows and invalid/future prices must not overwrite data.
- Expired broker sessions still expose independently updated prices.
- Revaluation must not modify quantity sync timestamps or cross account boundaries.

### Task 1: Exact feed parsing and portfolio valuation
Files: src/daily-prices.ts, src/portfolio-valuation.ts, test/daily-valuation.test.ts.
Interfaces: MarketPrice { isin, kind, price, date, source }; parsers accept text and maximum date; revalue accepts snapshot and MarketPrice[].
- [x] Add failing tests for both feed schemas, invalid/duplicate quotes, fractional quantities, missing quotes and newer broker prices.
- [x] Run tests and observe missing-module failure.
- [x] Implement bounded ZIP decoding, exact ISIN parsing and decimal totals.
- [x] Run focused tests until passing.

### Task 2: Durable refresh and response integration
Files: src/daily-valuation-job.ts, migrations/0007_daily_prices.sql, src/index.ts, src/zerodha.ts, wrangler.jsonc, test/daily-valuation-job.test.ts, test/zerodha.test.ts.
Interfaces: refreshDailyPrices(env, fetcher, at), valuedSnapshot(env, snapshot).
- [x] Add failing SQLite-backed tests for persisted latest prices, partial failures, retries, held-instrument filtering and expired-session responses.
- [x] Implement bounded source requests and latest-price upserts, integrate every portfolio response and scheduled handler.
- [x] Verify full backend tests, typecheck and Worker bundle; probe public sources.
- [x] Review final code and address material findings. Record deployment status separately from local completion.

No commits requested. Existing untracked repository is retained in place.

## Execution record
- Implemented inline in the existing untracked checkout; no commits or checkout changes.
- Both initial test modules failed before production modules existed.
- Review findings reproduced with failing tests, then fixed: D1 query exhaustion for 80 holdings; missing broker quote rejecting an independent close.
- Chose AMFI official bulk NAV instead of MFapi to match recorded ISINs without an extra mapping provider.
- Kept only latest prices; no historical snapshot/trajectory scope added.
- Production rollout remains separate because it also removes previously retired routes; prior automatic approval rejected that service-impacting deployment.

## Final verification
- 39 backend tests pass; TypeScript typecheck passes; Wrangler dry-run builds.
- 26 iOS tests pass on iPhone 18 Pro; latest app installed on simulator.
- Downloaded real NSE and AMFI files successfully. Selected 80-ISIN parsing measured 2 ms/3 ms locally (not production CPU guarantees).
- workerd smoke with real downloaded feeds and synthetic holdings: scheduled handler stored both source prices, portfolio returned HTTP 200 with broker expired, quantities/sync timestamp preserved.
- Runtime smoke caught unsupported redirect:error; regression assertion failed then passed after changing to manual redirects.
- No production migration or deployment performed.
