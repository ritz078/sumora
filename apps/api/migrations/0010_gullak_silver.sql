ALTER TABLE gullak_checkpoints ADD COLUMN silver_grams TEXT;
ALTER TABLE gullak_checkpoints ADD COLUMN opening_silver_grams TEXT;
ALTER TABLE gullak_imports ADD COLUMN parser_version INTEGER NOT NULL DEFAULT 1;
