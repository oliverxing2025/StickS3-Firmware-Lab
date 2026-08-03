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

## Optional bundled ESP32-S3 QEMU runtime

Release builds may include Espressif's Xtensa QEMU
`esp-develop-9.2.2-20250817` as a separate child-process
executable under `Contents/Resources/Emulation/`. QEMU is licensed under
GPL-2.0-only; its source and license information are available from
https://github.com/espressif/qemu. The build script does not link QEMU into the
Swift executable. The GPL-2.0 text is included at
`Vendor/Licenses/Runtime/GPL-2.0-only.txt`.

The macOS runtime bundle can also carry QEMU's dynamically linked libraries,
including pixman 0.46.4 (MIT), libgcrypt 1.12.2 (LGPL-2.1-or-later and
GPL-2.0-or-later), libgpg-error 1.61 (LGPL-2.1-or-later), SDL2 compatibility
2.32.70 (Zlib), GLib 2.88.3 (LGPL-2.1-or-later), PCRE2 10.47
(BSD-3-Clause), and gettext 1.0 (GPL-3.0-or-later and LGPL-2.1-or-later).
The matching standard license texts are included under
`Vendor/Licenses/Runtime/`.

Every public binary release must also attach the source bundle produced by
`scripts/prepare-third-party-sources.sh`. See
`docs/THIRD_PARTY_SOURCE_DISTRIBUTION.md` for the reviewed versions and release
procedure.
