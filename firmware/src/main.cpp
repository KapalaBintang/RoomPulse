#include <Arduino.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <ArduinoJson.h>
#include <ld2410.h>

#include "config.h"

// If secrets.h exists, include it; otherwise fallback to defaults for build verification
#if __has_include("secrets.h")
    #include "secrets.h"
#else
    #define WIFI_SSID "Demo_WiFi"
    #define WIFI_PASS "Demo_Pass"
    #define API_BASE_URL "http://127.0.0.1:54321/functions/v1"
    #define DEVICE_ID "device-room-101"
    #define DEVICE_KEY "dev_key_room_101_secret"
#endif

ld2410 radar;
HardwareSerial RadarSerial(2); // UART2

unsigned long lastTelemetryMs = 0;
unsigned long lastStatePollMs = 0;
unsigned long lastBlinkMs = 0;
bool yellowBlinkState = false;

int consecutiveHttpFailures = 0;
enum LedColor { COLOR_GREEN, COLOR_YELLOW, COLOR_RED, COLOR_UNKNOWN };
LedColor currentLedState = COLOR_UNKNOWN;

void setLeds(bool green, bool yellow, bool red) {
    digitalWrite(LED_GREEN_PIN, green ? HIGH : LOW);
    digitalWrite(LED_YELLOW_PIN, yellow ? HIGH : LOW);
    digitalWrite(LED_RED_PIN, red ? HIGH : LOW);
}

void applyLedColor(LedColor color) {
    switch (color) {
        case COLOR_GREEN:
            setLeds(true, false, false);
            break;
        case COLOR_YELLOW:
            setLeds(false, true, false);
            break;
        case COLOR_RED:
            setLeds(false, false, true);
            break;
        case COLOR_UNKNOWN:
        default:
            // Slow yellow blink handled in loop; turn green and red off
            digitalWrite(LED_GREEN_PIN, LOW);
            digitalWrite(LED_RED_PIN, LOW);
            break;
    }
}

void connectWifi() {
    if (WiFi.status() == WL_CONNECTED) return;

    Serial.printf("[WiFi] Connecting to %s...\n", WIFI_SSID);
    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASS);

    unsigned long start = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - start < 10000) {
        delay(500);
        Serial.print(".");
    }

    if (WiFi.status() == WL_CONNECTED) {
        Serial.printf("\n[WiFi] Connected! IP: %s\n", WiFi.localIP().toString().c_str());
    } else {
        Serial.println("\n[WiFi] Connection failed. Will retry in loop.");
    }
}

bool sendTelemetry(bool presence, bool moving, bool stationary,
                   int movingEnergy, int staticEnergy, int distanceCm) {
    if (WiFi.status() != WL_CONNECTED) return false;

    HTTPClient http;
    String endpoint = String(API_BASE_URL) + "/device-telemetry";

    // TODO: For production, load root CA certificate via secureClient.setCACert().
    // Using plain HTTP for local edge functions or setInsecure() for HTTPS local testing.
    WiFiClient client;
    http.begin(client, endpoint);
    http.setTimeout(HTTP_TIMEOUT_MS);
    http.addHeader("Content-Type", "application/json");
    http.addHeader("x-device-key", DEVICE_KEY);

    StaticJsonDocument<256> doc;
    doc["device_id"] = DEVICE_ID;
    doc["presence"] = presence;
    doc["moving"] = moving;
    doc["stationary"] = stationary;
    doc["moving_energy"] = movingEnergy;
    doc["static_energy"] = staticEnergy;
    doc["distance_cm"] = distanceCm;
    doc["source"] = "device";

    String requestBody;
    serializeJson(doc, requestBody);

    int httpCode = http.POST(requestBody);
    bool success = false;

    if (httpCode == HTTP_CODE_OK || httpCode == 201) {
        consecutiveHttpFailures = 0;
        success = true;
    } else {
        Serial.printf("[Telemetry] HTTP POST failed, code: %d, error: %s\n",
                      httpCode, http.errorToString(httpCode).c_str());
        consecutiveHttpFailures++;
    }

    http.end();
    return success;
}

bool pollDeviceState() {
    if (WiFi.status() != WL_CONNECTED) {
        consecutiveHttpFailures++;
        return false;
    }

    HTTPClient http;
    String endpoint = String(API_BASE_URL) + "/device-state?device_id=" + String(DEVICE_ID);

    WiFiClient client;
    http.begin(client, endpoint);
    http.setTimeout(HTTP_TIMEOUT_MS);
    http.addHeader("x-device-key", DEVICE_KEY);

    int httpCode = http.GET();
    bool success = false;

    if (httpCode == HTTP_CODE_OK) {
        String payload = http.getString();
        StaticJsonDocument<256> doc;
        DeserializationError error = deserializeJson(doc, payload);

        if (!error) {
            const char* ledStr = doc["led"] | "unknown";
            if (strcmp(ledStr, "green") == 0) {
                currentLedState = COLOR_GREEN;
            } else if (strcmp(ledStr, "yellow") == 0) {
                currentLedState = COLOR_YELLOW;
            } else if (strcmp(ledStr, "red") == 0) {
                currentLedState = COLOR_RED;
            } else {
                currentLedState = COLOR_UNKNOWN;
            }
            consecutiveHttpFailures = 0;
            success = true;
        }
    } else {
        Serial.printf("[State] HTTP GET failed, code: %d\n", httpCode);
        consecutiveHttpFailures++;
    }

    http.end();
    return success;
}

void setup() {
    Serial.begin(115200);
    delay(1000);
    Serial.println("\n==============================================");
    Serial.println("  RoomPulse ESP32 mmWave Presence Firmware    ");
    Serial.println("  STACK 2026 Semifinal Prototype              ");
    Serial.println("==============================================");

    // Initialize LED pins
    pinMode(LED_GREEN_PIN, OUTPUT);
    pinMode(LED_YELLOW_PIN, OUTPUT);
    pinMode(LED_RED_PIN, OUTPUT);
    setLeds(false, false, false);

    // Start UART2 for LD2410 radar
    RadarSerial.begin(RADAR_BAUD_RATE, SERIAL_8N1, RADAR_RX_PIN, RADAR_TX_PIN);
    radar.begin(RadarSerial);

    Serial.println("[Radar] Connecting to LD2410 on UART2...");
    if (radar.isConnected()) {
        Serial.println("[Radar] LD2410 successfully initialized!");
    } else {
        Serial.println("[Radar] LD2410 not detected yet; listening on serial port.");
    }

    connectWifi();
}

void loop() {
    unsigned long now = millis();

    // Reconnect Wi-Fi with backoff if disconnected
    if (WiFi.status() != WL_CONNECTED) {
        static unsigned long lastWifiRetry = 0;
        if (now - lastWifiRetry > 10000) {
            lastWifiRetry = now;
            connectWifi();
        }
    }

    // Safety rule: if 2 or more consecutive failures, force COLOR_UNKNOWN (never hold stale green!)
    if (consecutiveHttpFailures >= MAX_FAILED_ATTEMPTS_BEFORE_UNKNOWN) {
        currentLedState = COLOR_UNKNOWN;
    }

    // Process slow blinking yellow for COLOR_UNKNOWN state (500ms toggle)
    if (currentLedState == COLOR_UNKNOWN) {
        if (now - lastBlinkMs >= 500) {
            lastBlinkMs = now;
            yellowBlinkState = !yellowBlinkState;
            digitalWrite(LED_YELLOW_PIN, yellowBlinkState ? HIGH : LOW);
        }
    } else {
        applyLedColor(currentLedState);
    }

    // Read radar frame
    radar.read();
    bool presence = radar.presenceDetected();
    bool moving = radar.movingTargetDetected();
    bool stationary = radar.stationaryTargetDetected();
    int movingEnergy = radar.movingTargetEnergy();
    int staticEnergy = radar.stationaryTargetEnergy();
    int distanceCm = radar.stationaryTargetDistance();

#if TEST_MODE == 1
    static unsigned long lastTestPrint = 0;
    if (now - lastTestPrint > 1000) {
        lastTestPrint = now;
        Serial.printf("[TEST_MODE] Presence: %d | Moving: %d (Eng: %d) | Static: %d (Eng: %d) | Dist: %d cm\n",
                      presence, moving, movingEnergy, stationary, staticEnergy, distanceCm);
    }
#endif

    // Periodic telemetry transmission (acts as heartbeat)
    if (now - lastTelemetryMs >= TELEMETRY_INTERVAL_MS) {
        lastTelemetryMs = now;
        sendTelemetry(presence, moving, stationary, movingEnergy, staticEnergy, distanceCm);
    }

    // Periodic state polling
    if (now - lastStatePollMs >= STATE_POLL_INTERVAL_MS) {
        lastStatePollMs = now;
        pollDeviceState();
    }

    delay(20);
}
