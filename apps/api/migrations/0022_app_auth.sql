CREATE TABLE app_accounts (
 id TEXT PRIMARY KEY, google_sub TEXT NOT NULL UNIQUE, email TEXT NOT NULL,
 data_owner_id TEXT NOT NULL UNIQUE, onboarding_completed INTEGER NOT NULL DEFAULT 0,
 created_at INTEGER NOT NULL
);
CREATE TABLE app_sessions (
 token_hash TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES app_accounts(id), expires_at INTEGER NOT NULL
);
CREATE INDEX app_sessions_account ON app_sessions(account_id);
CREATE TABLE google_login_attempts (
 id TEXT PRIMARY KEY, challenge TEXT NOT NULL, encrypted_verifier TEXT NOT NULL, nonce TEXT NOT NULL,
 expires_at INTEGER NOT NULL, legacy_owner_id TEXT, result_hash TEXT UNIQUE, identity TEXT, exchanging INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE zerodha_connections (
 owner_id TEXT PRIMARY KEY, client_id TEXT NOT NULL UNIQUE, encrypted_token TEXT NOT NULL, provider_expires_at INTEGER NOT NULL
);
INSERT INTO zerodha_connections (owner_id,client_id,encrypted_token,provider_expires_at)
 SELECT owner_id,owner_id,encrypted_token,provider_expires_at FROM (
 SELECT *,ROW_NUMBER() OVER (PARTITION BY owner_id ORDER BY provider_expires_at DESC,expires_at DESC) AS rank FROM zerodha_sessions
 ) WHERE rank=1;
ALTER TABLE zerodha_attempts ADD COLUMN app_owner_id TEXT;
