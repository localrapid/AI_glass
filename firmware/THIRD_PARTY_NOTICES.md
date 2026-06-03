# Third-Party Notices

This firmware is original work for the AI_glass project, but its design draws
on the following open-source projects. We acknowledge their authors and
licenses here.

---

## OpenGlass

- Repository: https://github.com/BasedHardware/OpenGlass
- License: MIT
- Use: design reference for BLE service layout, JPEG-over-BLE chunking
  protocol, and the choice of XIAO ESP32-S3 Sense as the target board.
  No source files are copied verbatim, but the wire format for photo
  transfer (2-byte frame counter prefix + `0xFFFF` EOF marker, 200-byte
  chunks) is intentionally interoperable.

MIT License text reproduced below as required:

```
MIT License

Copyright (c) 2024 Based Hardware

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF TORT, OR OTHERWISE, ARISING FROM, OUT OF
OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## Seeed Studio XIAO ESP32-S3 Sense — Camera pin map

- Source: https://wiki.seeedstudio.com/xiao_esp32s3_camera_usage/
- The GPIO assignments in `AIGlass/camera_pins.h` reflect the hardware-fixed
  routing on the XIAO ESP32-S3 Sense board. The values themselves are not
  copyrightable (functional facts about the hardware), but the documentation
  is published by Seeed Studio.

---

## Espressif Arduino-ESP32 core

- Repository: https://github.com/espressif/arduino-esp32
- License: LGPL-2.1 / Apache-2.0 (mixed, per file)
- Use: provides `BLEDevice.h`, `esp_camera.h`, and the build toolchain. The
  AI_glass firmware links against these as a normal user of the framework.
