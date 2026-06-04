// BLE service / advertising implementation for AI_glass — Phase 1 step 5.
//
// Sets up the main service with four characteristics (Photo Data, Photo Control,
// Touch Event, Status) plus the standard Device Information service, then starts
// advertising under BLE_DEVICE_NAME.
//
// The notify-side helpers (touch / status) are wired through fully; the photo
// chunking path is left as a stub until Phase 1 step 7 brings in real JPEG data.

#include "ble_protocol.h"

#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#include "config.h"

namespace {

bool g_connected = false;

// Capture scheduling state, written from the BLE callback task and read from
// the main loop. 32-bit aligned scalars are atomic on the ESP32; `volatile`
// keeps the loop from caching them.
volatile unsigned long g_capture_interval_ms = (unsigned long)DEFAULT_PHOTO_INTERVAL_S * 1000UL;
volatile bool          g_capture_once        = false;
volatile uint8_t       g_audio_request_s     = 0;   // seconds to record, 0 = none

BLEServer*         g_server        = nullptr;
BLECharacteristic* g_photo_data    = nullptr;
BLECharacteristic* g_photo_control = nullptr;
BLECharacteristic* g_touch_event   = nullptr;
BLECharacteristic* g_status        = nullptr;
BLECharacteristic* g_audio_data    = nullptr;
BLECharacteristic* g_audio_control = nullptr;

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer*) override {
    g_connected = true;
    Serial.println(F("[BLE] central connected"));
  }
  void onDisconnect(BLEServer*) override {
    g_connected = false;
    Serial.println(F("[BLE] central disconnected, re-advertising"));
    BLEDevice::startAdvertising();
  }
};

class PhotoControlCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    std::string value = characteristic->getValue();
    if (value.empty()) return;
    int8_t cmd = static_cast<int8_t>(value[0]);
    Serial.print(F("[BLE] Photo Control write: "));
    Serial.println(cmd);

    // Phase 1 step 8 dispatch:
    //   -1            -> capture a single frame now
    //    0            -> stop auto-capture
    //    1..MAX_S     -> set auto-capture interval (seconds)
    if (cmd == -1) {
      g_capture_once = true;
    } else if (cmd == 0) {
      g_capture_interval_ms = 0;
    } else if (cmd >= MIN_PHOTO_INTERVAL_S && cmd <= MAX_PHOTO_INTERVAL_S) {
      g_capture_interval_ms = (unsigned long)cmd * 1000UL;
    }
  }
};

class AudioControlCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    std::string value = characteristic->getValue();
    if (value.empty()) return;
    uint8_t seconds = static_cast<uint8_t>(value[0]);
    if (seconds == 0) seconds = AUDIO_DEFAULT_SECONDS;
    if (seconds > AUDIO_MAX_SECONDS) seconds = AUDIO_MAX_SECONDS;
    g_audio_request_s = seconds;
    Serial.print(F("[BLE] Audio Control: record "));
    Serial.print(seconds);
    Serial.println(F("s"));
  }
};

void addDeviceInformationService(BLEServer* server) {
  BLEService* dis = server->createService(BLEUUID((uint16_t)0x180A));

  auto add = [&](uint16_t uuid, const char* value) {
    BLECharacteristic* c = dis->createCharacteristic(
      BLEUUID(uuid), BLECharacteristic::PROPERTY_READ);
    c->setValue(reinterpret_cast<uint8_t*>(const_cast<char*>(value)), strlen(value));
  };
  add(0x2A29, MANUFACTURER_NAME);   // Manufacturer Name String
  add(0x2A24, HARDWARE_NAME);       // Model Number String
  add(0x2A26, FIRMWARE_VERSION);    // Firmware Revision String

  dis->start();
}

}  // namespace

void bleSetup() {
  Serial.println(F("[BLE] init"));

  BLEDevice::init(BLE_DEVICE_NAME);

  // Request a large ATT MTU so a photo chunk fits in a single notify. iOS still
  // caps the negotiated value (often 185), which is why PHOTO_CHUNK_SIZE stays
  // under that floor — this just lets capable centrals go bigger.
  BLEDevice::setMTU(517);

  g_server = BLEDevice::createServer();
  g_server->setCallbacks(new ServerCallbacks());

  // Reserve enough attribute handles for all characteristics + their CCCDs.
  // The default (15) overflows once the audio characteristics are added, which
  // silently drops them — give plenty of headroom for future ones too.
  BLEService* service = g_server->createService(BLEUUID(BLE_SERVICE_UUID), 40);

  // Photo Data — READ + NOTIFY (chunked JPEG, implemented in step 7)
  g_photo_data = service->createCharacteristic(
      BLE_PHOTO_DATA_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  g_photo_data->addDescriptor(new BLE2902());

  // Photo Control — WRITE (capture command, dispatcher comes in step 8)
  g_photo_control = service->createCharacteristic(
      BLE_PHOTO_CONTROL_UUID,
      BLECharacteristic::PROPERTY_WRITE);
  g_photo_control->setCallbacks(new PhotoControlCallbacks());

  // Touch Event — NOTIFY only
  g_touch_event = service->createCharacteristic(
      BLE_TOUCH_EVENT_UUID,
      BLECharacteristic::PROPERTY_NOTIFY);
  g_touch_event->addDescriptor(new BLE2902());

  // Status — READ + NOTIFY (capture/error flags)
  g_status = service->createCharacteristic(
      BLE_STATUS_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  g_status->addDescriptor(new BLE2902());
  uint8_t initial_status = 0;
  g_status->setValue(&initial_status, 1);

  // Audio Data — READ + NOTIFY (chunked PCM, same wire format as photos)
  g_audio_data = service->createCharacteristic(
      BLE_AUDIO_DATA_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  g_audio_data->addDescriptor(new BLE2902());

  // Audio Control — WRITE (1 byte = seconds to record)
  g_audio_control = service->createCharacteristic(
      BLE_AUDIO_CONTROL_UUID,
      BLECharacteristic::PROPERTY_WRITE);
  g_audio_control->setCallbacks(new AudioControlCallbacks());

  service->start();

  addDeviceInformationService(g_server);

  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(BLE_SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->setMinPreferred(0x06);
  advertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println(F("[BLE] advertising as \"" BLE_DEVICE_NAME "\""));
}

bool bleIsConnected() {
  return g_connected;
}

unsigned long bleCaptureIntervalMs() {
  return g_capture_interval_ms;
}

bool bleConsumeCaptureOnce() {
  if (g_capture_once) {
    g_capture_once = false;
    return true;
  }
  return false;
}

// --- Notify helpers ---------------------------------------------------------

namespace {
// Stream a buffer over `ch` as counter-prefixed chunks, terminated by an empty
// PHOTO_EOF_MARKER packet. Shared by photo and audio paths.
//   [counter_LSB][counter_MSB][up to PHOTO_CHUNK_SIZE payload bytes]
uint16_t chunkSend(BLECharacteristic* ch, const uint8_t* data, size_t length) {
  uint8_t packet[PHOTO_HEADER_SIZE + PHOTO_CHUNK_SIZE];
  uint16_t counter = 0;
  for (size_t offset = 0; offset < length; offset += PHOTO_CHUNK_SIZE) {
    size_t chunk = length - offset;
    if (chunk > PHOTO_CHUNK_SIZE) chunk = PHOTO_CHUNK_SIZE;
    packet[0] = counter & 0xFF;
    packet[1] = (counter >> 8) & 0xFF;
    memcpy(packet + PHOTO_HEADER_SIZE, data + offset, chunk);
    ch->setValue(packet, PHOTO_HEADER_SIZE + chunk);
    ch->notify();
    counter++;
    delay(3);  // pace notifies so the controller TX buffer doesn't overflow
  }
  packet[0] = PHOTO_EOF_MARKER & 0xFF;
  packet[1] = (PHOTO_EOF_MARKER >> 8) & 0xFF;
  ch->setValue(packet, PHOTO_HEADER_SIZE);
  ch->notify();
  return counter;
}
}  // namespace

void blePhotoSend(const uint8_t* jpeg, size_t length) {
  if (!g_photo_data || !g_connected || !jpeg || length == 0) return;
  uint16_t chunks = chunkSend(g_photo_data, jpeg, length);
  Serial.print(F("[BLE] photo sent: "));
  Serial.print(length);
  Serial.print(F(" bytes in "));
  Serial.print(chunks);
  Serial.println(F(" chunks"));
}

void bleAudioSend(const uint8_t* pcm, size_t length) {
  if (!g_audio_data || !g_connected || !pcm || length == 0) return;
  uint16_t chunks = chunkSend(g_audio_data, pcm, length);
  Serial.print(F("[BLE] audio sent: "));
  Serial.print(length);
  Serial.print(F(" bytes in "));
  Serial.print(chunks);
  Serial.println(F(" chunks"));
}

uint8_t bleConsumeAudioRequest() {
  uint8_t s = g_audio_request_s;
  if (s) g_audio_request_s = 0;
  return s;
}

void bleTouchNotify(TouchEventType type, uint16_t duration_ms) {
  if (!g_touch_event || !g_connected) return;
  uint8_t payload[3];
  payload[0] = static_cast<uint8_t>(type);
  payload[1] = duration_ms & 0xFF;
  payload[2] = (duration_ms >> 8) & 0xFF;
  g_touch_event->setValue(payload, sizeof(payload));
  g_touch_event->notify();
}

void bleStatusUpdate(uint8_t flags) {
  if (!g_status) return;
  g_status->setValue(&flags, 1);
  if (g_connected) g_status->notify();
}
