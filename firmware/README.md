# AI_glass Firmware

Target board: **Seeed XIAO ESP32-S3 Sense**
Toolchain: **arduino-cli + ESP32 core 2.0.17**

This directory contains the firmware sketch ([AIGlass/](AIGlass/)). The companion design document is [../docs/FIRMWARE_DESIGN.md](../docs/FIRMWARE_DESIGN.md).

## Current state

Phase 1 step 8 — **Photo Control drives capture**. The sketch boots, advertises as `AI_glass`, requests a 517 ATT MTU, and initializes the OV2640. While a central is connected it captures on the interval set via the Photo Control characteristic (`-1` = single shot, `0` = stop, `1..120` = seconds) and chunks each JPEG out over Photo Data (180-byte payloads, 2-byte counter, `0xFFFF` end marker). The companion iOS app (`../ios_app/AIGlass`) reassembles and displays these frames on a physical iPhone and can caption them via Claude. TTP223 touch input (step 9) is unwired — the app's single-shot button stands in for manual capture.

## One-time toolchain setup

### Windows (PowerShell)

```powershell
winget install ArduinoSA.CLI

arduino-cli config init
arduino-cli config add board_manager.additional_urls `
  https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
arduino-cli core update-index
arduino-cli core install esp32:esp32@2.0.17

arduino-cli board list   # XIAO should show up on COMxx
```

### macOS (Homebrew)

```bash
brew install arduino-cli

arduino-cli config init
arduino-cli config add board_manager.additional_urls \
  https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
arduino-cli core update-index
arduino-cli core install esp32:esp32@2.0.17

arduino-cli board list   # XIAO appears as /dev/cu.usbmodemXXXX
```

`esp_camera` and the BLE libraries ship with the ESP32 core — no separate library install is needed for the current sketch. Opus / I2S audio libraries are added later when Phase 2 audio is implemented.

## Build (no board required)

```powershell
arduino-cli compile `
  --fqbn esp32:esp32:XIAO_ESP32S3:PSRAM=opi,PartitionScheme=default_8MB `
  AIGlass
```

A successful `Sketch uses ... bytes` line is the goal for Phase 1 step 4 — that confirms the toolchain is set up and the project structure compiles.

## Upload (board required)

Replace `COM5` with the actual port shown by `arduino-cli board list`.

```powershell
arduino-cli upload `
  -p COM5 `
  --fqbn esp32:esp32:XIAO_ESP32S3:PSRAM=opi,PartitionScheme=default_8MB `
  AIGlass
```

To watch Serial output (115200 baud):

```powershell
arduino-cli monitor -p COM5 -c baudrate=115200
```

## File layout

```
firmware/
├── AIGlass/
│   ├── AIGlass.ino       # main sketch (setup / loop)
│   ├── config.h          # all UUIDs, GPIO pins, intervals, thresholds
│   ├── camera_pins.h     # XIAO ESP32-S3 Sense OV2640 pin map
│   ├── ble_protocol.h    # BLE API declarations (impl Phase 1 step 5+)
│   └── touch_input.h     # TTP223 API declarations (impl Phase 1 step 9)
├── README.md             # this file
└── THIRD_PARTY_NOTICES.md
```

## Next steps after parts arrive

The build order is enumerated in `../docs/FIRMWARE_DESIGN.md` §8. Summary:

| Step | What | Hardware needed |
|------|------|---|
| 5 | BLE advertising visible from `nRF Connect` on iPhone | XIAO board |
| 6 | Single camera capture, JPEG size printed to Serial | XIAO + USB cable |
| 7 | Photo notify chunks reach iPhone scanner | XIAO + iPhone |
| 8 | Photo Control write triggers periodic capture | + iPhone app |
| 9 | TTP223 short/long press → Touch Event notify | + TTP223 sensor |
