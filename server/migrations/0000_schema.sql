-- Auth Tables
CREATE TABLE IF NOT EXISTS "user" (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  google_id TEXT NOT NULL UNIQUE,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS session (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  expires_at DATETIME NOT NULL,
  FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS oauth_token (
  user_id TEXT PRIMARY KEY,
  access_token TEXT NOT NULL,
  refresh_token TEXT,
  expires_at DATETIME NOT NULL,
  FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE CASCADE
);

-- Core App Tables
CREATE TABLE IF NOT EXISTS task (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  deadline DATETIME,
  estimated_hours REAL NOT NULL,
  energy_cost TEXT NOT NULL,
  requires_transit BOOLEAN NOT NULL DEFAULT 0,
  transit_minutes INTEGER NOT NULL DEFAULT 0,
  recurrence TEXT NOT NULL DEFAULT 'none',
  category TEXT NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  completed_at DATETIME
);

CREATE TABLE IF NOT EXISTS schedule (
  date TEXT PRIMARY KEY, -- YYYY-MM-DD formatting
  energy_level INTEGER,
  mood INTEGER,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS schedule_block (
  id TEXT PRIMARY KEY,
  schedule_date TEXT NOT NULL,
  task_id TEXT,
  start_time DATETIME NOT NULL,
  end_time DATETIME NOT NULL,
  type TEXT NOT NULL,
  notes TEXT,
  FOREIGN KEY (schedule_date) REFERENCES schedule(date) ON DELETE CASCADE,
  FOREIGN KEY (task_id) REFERENCES task(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS checkin (
  date TEXT PRIMARY KEY,
  mood INTEGER NOT NULL,
  energy INTEGER NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS calendar_cache (
  id TEXT PRIMARY KEY,
  event_id TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  start_time DATETIME NOT NULL,
  end_time DATETIME NOT NULL,
  fetched_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS user_settings (
  id TEXT PRIMARY KEY,
  settings_json TEXT NOT NULL
);
