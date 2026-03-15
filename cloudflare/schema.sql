CREATE TABLE IF NOT EXISTS snapshots (
  net_slug   TEXT PRIMARY KEY,
  data       TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
