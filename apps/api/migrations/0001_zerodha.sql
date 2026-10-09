CREATE TABLE IF NOT EXISTS zerodha_attempts (
 id TEXT PRIMARY KEY, challenge TEXT NOT NULL, expires_at INTEGER NOT NULL,
 result_hash TEXT UNIQUE, encrypted_token TEXT, provider_expires_at INTEGER, owner_id TEXT
);
CREATE TABLE IF NOT EXISTS zerodha_sessions (
 token_hash TEXT PRIMARY KEY, encrypted_token TEXT NOT NULL, owner_id TEXT NOT NULL,
 expires_at INTEGER NOT NULL, provider_expires_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS zerodha_snapshots (
 owner_id TEXT PRIMARY KEY, snapshot TEXT NOT NULL, synced_at INTEGER NOT NULL
);
