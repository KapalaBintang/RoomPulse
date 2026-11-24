# AI Usage Log

## Tool & Model
- **Assistant**: Antigravity (Powered by Google Gemini 3.8 Flash)
- **Role**: Senior Full-Stack and Embedded Systems Engineer

## Material AI Assistance
1. **Architecture & Schema Design**:
   - Automated creation of PostgreSQL migration with conditional `btree_gist` exclusion constraint.
   - Design of idempotent `run_rules()` rule engine using `SELECT ... FOR UPDATE SKIP LOCKED`.
2. **Edge Function & Simulator Implementation**:
   - Implementation of SHA-256 hashed API key authentication.
   - Creation of scenario-driven CLI sensor simulator (`empty`, `present`, `present-then-leave`, `flaky`, `offline`).
3. **Firmware Scaffolding**:
   - ESP32 Arduino / PlatformIO structure integrating `ncmreynolds/ld2410` UART library and LED indicator state machine.
4. **Web UI Development**:
   - Responsive mobile-first React + Tailwind CSS dashboard with Supabase Realtime bindings and Asia/Jakarta timezone formatting.

## Human Review Points
- Database constraints and safety rules reviewed for deadlocks and offline fail-safe behavior.
- Validation of simulated data indicators across all UI views and simulator outputs.
- Verification of zero committed secrets (`.env.example` vs `.env.local`).
