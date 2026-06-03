#pragma once

// === Identity ===
#define BLE_DEVICE_NAME           "AI_glass"
#define FIRMWARE_VERSION          "0.1.0-phase1-step8"
#define HARDWARE_NAME             "Seeed XIAO ESP32-S3 Sense"
#define MANUFACTURER_NAME         "AI_glass DIY"

// === BLE UUIDs ===
// Base group "a17ec1a5" reads loosely as "ai-glass". Regenerate with `uuidgen`
// once before shipping if a real fresh namespace is desired.
#define BLE_SERVICE_UUID          "a17ec1a5-0000-4000-8000-000000000001"
#define BLE_PHOTO_DATA_UUID       "a17ec1a5-0000-4000-8000-000000000002"
#define BLE_PHOTO_CONTROL_UUID    "a17ec1a5-0000-4000-8000-000000000003"
#define BLE_TOUCH_EVENT_UUID      "a17ec1a5-0000-4000-8000-000000000004"
#define BLE_STATUS_UUID           "a17ec1a5-0000-4000-8000-000000000005"
// Phase 2 (audio) — declared here so the namespace is consistent from day 1
#define BLE_AUDIO_DATA_UUID       "a17ec1a5-0000-4000-8000-000000000006"
#define BLE_AUDIO_CODEC_UUID      "a17ec1a5-0000-4000-8000-000000000007"

// === Photo protocol (OpenGlass-style counter-prefixed chunks) ===
// 180B payload + 2B counter = 182B notify, which fits inside iOS's commonly
// negotiated 185-byte ATT MTU (payload cap = MTU-3). bleSetup() also requests
// a 517 MTU so newer iPhones can negotiate larger frames; the iOS reassembler
// is length-independent either way.
#define PHOTO_CHUNK_SIZE          180      // JPEG payload bytes per BLE notify
#define PHOTO_HEADER_SIZE         2        // 2-byte frame counter prefix
#define PHOTO_EOF_MARKER          0xFFFF   // counter value signaling end-of-frame
#define DEFAULT_PHOTO_INTERVAL_S  15       // auto-capture interval at boot
#define MIN_PHOTO_INTERVAL_S      1
#define MAX_PHOTO_INTERVAL_S      120

// === Camera ===
#define CAMERA_FRAME_SIZE         FRAMESIZE_SVGA   // 800x600
#define CAMERA_JPEG_QUALITY       10               // 0 = best, 63 = worst
#define CAMERA_FB_COUNT           1
#define CAMERA_XCLK_FREQ_HZ       20000000

// === Touch input (TTP223 on XIAO D0 / GPIO1) ===
#define TOUCH_INPUT_PIN           1
#define TOUCH_TAP_MAX_MS          1000     // hold shorter than this = tap
#define TOUCH_LONGPRESS_MIN_MS    2000     // hold at-least this = long press
#define TOUCH_DEBOUNCE_MS         500

// === Status LED (XIAO ESP32-S3 user LED on GPIO21, active LOW) ===
#define STATUS_LED_PIN            21
#define STATUS_LED_ON             LOW
#define STATUS_LED_OFF            HIGH

// === Serial ===
#define SERIAL_BAUD               115200
