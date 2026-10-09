CREATE TABLE IF NOT EXISTS gmail_attempts (
 id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, challenge TEXT NOT NULL,
 encrypted_verifier TEXT NOT NULL, expires_at INTEGER NOT NULL,
 result_hash TEXT UNIQUE, encrypted_refresh_token TEXT, email TEXT
);
CREATE TABLE IF NOT EXISTS gmail_connections (
 owner_id TEXT PRIMARY KEY, email TEXT NOT NULL, encrypted_refresh_token TEXT NOT NULL,
 connected_at INTEGER NOT NULL, last_sync_at INTEGER, last_attempt_at INTEGER,
 status TEXT NOT NULL DEFAULT 'connected', error TEXT, page_token TEXT,
 sync_since INTEGER NOT NULL DEFAULT 0, lease_id TEXT, lease_until INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS gmail_documents (
 owner_id TEXT NOT NULL, message_id TEXT NOT NULL, attachment_id TEXT NOT NULL,
 filename TEXT NOT NULL, received_at INTEGER NOT NULL, object_key TEXT NOT NULL,
 imported_at INTEGER NOT NULL, status TEXT NOT NULL DEFAULT 'awaiting_parser',
 PRIMARY KEY (owner_id, message_id, attachment_id)
);
CREATE INDEX IF NOT EXISTS gmail_documents_owner ON gmail_documents(owner_id, received_at);
