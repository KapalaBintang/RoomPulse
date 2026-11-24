#pragma once

// RoomPulse ESP32 Hardware Pin & Serial Configuration
// STACK 2026 Semifinal Prototype

// mmWave Radar (LD2410) UART2 Pin Configuration
// LD2410 default communication baud rate is 256,000 baud
#define RADAR_RX_PIN 16 // Connect to LD2410 TX pin
#define RADAR_TX_PIN 17 // Connect to LD2410 RX pin
#define RADAR_BAUD_RATE 256000

// Status Indicator LEDs (Active HIGH)
// NOTE ON CURRENT LIMITING RESISTORS:
// Always insert a 220 Ohm to 330 Ohm series resistor on each LED anode/cathode
// to protect ESP32 GPIOs from exceeding 12mA sink/source limits.
#define LED_GREEN_PIN  18 // Room is Free / Available
#define LED_YELLOW_PIN 19 // Room is Reserved / Confirm Pending / Warning / Unknown
#define LED_RED_PIN    21 // Room is Occupied / Active Booking

// Operational Parameters
#define TELEMETRY_INTERVAL_MS 5000 // Send telemetry every 5 seconds
#define STATE_POLL_INTERVAL_MS 5000 // Poll server LED state every 5 seconds
#define HTTP_TIMEOUT_MS 4000
#define MAX_FAILED_ATTEMPTS_BEFORE_UNKNOWN 2

// Test Mode: Set to 1 to enable verbose serial output of raw gate energies & distances
#define TEST_MODE 0
