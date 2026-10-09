CREATE TABLE bonds_settings(owner_id TEXT PRIMARY KEY,encrypted_password TEXT NOT NULL,scan_cursor TEXT,updated_at INTEGER NOT NULL,last_sync_at INTEGER,error TEXT,lease_until INTEGER NOT NULL DEFAULT 0);
CREATE TABLE bonds_snapshots(owner_id TEXT PRIMARY KEY,account_hash TEXT NOT NULL,statement_date TEXT NOT NULL,total TEXT NOT NULL,bonds TEXT NOT NULL,message_id TEXT NOT NULL,content_hash TEXT NOT NULL,imported_at INTEGER NOT NULL);
CREATE TABLE bonds_imports(owner_id TEXT NOT NULL,content_hash TEXT NOT NULL,message_id TEXT NOT NULL,status TEXT NOT NULL CHECK(status IN ('imported','ignored','needs_review')),error TEXT,imported_at INTEGER NOT NULL,PRIMARY KEY(owner_id,content_hash));
CREATE INDEX bonds_import_message ON bonds_imports(owner_id,message_id);
-- A snapshot and its successful import record commit or roll back together.
CREATE TRIGGER bonds_snapshot_import_insert AFTER INSERT ON bonds_snapshots BEGIN
 INSERT INTO bonds_imports(owner_id,content_hash,message_id,status,imported_at)
 VALUES(NEW.owner_id,NEW.content_hash,NEW.message_id,'imported',NEW.imported_at)
 ON CONFLICT(owner_id,content_hash) DO UPDATE SET status='imported',error=NULL;
END;
CREATE TRIGGER bonds_snapshot_import_update AFTER UPDATE ON bonds_snapshots BEGIN
 INSERT INTO bonds_imports(owner_id,content_hash,message_id,status,imported_at)
 VALUES(NEW.owner_id,NEW.content_hash,NEW.message_id,'imported',NEW.imported_at)
 ON CONFLICT(owner_id,content_hash) DO UPDATE SET status='imported',error=NULL;
END;
