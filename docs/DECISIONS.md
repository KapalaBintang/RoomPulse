# Architecture & Technical Decisions

## 1. Exclusion Constraint for Overlapping Bookings
- **Decision**: Used PostgreSQL `btree_gist` extension with a conditional exclusion constraint:
  `EXCLUDE USING gist (room_id WITH =, tstzrange(start_time, end_time, '[)') WITH &&) WHERE (status IN ('reserved', 'confirm_pending', 'active'))`
- **Reason**: Guarantees zero double-booking races at the database engine level, even under concurrent HTTP requests, while automatically allowing cancelled, released, completed, or expired bookings to overlap without manual cleanup.

## 2. Sensor Ingestion & Device Authentication
- **Decision**: Header `x-device-key` is verified against `devices.api_key_hash` using `encode(digest(key, 'sha256'), 'hex')`.
- **Reason**: Plaintext device keys are never stored in the database. Compromising a read-only database dump does not expose device credentials.

## 3. Simulator vs Physical Device Distinction
- **Decision**: A designated simulator API key (`sim_key_default_dev`) is supported in addition to device keys. When telemetry is submitted with this simulator key or `source: 'simulator'`, the database stores `source = 'simulator'`.
- **Reason**: Strict compliance with the honesty rule: the web frontend checks the room's latest reading and clearly badges "SIMULATED SENSOR DATA".

## 4. Safety First for Sensor Offline
- **Decision**: If a room's sensor hasn't reported within `offline_threshold_seconds` (default 120s, or 30s in demo mode), the booking is NEVER released for no-show. The rule engine logs `skipped_sensor_offline` once per offline window.
- **Reason**: Hardware failure, battery drain, or network dropout must never penalize students or eject active occupants.

## 5. Cron Scheduling Frequency
- **Decision**: In Supabase local development, `run_rules()` is designed to run via `pg_cron` (per minute) and can be triggered on demand or on 5-second intervals via a dedicated runner / Edge Function / simulator tick to allow instant hackathon demo feedback.
