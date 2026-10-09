# Gold valuation and Gullak balances

Gold uses Snapdata's free Indian 24K/IBJA daily JSON feed, in INR per gram. No API key is needed. Snapdata currently labels observations provisional; values are estimates, not Gullak liquidation quotes.

## App setup

Connect Zerodha to sign in to Sumora, then connect Gmail under Connections. In Settings → Gullak gold, enter the 10-digit mobile number registered with Gullak, save the decryption password, and tap Sync Gullak. The server derives the middle eight digits and stores only that password encrypted with the existing encryption key. Neither mobile number nor password is returned by status endpoints.

The screen shows the recorded grams, statement period, balance date, quote date, last sync attempt and errors. Removing the password stops automatic imports and keeps the last recorded holding. Disconnecting Gmail also stops collection; it retains imported financial checkpoints.

## Automatic processing

Cron runs at midnight, 06:00 and 20:00 IST. The extra evening run captures the published daily gold rate. Each invocation refreshes the shared gold price, checks one configured mailbox, then runs existing equity/MF valuation. Mailboxes rotate by last attempt; this deployment currently serves one account.

Only Gmail messages from no-reply@gullak.money with the exact monthly statement subject are accepted. Google must report DMARC pass for gullak.money. Search is limited to the last 120 days and ten messages, and at most one unseen PDF is parsed per invocation. This does not collect stock contract notes or rebuild trade history.

PDFs are decrypted/extracted in memory using unpdf. A monthly checkpoint must reconcile opening gold + buys - sells + credited Gold+ interest = total gold. Leased grams are already part of total holdings. Nonzero mixed-metal rewards, unexpected formats and continuity gaps require review. No PDF archive is created; source IDs, content hashes, dates, validated balances and safe error messages are stored in D1. Imported content is idempotent and older statements cannot regress the checkpoint. The first checkpoint is a self-reconciled recent statement, not a claim that all previous activity is available. Later periods must be consecutive and opening grams must equal the previous recorded closing grams.

## Prices and daily changes

The latest endpoint is https://snapdata.dev/api/v1/gold/in/latest.json. Accept only one XAU.24K.INR.G observation with valid nonfuture date, positive decimal value and expected Indian INR/gram schema/source. HTTP bodies are bounded and redirects are rejected. Last valid quotes survive network/schema failures and older dates cannot replace newer quotes.

Persist each daily quote in gold_price_history and latest in market_prices. Freeze a prior-day gold baseline before replacing the latest quote; same-day revisions cannot move that baseline. On the first run, try explicitly dated Snapdata snapshots up to seven prior days. Missing baseline means unavailable daily gain, never a fabricated zero. Existing 30-day baseline retention applies; daily gold price history remains available.

Estimated gold value = recorded grams × latest INR/gram price. Daily movement = current recorded grams × (latest price − prior-day baseline). Changes in grams are not counted as price return. Daily portfolio gain still requires coverage for every holding. Acquisition cost is unknown from a balance checkpoint: gold and overall all-time gain are unavailable, and invested cost is shown as unavailable for gold. Quantity and price dates remain separate and visible.

## Verification

Backend tests cover validation, date regression, persisted baselines, failures, account isolation, encrypted setup, sender authentication, content deduplication, continuity, encrypted PDF import and combined portfolio totals. The encrypted PDF fixture is synthetic and contains no personal data. Actual August and September statements were checked privately without adding them to this repo.

Use npm test and npm run typecheck in apps/api. Build the Worker with npx wrangler deploy --dry-run. Run SumoraTests on an iOS simulator with normal simulator signing enabled (the Keychain test requires signed entitlements). The importer and live Snapdata persistence were also exercised inside local workerd with isolated D1 storage.

## Silver balances

The same statement also supplies opening silver, bought grams, sold grams, and closing silver. Reconcile opening + buys − sells = closing independently from gold, then persist both metals in the same checkpoint. Mixed-metal rewards still require review. Nonzero silver continuity gaps reject the whole checkpoint and retain previous balances.

Settings displays dated silver grams, including an explicit zero when verified. Existing gold-only checkpoints keep silver unknown until their original PDF is reprocessed with parser version 2; duplicate detection then resumes. No silver INR valuation is inferred from the gold rate, and silver is not included in net worth until a separate price source is implemented.
