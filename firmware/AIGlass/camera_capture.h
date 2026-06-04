#pragma once

#include <Arduino.h>
#include "esp_camera.h"

// Power the OV2640 ON (esp_camera_init) with the pin map in camera_pins.h and
// the format constants in config.h. Returns true on success; false logs to
// Serial. On the XIAO Sense the PWDN pin isn't wired, so power saving between
// captures is done by deinit (cameraPowerOff), which stops the XCLK clock.
bool cameraPowerOn();

// Power the camera OFF (esp_camera_deinit) to cut idle current between shots.
void cameraPowerOff();

// Grab one JPEG. Returns nullptr on failure. The framebuffer is owned by the
// camera driver — callers MUST call cameraReleaseFrame() when done so PSRAM is
// reclaimed.
camera_fb_t* cameraCaptureFrame();

// Release a framebuffer obtained from cameraCaptureFrame().
void cameraReleaseFrame(camera_fb_t* fb);
