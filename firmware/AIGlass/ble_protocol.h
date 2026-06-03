#pragma once

#include <Arduino.h>

// BLE service / characteristic setup and notification helpers.
// Implementation is added in Phase 1 step 5 onwards. This header declares the
// API surface so AIGlass.ino can compile against it from the start.

void bleSetup();
bool bleIsConnected();

// Photo data path — call from the camera path after a JPEG is captured.
// Chunks the buffer into PHOTO_CHUNK_SIZE BLE notify packets with a 2-byte
// counter prefix, terminated by a PHOTO_EOF_MARKER packet.
void blePhotoSend(const uint8_t* jpeg, size_t length);

// Audio data path (Phase 2). Streams PCM over Audio Data using the same
// counter-prefixed chunk format as photos. The app reassembles and wraps it
// in a WAV header. bleConsumeAudioRequest() returns the requested clip length
// in seconds once after an Audio Control write, else 0.
void bleAudioSend(const uint8_t* pcm, size_t length);
uint8_t bleConsumeAudioRequest();

// Touch events fire on TTP223 rising edge (configured in touch_input).
enum TouchEventType : uint8_t {
  TOUCH_EVENT_TAP        = 0x01,
  TOUCH_EVENT_LONG_PRESS = 0x02,
};
void bleTouchNotify(TouchEventType type, uint16_t duration_ms);

// Status flags pushed via BLE_STATUS_UUID notify.
enum StatusFlags : uint8_t {
  STATUS_CAPTURING   = 1 << 0,
  STATUS_LOW_BATTERY = 1 << 1,
  STATUS_ERROR       = 1 << 2,
};
void bleStatusUpdate(uint8_t flags);

// Capture scheduling driven by Photo Control writes (Phase 1 step 8).
// bleCaptureIntervalMs() returns the current auto-capture interval in ms, or 0
// when auto-capture is stopped. bleConsumeCaptureOnce() returns true exactly
// once after a single-shot (`-1`) command was received, then clears the flag.
unsigned long bleCaptureIntervalMs();
bool bleConsumeCaptureOnce();
