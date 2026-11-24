# Known Limitations

1. **Hardware In-Loop Testing During Development**:
   - PlatformIO firmware is verified via compilation and headless linting in this repository. Physical UART2 baud rate matching (256,000 baud) and GPIO resistor tolerances require on-device validation with the physical ESP32 and LD2410 sensor.
2. **Postgres pg_cron Sub-minute Resolution**:
   - Standard `pg_cron` natively supports 1-minute intervals (`* * * * *`). For the 10-second hackathon demo requirement, `run_rules()` is triggered either via a lightweight runner script / edge function / simulator loop during demo mode.
3. **Telegram Notifications (P1/P2 Scope)**:
   - Profile table supports `telegram_chat_id`, but external Telegram Bot API token dispatch is prioritized after core P0 web realtime push notifications.
4. **TLS Insecure Mode on ESP32 Development**:
   - The ESP32 firmware includes `client.setInsecure()` for local development HTTPS self-signed certificates or HTTP local edge functions. Production deployments must pin the Supabase CA root certificate.
