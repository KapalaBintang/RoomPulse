# Hardware Wiring Guide & Testing Checklist

## 1. Components
1. **ESP32 DevKit v1** (30-pin or 38-pin module)
2. **HLK-LD2410 24GHz mmWave Human Presence Radar Sensor**
3. **Status Indicator LEDs**:
   - 1x Green LED (Available)
   - 1x Yellow LED (Reserved / Confirming / Unknown)
   - 1x Red LED (Occupied / Active Booking)
4. **Resistors**:
   - 3x 220Ω to 330Ω 1/4W resistors (1 for each LED)
5. **Jumper Wires & Breadboard**

---

## 2. Wiring Schematic

```
ESP32 DevKit v1             LD2410 mmWave Radar
-------------------------------------------------
5V / VIN       -----------> VCC (5V recommended)
GND            -----------> GND
GPIO 16 (RX2)  <----------- TX
GPIO 17 (TX2)  -----------> RX

ESP32 GPIOs                 Status LEDs
-------------------------------------------------
GPIO 18        ---> [220Ω Resistor] ---> Green LED Anode (+) ---> GND
GPIO 19        ---> [220Ω Resistor] ---> Yellow LED Anode (+) ---> GND
GPIO 21        ---> [220Ω Resistor] ---> Red LED Anode (+) ---> GND
```

> [!WARNING]
> Always insert a current-limiting resistor (220Ω to 330Ω) between each ESP32 GPIO pin and the LED anode. Directly connecting an LED without a resistor will damage the GPIO driver.

---

## 3. Hardware Test Checklist

- [ ] **Power Supply**: Measure 5V on VIN pin; ensure power supply can source at least 500mA peak during Wi-Fi bursts.
- [ ] **UART Communication**:
  - Verify LD2410 baud rate matches `256000` baud in `config.h`.
  - Check Serial Monitor at 115200 baud for `[Radar] LD2410 successfully initialized!`.
- [ ] **Presence Sensitivity Validation**:
  - Enable `TEST_MODE 1` in `config.h`.
  - Sit quietly 1.5 meters away: ensure `stationaryTargetEnergy` registers > 40.
  - Vacate room: ensure energy drops to 0 within 5 seconds.
- [ ] **Fail-Safe Offline Blink**:
  - Disconnect Wi-Fi access point.
  - Verify that after 2 failed HTTP requests, LEDs switch to slow-blinking Yellow (never holding stale Green).
