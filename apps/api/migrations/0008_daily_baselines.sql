CREATE TABLE daily_price_baselines (
  day TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('indianEquity', 'mutualFund')),
  isin TEXT NOT NULL, price TEXT NOT NULL, price_date TEXT NOT NULL, source TEXT NOT NULL,
  PRIMARY KEY (day, kind, isin)
);
