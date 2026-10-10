# Daily portfolio snapshots

One owner-scoped observation per Indian calendar day, beginning when this feature is enabled. The existing fifteen-minute scheduled event captures the latest stored portfolio after the US-holdings sync. It does not require an open app, a valid Kite trading session, or extra upstream calls. Source updates from other scheduled jobs are included in subsequent captures.

Today's row is replaced only by a later observation. At midnight IST a new row is created; past days are not backfilled or reconstructed. The record is the latest successfully observed value for that day, not a guaranteed market-close valuation. Days missed during an outage remain absent.

Each record contains all holdings and their quantities, original valuation basis/source, investment-specific terms, source connection dates, total net worth, coverage, and totals for all eight instrument types. Holding metadata separately records valuation and quantity dates. NPS quantity dates are preserved separately for each tier. Undated broker quote and US-stock retrieval times are stored separately because INDmoney does not supply the market valuation timestamp. A carried-forward flag means the valuation date predates the snapshot day; missing/future source dates are marked unknown. This is not a claim that the quantity was independently verified that day.

FDs use maturity amounts; bonds use projected maturity value with CAS purchase value fallback; properties use full manually entered estimates. Their source dates and basis remain visible. Unknown prices stay null, with partial/unavailable coverage; no fake zero prices or daily P&L is generated.

Records persist independently of the 30-day price-baseline retention. There is no history deletion on ordinary broker disconnect/reconnect. Snapshot data contains financial holdings, not provider tokens, passwords, PAN or Gmail bodies.

## API

Authenticated with the existing Sumora bearer session:

- `GET /v1/portfolio/history?from=YYYY-MM-DD&to=YYYY-MM-DD`: chronological daily summaries, instrument totals and coverage. Defaults to the most recent 30 calendar days; maximum inclusive range is 90 days. Older data can be read in further date windows. Missing days are omitted.
- `GET /v1/portfolio/history/YYYY-MM-DD`: full record, portfolio and holding provenance for a recorded day; 404 if absent.

The server always derives the owner from the session. This change adds persistence and API access; it does not reintroduce historical charts into the app.

## Operations

Migration 0020 creates the history and attempt tables. One owner is processed per fifteen-minute invocation, rotated by oldest attempt to bound database work and avoid starvation after a bad source. This is suitable for this personal app; scheduling must be expanded before a large multi-user rollout. Failure retains the previous snapshot and records a generic error in `portfolio_snapshot_jobs`. A failed attempt can retry on the next scheduled invocation.
