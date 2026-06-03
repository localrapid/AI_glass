#pragma once

#include <Arduino.h>

// TTP223 capacitive touch input handler.
// Phase 1 step 9 implementation will wire an ISR on TOUCH_INPUT_PIN that
// classifies tap vs long-press by measuring the high-period and then calls
// bleTouchNotify() plus (for taps) triggers a single-shot photo capture.

void touchSetup();
void touchLoop();
