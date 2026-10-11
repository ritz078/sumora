# Google app login

The app uses a server-side OpenID Connect authorization-code flow, separate from Gmail permissions. The existing Gmail web client can be reused; login requests only `openid email profile`, while Gmail connection requests its separate read-only scope.

Google Cloud → Google Auth Platform → Clients → Sumora Gmail Backend: retain the existing Gmail callback and add `https://sumora-api.rkritesh078.workers.dev/v1/auth/google/callback` to authorized redirect URIs.

The Worker uses existing `GMAIL_CLIENT_ID` / `GMAIL_CLIENT_SECRET` secrets unless separate `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` are configured. `GOOGLE_REDIRECT_URI` is a non-secret Worker variable. Keep `KITE_ENCRYPTION_KEY` stable. Apply migration 0022 before deployment.

App login uses Google subject as identity, verifies signed ID tokens (issuer/audience/expiry/nonce/verified email), and issues a hashed, 30-day app-session token. The mobile handoff uses a single-use claim protected by a local verifier. Google access/ID tokens are not persisted. App token is held in device Keychain.

On first login, connections and encrypted document passwords are configured before consolidated fetching; setup completion is saved per account. Providers are optional. Logout revokes only the current app session and clears private device state. Provider disconnect remains a separate action. Existing legacy app sessions can prove ownership during Google login; after migration they are retired. No account is linked merely by matching an email address.

A legacy session that has expired cannot prove ownership. Do not create an unverified association or silently discard existing holdings: reconnect/recovery must establish ownership first. Current production migration should be tested with the existing valid device session.

Before public distribution: configure branding/privacy policy and account deletion, complete any Gmail sensitive-scope requirements, validate the OAuth audience/publishing state, and add per-IP/account abuse controls. This implementation does not imply those launch steps are complete.

Reference: [Google OpenID Connect](https://developers.google.com/identity/openid-connect/openid-connect).
