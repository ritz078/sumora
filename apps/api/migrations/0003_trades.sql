CREATE TABLE trade_notes (
 owner_id TEXT NOT NULL,
 contract_id TEXT NOT NULL,
 trade_date TEXT NOT NULL,
 source_hash TEXT NOT NULL,
 canonical_hash TEXT NOT NULL,
 imported_at INTEGER NOT NULL,
 payload TEXT NOT NULL CHECK(json_valid(payload)),
 PRIMARY KEY(owner_id, contract_id, trade_date)
);
CREATE VIEW trade_ledger AS
 SELECT n.owner_id,n.contract_id,n.trade_date,n.imported_at,
 json_extract(f.value,'$.id') AS execution_id,f.value AS fill
 FROM trade_notes n,json_each(n.payload,'$.fills') f;
CREATE TRIGGER prevent_overlapping_executions BEFORE INSERT ON trade_notes
 WHEN EXISTS(SELECT 1 FROM trade_ledger old,json_each(NEW.payload,'$.fills') incoming
 WHERE old.owner_id=NEW.owner_id AND old.execution_id=json_extract(incoming.value,'$.id'))
 BEGIN SELECT RAISE(ABORT,'EXECUTION_CONFLICT'); END;
CREATE INDEX trade_notes_owner_date ON trade_notes(owner_id,trade_date DESC);
