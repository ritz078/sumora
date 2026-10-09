ALTER TABLE bonds_settings ADD COLUMN wint_cursor TEXT;
ALTER TABLE bonds_settings ADD COLUMN scan_kind TEXT NOT NULL DEFAULT 'cas';
CREATE TABLE wint_events(owner_id TEXT NOT NULL,event_key TEXT NOT NULL,account_hash TEXT,data TEXT NOT NULL,economic_hash TEXT NOT NULL,message_id TEXT NOT NULL,imported_at INTEGER NOT NULL,PRIMARY KEY(owner_id,event_key));
CREATE TABLE wint_imports(owner_id TEXT NOT NULL,message_id TEXT NOT NULL,status TEXT NOT NULL CHECK(status IN ('imported','ignored','needs_review')),error TEXT,imported_at INTEGER NOT NULL,PRIMARY KEY(owner_id,message_id));
CREATE TRIGGER wint_event_import_insert AFTER INSERT ON wint_events BEGIN
 INSERT INTO wint_imports(owner_id,message_id,status,imported_at) VALUES(NEW.owner_id,NEW.message_id,'imported',NEW.imported_at) ON CONFLICT(owner_id,message_id) DO UPDATE SET status='imported',error=NULL;
END;
CREATE TRIGGER wint_event_import_update AFTER UPDATE ON wint_events BEGIN
 INSERT INTO wint_imports(owner_id,message_id,status,imported_at) VALUES(NEW.owner_id,NEW.message_id,'imported',NEW.imported_at) ON CONFLICT(owner_id,message_id) DO UPDATE SET status='imported',error=NULL;
END;
