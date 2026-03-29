CREATE TABLE IF NOT EXISTS integration (
  provider TEXT PRIMARY KEY,
  refresh_token TEXT,
  updated_at TEXT
);
