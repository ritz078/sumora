CREATE TABLE gmail_decryption (
 owner_id TEXT PRIMARY KEY,
 encrypted_pan TEXT NOT NULL,
 version TEXT NOT NULL,
 password_error INTEGER NOT NULL DEFAULT 0 CHECK(password_error IN (0,1))
);
ALTER TABLE gmail_documents ADD COLUMN processing_id TEXT;
ALTER TABLE gmail_documents ADD COLUMN processing_until INTEGER NOT NULL DEFAULT 0;
ALTER TABLE gmail_documents ADD COLUMN processing_attempts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE gmail_documents ADD COLUMN retry_at INTEGER NOT NULL DEFAULT 0;
ALTER TABLE gmail_documents ADD COLUMN pan_version TEXT;
ALTER TABLE gmail_documents ADD COLUMN source_hash TEXT;
ALTER TABLE gmail_documents ADD COLUMN processing_error TEXT;
ALTER TABLE gmail_documents ADD COLUMN processed_at INTEGER;
CREATE INDEX gmail_documents_queue ON gmail_documents(status,retry_at,processing_until);
CREATE UNIQUE INDEX gmail_processing_lease ON gmail_documents(processing_id) WHERE processing_id IS NOT NULL;
CREATE TABLE gmail_processing_budget (
 id INTEGER PRIMARY KEY CHECK(id=1),
 read_day INTEGER NOT NULL DEFAULT 0 CHECK(read_day>=0),
 read_attempts INTEGER NOT NULL DEFAULT 0 CHECK(read_attempts>=0)
);
INSERT INTO gmail_processing_budget(id) VALUES (1);
