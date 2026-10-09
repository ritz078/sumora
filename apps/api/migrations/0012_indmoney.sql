CREATE TABLE indmoney_attempts (
 id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, challenge TEXT NOT NULL,
 encrypted_verifier TEXT NOT NULL, encrypted_client TEXT NOT NULL,
 expires_at INTEGER NOT NULL, result_hash TEXT UNIQUE, encrypted_credentials TEXT, callback_claimed INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE indmoney_connections (
 owner_id TEXT PRIMARY KEY, generation TEXT NOT NULL, encrypted_credentials TEXT NOT NULL,
 connected_at INTEGER NOT NULL, last_sync_at INTEGER, status TEXT NOT NULL DEFAULT 'connected',
 error TEXT, lease_until INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE indmoney_snapshots (
 owner_id TEXT PRIMARY KEY, snapshot TEXT NOT NULL, captured_at INTEGER NOT NULL
);
CREATE TABLE indmoney_capabilities (
 id INTEGER PRIMARY KEY CHECK(id=1), schema TEXT NOT NULL, discovered_at INTEGER NOT NULL
);
