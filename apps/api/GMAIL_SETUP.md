# Gmail connection

Gmail remains available as a generic read-only connector for future gold imports. Contract-note collection, PAN entry, PDF parsing, trade history and scheduled imports are removed. Gold ingestion is not implemented yet.

The existing Google Web OAuth client uses https://sumora-api.rkritesh078.workers.dev/v1/gmail/callback and the gmail.readonly scope. Worker secrets GMAIL_CLIENT_ID, GMAIL_CLIENT_SECRET and the existing KITE_ENCRYPTION_KEY remain configured; never rotate the encryption key without migrating ciphertext.

Authenticated routes: POST /v1/gmail/start, POST /v1/gmail/claim, GET /v1/gmail/connection, DELETE /v1/gmail/connection. Google's callback is public and bound to an expiring server attempt. Claims are owner-bound, verifier-bound and single use. Google refresh tokens remain encrypted on the backend and are never returned to the app.

Connections shows Gmail link/reconnect/status/disconnect controls. No Sync Now, document counters, PAN controls, scheduled jobs or R2 binding are enabled. Existing credentials, collected documents and database records remain retained. Migration history is preserved.
