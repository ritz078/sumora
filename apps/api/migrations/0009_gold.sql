ALTER TABLE market_prices RENAME TO market_prices_before_gold;
CREATE TABLE market_prices (
 kind TEXT NOT NULL CHECK (kind IN ('indianEquity','mutualFund','gold')),
 isin TEXT NOT NULL, price TEXT NOT NULL, date TEXT NOT NULL, source TEXT NOT NULL,
 updated_at INTEGER NOT NULL, PRIMARY KEY(kind,isin)
);
INSERT INTO market_prices SELECT * FROM market_prices_before_gold;
DROP TABLE market_prices_before_gold;
ALTER TABLE daily_price_baselines RENAME TO daily_price_baselines_before_gold;
CREATE TABLE daily_price_baselines (
 day TEXT NOT NULL, kind TEXT NOT NULL CHECK (kind IN ('indianEquity','mutualFund','gold')),
 isin TEXT NOT NULL, price TEXT NOT NULL, price_date TEXT NOT NULL, source TEXT NOT NULL,
 PRIMARY KEY(day,kind,isin)
);
INSERT INTO daily_price_baselines SELECT * FROM daily_price_baselines_before_gold;
DROP TABLE daily_price_baselines_before_gold;
CREATE TABLE gold_price_history (date TEXT PRIMARY KEY, price TEXT NOT NULL, source TEXT NOT NULL, fetched_at INTEGER NOT NULL);
CREATE TABLE gold_price_job (id INTEGER PRIMARY KEY CHECK(id=1),running_until INTEGER NOT NULL DEFAULT 0,last_run_at INTEGER,error TEXT);
INSERT INTO gold_price_job(id) VALUES(1);
CREATE TABLE gullak_settings (owner_id TEXT PRIMARY KEY, encrypted_password TEXT NOT NULL, updated_at INTEGER NOT NULL, last_sync_at INTEGER, error TEXT, lease_until INTEGER NOT NULL DEFAULT 0);
CREATE TABLE gullak_checkpoints (owner_id TEXT PRIMARY KEY, grams TEXT NOT NULL, opening_grams TEXT NOT NULL, period_start TEXT NOT NULL, period_end TEXT NOT NULL, balance_date TEXT NOT NULL, message_id TEXT NOT NULL, content_hash TEXT NOT NULL, imported_at INTEGER NOT NULL);
CREATE TABLE gullak_imports (owner_id TEXT NOT NULL, content_hash TEXT NOT NULL, message_id TEXT NOT NULL, status TEXT NOT NULL, error TEXT, imported_at INTEGER NOT NULL, PRIMARY KEY(owner_id,content_hash));
