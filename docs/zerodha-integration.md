# Personal Zerodha integration

Connect Zerodha in the app starts Kite authentication. The server obtains the account identity from Kite's verified token exchange, binds it to the Sumora session, and isolates cached portfolios by that identity. No manually configured owner ID is required. This build does not yet have separate Sumora user registration or Sign in with Apple. The app reads holdings; it does not submit orders, convert positions, or authorize sales.

## Setup

Create or use an existing Kite Connect app and register this redirect URL:

`https://sumora-api.rkritesh078.workers.dev/v1/zerodha/callback`

Configure `KITE_API_KEY`, `KITE_API_SECRET` and `KITE_ENCRYPTION_KEY` through Wrangler secrets. The encryption key is a base64-encoded random 32-byte key. Keep that key stable across redeployments: it decrypts existing sessions. The local setup wizard captures credentials with hidden secret entry and writes an ignored, owner-readable `.dev.vars` file before uploading secrets.

The D1 binding `DB` uses `sumora-private`. Apply `apps/api/migrations/0001_zerodha.sql` locally and remotely before running the connector. All personal endpoints disable caching. Financial snapshots require a valid Sumora session and never appear under the public demo route.

## Authentication

The app generates a random verifier and sends its SHA-256 challenge to `POST /v1/zerodha/start`. The backend stores a ten-minute attempt and returns a Kite login URL with an unpredictable state forwarded through `redirect_params`. Swift opens that URL using `ASWebAuthenticationSession`.

The HTTPS callback validates state, exchanges the single-use Kite request token, validates the identity returned by Kite, and encrypts the broker access token using AES-GCM. It redirects to `sumora://zerodha` with a one-minute completion code. The app verifies callback scheme, host and state, then sends the code and original verifier to `POST /v1/zerodha/claim`. Atomic deletion of the matching attempt makes completion single-use. The claim returns a separate thirty-day Sumora session; only its SHA-256 digest is stored on the backend, and the native token is saved in Keychain for that API address.

Broker tokens remain on Cloudflare. A standard Kite token requires reconnection at the next 6 AM IST expiry or earlier revocation. A valid Sumora session can still retrieve the last successful snapshot, clearly marked as needing reconnection. Disconnect revokes the broker session where possible and removes the owner's Sumora sessions and cached snapshot; the app then removes its Keychain session.

## Import contract

`GET /v1/zerodha/portfolio` fetches `/portfolio/holdings` and `/mf/holdings`. Both must succeed before publishing a new snapshot. Equity delivery quantity uses `quantity + t1_quantity - used_quantity`; funds use the reported units. Decimal JSON values are parsed losslessly and calculations use decimal arithmetic. Zero or absent prices remain unavailable; partial totals exclude unvalued holdings from covered cost. Reported average price supplies the invested basis. Original broker P&L is recomputed consistently from quantity, cost and reported price.

Duplicate equity ISINs, discrepancies, pledged holdings and MTF holdings stop the import with an explanation to avoid incorrect totals. Listed equity securities are grouped under Indian stocks; instrument classification, intraday positions, cash balances and other brokers are future work. Mutual fund NAV dates are preserved when supplied. Equity trade timestamps are unavailable from this response; fetching time is not presented as a trade timestamp. No historical value chart is fabricated. Current snapshots are cached for thirty seconds.

## Verification

Backend tests exercise real SQLite storage with a simulated Kite transport: verified identity, account isolation, code/verifier binding, callback replay, token encryption, expiry, disconnect and precise valuations. Swift tests verify callback validation, authenticated routing, Keychain persistence and the existing portfolio behavior. Live account authorization and the first real import must be verified by the owner in the simulator after credentials are configured.
