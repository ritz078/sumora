-- Conservative, global high-water reservation. Failed puts and overwritten objects
-- remain counted so retries and orphaned uploads cannot bypass the storage budget.
CREATE TABLE gmail_storage_budget (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    reserved_bytes INTEGER NOT NULL DEFAULT 0 CHECK (reserved_bytes >= 0),
    upload_day INTEGER NOT NULL DEFAULT 0,
    upload_attempts INTEGER NOT NULL DEFAULT 0 CHECK (upload_attempts >= 0)
);
INSERT INTO gmail_storage_budget (id) VALUES (1);
