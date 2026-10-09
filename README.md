# Sumora

Native SwiftUI iPhone portfolio dashboard, targeting iOS 17 or later. Open `apps/ios/Sumora.xcodeproj`, select **Sumora**, and run on an iPhone simulator.

## Included

- Overview: portfolio value, unrealized return, selectable history periods, interactive chart and asset allocation.
- Holdings: search by investment or account, asset filters, sorting and detail navigation.
- Investment detail: quantity, invested amount, original-currency price, reporting-currency valuation, exchange rate, history and valuation provenance.
- Connections: sample account status and last successful sync.
- Settings: persistent balance privacy, appearance and six demo scenarios.
- Loading, empty, partial, unavailable, stale and failed-refresh states.

All portfolio data is illustrative. The sample clock is fixed at 6 October 2026. The app can fetch samples from the Hono API or use bundled offline fixtures. No broker credentials or authentication are used.

## Data and state

`AppDependencies` assembles the app. `PortfolioStore` owns one snapshot shared by Overview and Holdings. `PortfolioAPI` defines the data boundary; `HTTPPortfolioAPI` uses URLSession and `MockPortfolioAPI` loads bundled JSON fixtures. Network errors remain visible, without silently switching to offline data.

Money and quantities arrive as decimal strings and decode directly to `Decimal`. Floating-point conversion is confined to chart rendering. The API owns valuations and return calculations. Missing prices remain unavailable, and partial totals exclude unvalued holdings. Portfolio value is distinct from net worth: liabilities and non-investment assets are not included.

One foreground task refreshes the snapshot every 30 seconds while Overview or Holdings is selected. Pull to refresh reads the same snapshot source. Refresh failure retains the previous snapshot. Cancellation and source changes prevent obsolete requests from overwriting current state.

Privacy masks amounts and quantities and removes value and allocation charts from both display and accessibility. Appearance supports system, light and dark modes.

## Verify

```sh
xcodebuild -project apps/ios/Sumora.xcodeproj -scheme Sumora \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  test CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
```

Choose an installed simulator name for your machine. `SumoraTests` uses Swift Testing for decimal precision, malformed amounts, fixture consistency, combined filtering and refresh lifecycle. `SumoraUITests` uses XCTest for navigation, privacy, filtering, failed-refresh retention and empty-state recovery.

The app icon is a local asset; the iOS app has no third-party dependencies. Physical-device builds require an Apple development team in Signing & Capabilities.

## Hono API on Cloudflare Workers

```sh
cd apps/api
npm ci
npm test
npm run typecheck
npm run dev
```

The iOS app defaults to the deployed sample API at `https://sumora-api.rkritesh078.workers.dev`. For local development, start the Worker and set `http://localhost:8787` in Settings → Portfolio data, then tap **Connect to sample API**. This reaches the local Worker from the simulator. Settings also lets you choose offline samples. UI tests use offline fixtures; the separate `SumoraAPIIntegrationTests` exercises real HTTP and skips when the local server is unavailable. For a physical device, use the deployed HTTPS endpoint rather than localhost.

Public sample endpoints:

- `GET /health` returns the service status.
- `GET /v1/demo/portfolio?scenario=complete` returns the existing snapshot contract. Other scenarios: `partial`, `stale`, `empty`, `unavailable`, `failure` (HTTP 503).
- Unsupported scenarios return JSON HTTP 400; unknown routes return JSON HTTP 404. Responses disable caching. Decimal values are strings, and sample timestamps stay fixed.

The Worker imports the same JSON fixtures as the iOS offline client. This prevents duplicate fixture copies drifting. There is no user-specific data, authentication, or storage in this public sample API.

Deploy to your Cloudflare account:

```sh
cd apps/api
npx wrangler login
npm run deploy
```

Paste Wrangler's HTTPS deployment address into Settings and tap **Connect to sample API**. Release builds accept only HTTPS API addresses and have no HTTP exception. Debug permits HTTP only for loopback hosts. Secrets belong in Wrangler secrets or ignored `.dev.vars`, never source control.

## Zerodha connection

Settings → Connections → **Connect Zerodha** opens native browser authentication. The server derives account identity from the verified Kite login and binds the session to that account. Broker tokens are encrypted on Cloudflare, and the separate Sumora session is stored in Keychain. Equity delivery holdings and Coin mutual funds feed the existing dashboard; sample data is never merged into the personal portfolio. Expired Kite sessions show a reconnect action and the last successful import. Disconnect removes server sessions, the cached snapshot and the app's Keychain session.

Register `https://sumora-api.rkritesh078.workers.dev/v1/zerodha/callback` on your Kite Connect app. Configure `KITE_API_KEY`, `KITE_API_SECRET`, and a base64 32-byte `KITE_ENCRYPTION_KEY` as Worker secrets. See `docs/zerodha-integration.md` for the full setup and endpoint contract. Keep the encryption key stable across deployments. Run D1 migrations before local or production authentication:

```sh
cd apps/api
npx wrangler d1 migrations apply sumora-private --local
```

Normal simulator signing is required for Keychain access; do not disable signing for tests or the installed app. The data adapter uses lossless JSON and decimal arithmetic. It excludes intraday positions and stops on unsupported pledged/MTF holdings or discrepancies. Historical value data is not yet collected.

## Next milestone

Multi-user Sign in with Apple, additional brokers, instrument classification, historical snapshots and live quote subscriptions remain future milestones. The current Zerodha integration binds each connection to the account authenticated through Kite and uses the prices reported by Kite holdings APIs.

## Backend CI and automatic deployment

GitHub Actions runs API tests and TypeScript checks on pushes to `main` and pull requests affecting the backend, shared portfolio fixtures, or the workflow. It uses Node 24, installs from the lockfile with `npm ci`, then runs `npm test` and `npm run typecheck`. No Cloudflare credentials are required for CI.

Connect the existing `sumora-api` Worker to `ritz078/sumora` in Cloudflare Settings → Builds:

- Production branch: `main`
- Root directory: `apps/api`
- Build command: `npm ci`
- Deploy command: `npx wrangler d1 migrations apply sumora-private --remote && npx wrangler deploy`

Cloudflare does not repeat the tests or typecheck. Its Git integration deploys independently of GitHub Actions; this workflow alone does not make deployment wait for CI. To protect `main`, require the `API tests and typecheck` status check before merging pull requests. Production rollout settings remain managed in Cloudflare.

### HDFC fixed deposits

Connect Gmail, then open Settings → HDFC fixed deposits and save the Customer ID used to decrypt HDFC monthly combined statements. Tap Sync HDFC to import the latest statement. The password is encrypted with the existing server encryption key and is never returned by the API. Removing it stops imports while retaining the last recorded FD balances.

FDs contribute the statement’s **maturity amounts** to net worth, including future interest. The app labels these as maturity amounts rather than current withdrawal values. Original principal, interest rate and dates remain available in holding details. The importer separately validates withdrawable amounts against the bank’s term-deposit summary. Existing imported deposits are revalued without a new statement import. Daily interest and investment returns are not inferred. FD identifiers are owner-scoped hashes with only the final four digits displayed.

Automatic jobs rotate between configured Gullak, HDFC and NPS mailbox sources, processing at most one unseen PDF per invocation. Duplicate attachments are skipped; older statements cannot regress balances, and conflicting or invalid statements retain the previous snapshot. PDFs are processed in memory and are not retained. No AI extraction service is used. Migration `0011_hdfc.sql` is applied by the existing Cloudflare deployment command.

### NPS

Settings → NPS schemes → Enable NPS imports → Sync NPS uses the existing Gmail connection. Supported KFintech Tier I / Tier II statements supply scheme units, NAVs and closing values. The value contributes to net worth under NPS, clearly dated to the statement valuation date; live NAVs and daily NPS returns are not estimated.

The verified KFintech email can supply the PRAN used to decrypt its attachment. It is checked against the decrypted statement and encrypted with the existing server key; a SecureField override is available when automatic discovery is unavailable. PRANs, PDFs and extracted text are never returned by these endpoints or retained as plaintext. D1 stores normalized schemes, an owner-scoped account hash, source IDs and content hashes. Stopping imports removes the encrypted password and keeps the recorded balances.

Imports verify the authenticated sender, reconcile scheme units × NAV and both statement totals, reject conflicting dates/accounts, deduplicate attachments and preserve the last verified snapshot on failure. Search is limited to the last 120 days, paginated ten messages per run with at most one PDF parsed; untrusted search matches are skipped; the existing bounded statement schedule rotates across enabled sources. Deployment applies migration `0014_nps.sql`. Tests use a synthetic encrypted PDF, not a personal statement.
