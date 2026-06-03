#pragma once

#include <Arduino.h>

// PDM microphone capture for the XIAO ESP32-S3 Sense (Phase 2).
// Records 16 kHz / 16-bit mono PCM into a PSRAM buffer for on-demand clips.

// Initialize the I2S PDM RX driver with the pins in config.h. Returns true on
// success; false logs to Serial.
bool audioSetup();

// Record `seconds` of PCM into a freshly allocated PSRAM buffer. On success
// returns the buffer and sets *out_len to its size in bytes; the caller MUST
// free() it. Returns nullptr on failure.
uint8_t* audioRecord(uint8_t seconds, size_t* out_len);
