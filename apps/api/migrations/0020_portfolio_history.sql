CREATE TABLE portfolio_daily_snapshots (
 owner_id TEXT NOT NULL,
 day TEXT NOT NULL,
 captured_at INTEGER NOT NULL,
 data TEXT NOT NULL CHECK(json_valid(data)),
 PRIMARY KEY(owner_id,day)
);
CREATE TABLE portfolio_snapshot_jobs (
 owner_id TEXT PRIMARY KEY,
 last_attempt_at INTEGER NOT NULL,
 last_error TEXT
);
