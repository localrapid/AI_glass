#pragma once

// === Identity ===
#define BLE_DEVICE_NAME           "AI_glass"
#define FIRMWARE_VERSION          "0.2.1-phase2-camoff"
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
// Phase 2 (audio)
#define BLE_AUDIO_DATA_UUID       "a17ec1a5-0000-4000-8000-000000000006"
#define BLE_AUDIO_CODEC_UUID      "a17ec1a5-0000-4000-8000-000000000007"
#define BLE_AUDIO_CONTROL_UUID    "a17ec1a5-0000-4000-8000-000000000008"

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
// After power-cycling the camera, discard a few frames so auto-exposure/gain
// settle before the kept shot (the OV2640 needs a moment after re-init).
#define CAMERA_WARMUP_FRAMES      3

// === Audio (Phase 2) — PDM mic on XIAO ESP32-S3 Sense ===
// On-demand short clips: the app writes N seconds to Audio Control, the device
// records 16kHz/16-bit mono PCM and streams it over Audio Data using the same
// counter-prefixed chunk format as photos (PHOTO_CHUNK_SIZE / EOF marker).
#define AUDIO_SAMPLE_RATE         16000
#define AUDIO_BITS_PER_SAMPLE     16
#define AUDIO_DEFAULT_SECONDS     5
#define AUDIO_MAX_SECONDS         30
#define AUDIO_I2S_PORT            0        // I2S_NUM_0 (camera uses LCD_CAM, no clash)
#define AUDIO_PDM_CLK_PIN         42       // XIAO ESP32-S3 Sense onboard PDM mic
#define AUDIO_PDM_DATA_PIN        41

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
