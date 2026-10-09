CREATE TABLE market_prices (
  kind TEXT NOT NULL CHECK (kind IN ('indianEquity', 'mutualFund')),
  isin TEXT NOT NULL, price TEXT NOT NULL, date TEXT NOT NULL, source TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (kind, isin)
);
CREATE TABLE daily_price_job (
  id INTEGER PRIMARY KEY CHECK (id = 1), running_until INTEGER NOT NULL DEFAULT 0,
  last_run_at INTEGER, result TEXT
);
INSERT INTO daily_price_job (id) VALUES (1);
