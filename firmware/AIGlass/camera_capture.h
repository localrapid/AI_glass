#pragma once

#include <Arduino.h>
#include "esp_camera.h"

// Initialize the OV2640 with the pin map in camera_pins.h and the format
// constants in config.h. Returns true on success; false logs to Serial.
bool cameraSetup();

// Grab one JPEG. Returns nullptr on failure. The framebuffer is owned by the
// camera driver — callers MUST call cameraReleaseFrame() when done so PSRAM is
// reclaimed.
camera_fb_t* cameraCaptureFrame();

// Release a framebuffer obtained from cameraCaptureFrame().
void cameraReleaseFrame(camera_fb_t* fb);
