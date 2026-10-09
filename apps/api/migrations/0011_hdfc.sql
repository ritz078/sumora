CREATE TABLE hdfc_settings(owner_id TEXT PRIMARY KEY,encrypted_password TEXT NOT NULL,updated_at INTEGER NOT NULL,last_sync_at INTEGER,error TEXT,lease_until INTEGER NOT NULL DEFAULT 0);
CREATE TABLE hdfc_snapshots(owner_id TEXT PRIMARY KEY,statement_date TEXT NOT NULL,total TEXT NOT NULL,deposits TEXT NOT NULL,message_id TEXT NOT NULL,content_hash TEXT NOT NULL,imported_at INTEGER NOT NULL);
CREATE TABLE hdfc_imports(owner_id TEXT NOT NULL,content_hash TEXT NOT NULL,message_id TEXT NOT NULL,status TEXT NOT NULL,error TEXT,imported_at INTEGER NOT NULL,PRIMARY KEY(owner_id,content_hash));
