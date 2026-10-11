# Google login and onboarding

Approved flow: Google sign-in → provider connections and document passwords → fetch consolidated holdings → home. Returning users skip completed setup. Logout revokes only the app session and clears device state; provider credentials and holdings persist.

Implementation: independent app accounts/sessions, Google authorization code exchange with PKCE and signed ID-token verification, single-use mobile claims; existing portfolio ownership is linked only with proof from a valid legacy session. Provider credentials move to a separate table. Fresh accounts can aggregate a portfolio without Zerodha. Every private endpoint resolves a session to a server-owned data namespace.

Tasks:
1. Add migration and authenticated Google login/session/onboarding routes. Test replay, identity validation, migration, isolation, logout.
2. Decouple Zerodha connect/disconnect from app login; support empty portfolios with other providers. Preserve legacy clients during rollout until migrated.
3. Add native Google login gate and onboarding, configure all providers with the app session, clear local state on logout.
4. Run backend suite/typecheck, iOS unit/UI tests and simulator build. Configure Google callback, deploy and validate real sign-in.

Public-release work outside this change: Google sensitive-scope verification for Gmail, privacy/account-deletion flows and production abuse controls.
