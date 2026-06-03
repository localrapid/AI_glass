// PDM microphone capture for AI_glass — Phase 2.
//
// Uses the legacy I2S driver (ESP32 Arduino core 2.0.x) in PDM RX mode to read
// the XIAO ESP32-S3 Sense onboard microphone. Produces raw 16 kHz / 16-bit mono
// PCM, which the iOS app wraps in a WAV header before sending to Whisper.

#include "audio_capture.h"

#include <driver/i2s.h>
#include "config.h"

static const i2s_port_t kPort = (i2s_port_t)AUDIO_I2S_PORT;
static bool g_ready = false;

bool audioSetup() {
  i2s_config_t cfg = {};
  cfg.mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX | I2S_MODE_PDM);
  cfg.sample_rate = AUDIO_SAMPLE_RATE;
  cfg.bits_per_sample = I2S_BITS_PER_SAMPLE_16BIT;
  cfg.channel_format = I2S_CHANNEL_FMT_ONLY_LEFT;     // mono
  cfg.communication_format = I2S_COMM_FORMAT_STAND_I2S;
  cfg.intr_alloc_flags = ESP_INTR_FLAG_LEVEL1;
  cfg.dma_buf_count = 8;
  cfg.dma_buf_len = 1024;
  cfg.use_apll = false;
  cfg.tx_desc_auto_clear = false;
  cfg.fixed_mclk = 0;

  if (i2s_driver_install(kPort, &cfg, 0, NULL) != ESP_OK) {
    Serial.println(F("[MIC] driver install failed"));
    return false;
  }

  i2s_pin_config_t pins = {};
  pins.bck_io_num   = I2S_PIN_NO_CHANGE;
  pins.ws_io_num    = AUDIO_PDM_CLK_PIN;   // PDM clock
  pins.data_out_num = I2S_PIN_NO_CHANGE;
  pins.data_in_num  = AUDIO_PDM_DATA_PIN;  // PDM data

  if (i2s_set_pin(kPort, &pins) != ESP_OK) {
    Serial.println(F("[MIC] set pin failed"));
    return false;
  }
  i2s_set_clk(kPort, AUDIO_SAMPLE_RATE, I2S_BITS_PER_SAMPLE_16BIT, I2S_CHANNEL_MONO);

  g_ready = true;
  Serial.println(F("[MIC] init OK"));
  return true;
}

uint8_t* audioRecord(uint8_t seconds, size_t* out_len) {
  *out_len = 0;
  if (!g_ready) return nullptr;
  if (seconds == 0) seconds = AUDIO_DEFAULT_SECONDS;
  if (seconds > AUDIO_MAX_SECONDS) seconds = AUDIO_MAX_SECONDS;

  const size_t total = (size_t)AUDIO_SAMPLE_RATE * (AUDIO_BITS_PER_SAMPLE / 8) * seconds;
  uint8_t* buf = (uint8_t*)ps_malloc(total);
  if (!buf) {
    Serial.println(F("[MIC] ps_malloc failed"));
    return nullptr;
  }

  // Discard the first DMA reads — the PDM mic outputs a click/settle on start.
  uint8_t warm[1024];
  size_t got = 0;
  for (int i = 0; i < 4; i++) i2s_read(kPort, warm, sizeof(warm), &got, pdMS_TO_TICKS(100));

  size_t filled = 0;
  while (filled < total) {
    size_t n = 0;
    esp_err_t err = i2s_read(kPort, buf + filled, total - filled, &n, portMAX_DELAY);
    if (err != ESP_OK) break;
    filled += n;
  }

  Serial.print(F("[MIC] recorded "));
  Serial.print(filled);
  Serial.print(F(" bytes ("));
  Serial.print(seconds);
  Serial.println(F("s)"));
  *out_len = filled;
  return buf;
}
