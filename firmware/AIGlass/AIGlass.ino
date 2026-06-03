/*
 * AI_glass firmware — Phase 1 step 4 skeleton
 * Target board: Seeed XIAO ESP32-S3 Sense (esp32:esp32:XIAO_ESP32S3)
 *
 * Current step:
 *   Phase 2 (audio) — photos work as in Phase 1 (Photo Control schedules
 *   captures, streamed over Photo Data). Added on-demand audio: the app writes
 *   N seconds to Audio Control, the device records 16kHz PCM from the PDM mic
 *   and streams it over Audio Data. Touch input (step 9) still stubbed.
 *
 * See ../docs/FIRMWARE_DESIGN.md for the full plan.
 */

#include <Arduino.h>
#include <BLEDevice.h>     // declarations only; not started yet
#include <esp_camera.h>    // declarations only; not started yet

#include "config.h"
#include "camera_pins.h"
#include "ble_protocol.h"
#include "camera_capture.h"
#include "audio_capture.h"
#include "touch_input.h"

void setup() {
  Serial.begin(SERIAL_BAUD);
  delay(500);

  Serial.println();
  Serial.println(F("=================================="));
  Serial.println(F("AI_glass firmware booting"));
  Serial.print(F("  device : "));  Serial.println(BLE_DEVICE_NAME);
  Serial.print(F("  fw     : "));  Serial.println(FIRMWARE_VERSION);
  Serial.print(F("  board  : "));  Serial.println(HARDWARE_NAME);
  Serial.println(F("=================================="));

  pinMode(STATUS_LED_PIN, OUTPUT);
  digitalWrite(STATUS_LED_PIN, STATUS_LED_OFF);

  bleSetup();
  cameraSetup();
  audioSetup();
  // Phase 1 step 9: touchSetup();
}

void loop() {
  static unsigned long last_blink_ms   = 0;
  static unsigned long last_capture_ms = 0;
  static bool led_on = false;
  const unsigned long now = millis();

  // Heartbeat blink — non-blocking so capture / BLE work happen on time.
  const unsigned long blink_step = led_on ? 900 : 100;
  if (now - last_blink_ms >= blink_step) {
    last_blink_ms = now;
    led_on = !led_on;
    digitalWrite(STATUS_LED_PIN, led_on ? STATUS_LED_ON : STATUS_LED_OFF);
  }

  // Phase 1 step 8: capture only while connected, on the schedule set via
  // Photo Control. A `-1` single-shot fires immediately; interval 0 = paused.
  if (bleIsConnected()) {
    const unsigned long interval = bleCaptureIntervalMs();
    const bool once = bleConsumeCaptureOnce();
    const bool due  = once || (interval > 0 && now - last_capture_ms >= interval);
    if (due) {
      last_capture_ms = now;
      camera_fb_t* fb = cameraCaptureFrame();
      if (fb) {
        Serial.print(F("[CAM] captured "));
        Serial.print(fb->len);
        Serial.println(F(" bytes"));
        bleStatusUpdate(STATUS_CAPTURING);
        blePhotoSend(fb->buf, fb->len);
        bleStatusUpdate(0);
        cameraReleaseFrame(fb);
      }
    }
    // Phase 2: on-demand audio clip requested via Audio Control.
    const uint8_t rec_s = bleConsumeAudioRequest();
    if (rec_s > 0) {
      size_t len = 0;
      uint8_t* pcm = audioRecord(rec_s, &len);
      if (pcm) {
        if (len > 0) bleAudioSend(pcm, len);
        free(pcm);
      }
    }
  } else {
    // Drop any stale requests queued before disconnect.
    bleConsumeCaptureOnce();
    bleConsumeAudioRequest();
  }

  // Phase 1 step 9+: touchLoop();
}
