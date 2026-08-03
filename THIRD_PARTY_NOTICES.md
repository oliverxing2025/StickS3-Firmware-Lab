# Third-party notices

## Firmware adapter snapshots

The files under `Vendor/Firmware/` are the minimal source snapshots required
by the macOS simulator adapters. They are not complete ESP-IDF firmware
distributions.

- VibeStick-Codex: MIT; based on VibeStick by Gary Zhang. See
  `Vendor/Licenses/VibeStick-Codex-LICENSE` and
  `Vendor/Licenses/VibeStick-Codex-NOTICE`.
- VibeStick-Fruit-Machine: MIT. See
  `Vendor/Licenses/VibeStick-Fruit-Machine-LICENSE`.
- VibeStick-Hourglass, VibeStick-Hourglass-Liquid, and
  VibeStick-Neon-Brick-Pulse adapter snapshots: Copyright (c) 2026 Oliver
  Xing, distributed under this repository's MIT License. The Liquid project
  license and notice are additionally preserved in `Vendor/Licenses/`.

## LVGL

`Sources/LVGLHost/` is a source snapshot of LVGL 9.2.0.

Copyright (c) 2021 LVGL Kft. Licensed under the MIT License. See
`Vendor/Licenses/LVGL-LICENSE`.

## Montserrat

LVGL's generated `lv_font_montserrat_*.c` font data is derived from the
Montserrat font family and remains available under the SIL Open Font License
1.1. See `Vendor/Licenses/Montserrat-OFL-1.1`.

## Components carried inside LVGL

Some optional LVGL library sources include their own notices or license files
within their source directories. The simulator build disables optional
FreeType and file-backed font assets and does not redistribute an Arial font
binary.
