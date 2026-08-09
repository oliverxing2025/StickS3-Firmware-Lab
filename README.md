<div align="center">
  <h1>StickS3 Firmware Lab</h1>
  <p><strong>Native macOS firmware lab for M5Stack StickS3 source projects</strong></p>
  <p>
    Build compatible StickS3 source projects in a private copy and bring their<br>
    display, physical buttons, and BMI270 pose input into one macOS lab.
  </p>
  <p>
    <a href="#overview">Overview</a> ·
    <a href="#v010-beta-public-test">v0.1.0 Beta</a> ·
    <a href="#sticks3-source-project-compatibility">Compatibility</a> ·
    <a href="#complete-controls">Controls</a> ·
    <a href="#installation">Install</a> ·
    <a href="#testing-status-and-windows-support">Support</a> ·
    <a href="#build">Build</a> ·
    <a href="README.zh-CN.md">简体中文</a>
  </p>
  <p>
    <img alt="Platform: macOS 26+" src="https://img.shields.io/badge/platform-macOS%2026%2B-111111">
    <img alt="Architecture: Apple Silicon" src="https://img.shields.io/badge/architecture-Apple%20Silicon-5A5A5A">
    <img alt="Swift: 6.2+" src="https://img.shields.io/badge/Swift-6.2%2B-F05138">
    <img alt="Version: 0.1.0 Beta" src="https://img.shields.io/badge/version-0.1.0--beta-2F80ED">
    <img alt="Mode: local first" src="https://img.shields.io/badge/mode-local--first-2E8B57">
  </p>
</div>

## v0.1.0 Beta public test

**Release date:** August 9, 2026

The source code is open for public beta testing under the MIT License. Download
the current macOS build and its checksum from the
[v0.1.0 Beta release](https://github.com/oliverxing2025/StickS3-Firmware-Lab/releases/tag/v0.1.0-beta),
or build it locally from this tag. Please report reproducible issues through
[GitHub Issues](https://github.com/oliverxing2025/StickS3-Firmware-Lab/issues).

- **Source-project simulation:** ESP-IDF, PlatformIO, and Arduino source
  projects have completed end-to-end build, display, button, and BMI270 tests.
- **Whole-device pose simulation:** portrait, left 90°, right 90°, and upside
  down rotate the body, display, and physical buttons together.
- **Fixed desktop viewport:** the application does not scroll horizontally or
  vertically; the complete control surface stays in one window.
- **Safe project reload:** refresh an imported source project without modifying
  its original files.
- **Hardware-aware adaptation:** detect common display, button, and BMI270
  mappings from source, with local calibration when a project is ambiguous.
- **Faster iteration:** reuse a private build only while both source and adapter
  inputs remain unchanged.

## Overview

<div align="center">
  <img src="assets/screenshots/sticks3-firmware-lab-brand.png" alt="StickS3 Firmware Lab and XiaoAo Technology brand artwork" width="520">
</div>

StickS3 Firmware Lab is a native macOS environment for importing, running,
and interacting with StickS3 firmware projects in a physical-device shell.

| | Capability | What it adds |
| --- | --- | --- |
| **01** | Source-project import | Adds compatible StickS3 source projects to one local catalog, identifies their build system, and checks simulation compatibility. |
| **02** | Normal display and controls | Connects compatible source projects to their firmware display, both physical buttons, and BMI270 pose input. |
| **03** | Hardware detection and calibration | Detects common display, button, and BMI270 mappings; stores source-bound calibration locally when needed. |
| **04** | Safe reload and build cache | Rebuilds changed source in a private copy and reuses only a matching cached result. |
| **05** | Local-first data | Keeps imported paths, settings, and test data on the Mac rather than uploading them to a service. |

> [!NOTE]
> This application complements real-device testing. Display color, physical
> sensor noise, ES8311 response, ESP32 memory and task scheduling, OTA metadata,
> partitions, and flash safety still require a physical StickS3.

## Device experience

- Choose imported firmware from one shared catalog.
- Switch between the readable default scale and a physical-size reference.
- Rotate the complete virtual device to four supported poses.
- Drive X, Y, and Z gravity independently with the control console.
- Trigger side-to-side and up/down shake gestures that return to the previous
  gravity pose.
- Trigger single, double, triple, quadruple, and long presses for both buttons.
- Adjust battery, charging, audio, brightness, and refresh-rate state when the
  current firmware supports those controls.
- Pause simulation or restart the current firmware without restarting the app.
- Inspect firmware capacity and application-image resource usage.
- View reload progress and logs.
- Inspect automatic hardware detection and calibrate ambiguous sensor axes,
  buttons, or display rotation without changing firmware source.
- Connect compatible firmware to an explicitly running loopback data service
  on the same Mac; remote and LAN requests are rejected.

<div align="center">
  <img src="assets/screenshots/landscape-control-console.png" alt="Firmware running in landscape pose with virtual motion and device controls" width="1000">
</div>

## StickS3 source-project compatibility

The application recognizes common StickS3 firmware project layouts. It can
import an ESP-IDF project root, a `firmware/sticks3` directory, a
PlatformIO/Arduino project containing `platformio.ini`, or an Arduino project
containing an `.ino` sketch, then manage it from the shared firmware catalog.

The app builds in a private copy outside the imported project and connects the
display, both physical buttons, and BMI270 pose input for common StickS3
firmware based on M5Unified/M5GFX. QEMU ships with the app. Source projects
require either [PlatformIO Core](https://docs.platformio.org/en/latest/core/installation/methods/installer-script.html)
or [ESP-IDF Installation Manager](https://docs.espressif.com/projects/idf-im-ui/en/latest/),
depending on project type. ESP-IDF is optional for the application as a whole,
but required when an imported project uses ESP-IDF. The app provides the same
official download links and does not require Homebrew.

This release focuses on normal firmware display and controls. It does not
simulate Wi-Fi, Bluetooth, cloud services, USB, or ULP programs. Projects that
access those peripherals directly, use custom display drivers, or bypass
M5Unified/M5GFX may still need compatibility work. This product does not import
precompiled `.bin` files from M5Burner or other sources. Bundled QEMU is only
an internal execution backend for adapted source-build outputs.

Compatible firmware may use the host data channel only for HTTP(S) services
running on the same Mac. The app rejects remote and LAN destinations; this
loopback bridge does not provide general network access to simulated firmware.

## System requirements

| Item | Requirement |
| --- | --- |
| Mac | Apple Silicon |
| Operating system | macOS 26 or later |
| Source build | Xcode 26 command-line tools and Swift 6.2 or later |
| Display | Fixed application window; no horizontal or vertical page scrolling |
| QEMU | Included with the app; no separate install required |
| PlatformIO | Required for Arduino/PlatformIO source projects; the app provides an official download link |
| ESP-IDF | Required when importing ESP-IDF source projects; not needed for Arduino/PlatformIO projects |
| Network | Required to install build tools and new project dependencies; cached components are reused |

## Testing status and Windows support

> [!IMPORTANT]
> This app is developed independently, so the available test platforms are
> limited and complete compatibility testing takes considerable time. The beta
> has not yet undergone repeated validation across multiple Mac models, macOS
> versions, and hardware configurations. Thank you for your understanding if
> you encounter a problem. Please report reproducible issues through
> [GitHub Issues](https://github.com/oliverxing2025/StickS3-Firmware-Lab/issues).
> The app will continue to improve in response to real-world feedback. Issue
> reports, testing notes, documentation fixes, and code contributions are all
> welcome so the community can help improve StickS3 Firmware Lab together.

> [!NOTE]
> A Windows version is not currently available. As an independent developer
> with limited time and development capacity, I have focused on the macOS
> version. Thank you for your understanding.

## Installation

### Public beta build

Download `StickS3-Firmware-Lab-v0.1.0-beta-macOS-arm64.dmg` and its `.sha256`
file from the
[v0.1.0 Beta release](https://github.com/oliverxing2025/StickS3-Firmware-Lab/releases/tag/v0.1.0-beta).
Verify the disk image before opening it:

```sh
shasum -a 256 -c StickS3-Firmware-Lab-v0.1.0-beta-macOS-arm64.dmg.sha256
```

Open the DMG, then drag `StickS3 固件实验台.app` onto the `Applications`
shortcut.

This beta is not Apple-notarized. For the first launch:

1. In Finder, open `Applications` and try to launch `StickS3 固件实验台` once.
2. If macOS blocks it, select **Done**, then open **System Settings > Privacy &
   Security**.
3. Scroll to **Security**, select **Open Anyway** for StickS3 Firmware Lab,
   authenticate if requested, and confirm **Open** in the final dialog.

Only override this protection after the downloaded DMG passes the checksum
verification above and you trust this repository as the source.

For source projects, use the corresponding official download button in
**Firmware Manager**:

- Arduino / PlatformIO: [download PlatformIO Core](https://docs.platformio.org/en/latest/core/installation/methods/installer-script.html)
- ESP-IDF projects: [download ESP-IDF Installation Manager](https://docs.espressif.com/projects/idf-im-ui/en/latest/)

Return to the app and select **Check Again** after installation.

> [!WARNING]
> This beta uses ad-hoc signing and does not have a Developer ID signature or
> Apple notarization. The first-launch approval above is required on systems
> where Gatekeeper blocks the app.

### Build from source

```sh
./scripts/run.sh
```

## Quick start

1. Launch the application.
2. Select **Import firmware or project** and choose an ESP-IDF or
   PlatformIO/Arduino project root, a `firmware/sticks3` directory, an Arduino
   `.ino` project directory.
3. Open **Manage** to inspect compatibility and project status.
4. Review the detected hardware profile. If the project is ambiguous, start it
   and use **Calibrate** to confirm axes, buttons, and display rotation.
5. Start a compatible firmware project.
6. Use pose, motion, shake, and physical-button controls to exercise the firmware
   display and normal interactions.
7. After changing firmware source, choose **Reload firmware**.

Imported source directories are read-only references. Removing an entry from
the catalog does not delete or modify the original project.

<div align="center">
  <img src="assets/screenshots/running-firmware.png" alt="Latest v0.1.0 Beta interface running a firmware project" width="1000">
</div>

> [!WARNING]
> Import only source projects that you trust. PlatformIO, Arduino, ESP-IDF,
> CMake, and project dependency hooks can execute build scripts with your macOS
> user permissions. Building in an app-private copy protects the original
> source tree from modification, but it does not turn untrusted build scripts
> into safe code.

## Complete controls

### Device console

| Control | Effect |
| --- | --- |
| Default / Physical size | Switch between readable scale and a 2× reference based on the 48 × 24 mm device face |
| Upright | Send the default StickS3 gravity pose |
| Left 90° / Right 90° | Rotate the complete body, display, buttons, and gravity axes |
| Upside down | Rotate the complete device by 180° |
| X / Y / Z | Adjust simulated BMI270 gravity |
| Side shake / Up-down shake | Apply a short BMI270 gesture and return to the previous pose |
| Blue front button | Single, double, triple, quadruple, or long press |
| Gray side button | Single, double, triple, quadruple, or long press |
| Brightness / Battery | Update the simulated device state |
| Charging / Sound | Toggle charging and firmware audio |
| 30 FPS / 60 FPS | Select display refresh rate |

Available controls depend on the current firmware and runtime mode. Generic
source-project compatibility focuses on the display, both physical buttons,
and BMI270 pose input; controls that are not connected are disabled in the UI.

Button bindings remain firmware-owned. A dimmed gesture is intentionally
unbound; the simulator does not invent a behavior.

### Keyboard

| Key | Action |
| --- | --- |
| `←` / `→` | Tilt left or right |
| `↑` / `↓` | Tilt forward or backward |
| `Space` | Blue front-button single press |
| `L` | Blue front-button long press |
| `S` | Toggle sound |

## Importing and reloading firmware

- Import one ESP-IDF or PlatformIO/Arduino project root, a `firmware/sticks3`
  directory or an Arduino `.ino` project directory at a time.
- The application checks the project structure and reports whether it can run.
- Common hardware mappings are detected from source semantics rather than the
  project name. Ambiguous mappings are shown for local calibration.
- Saved calibration is bound to the source fingerprint; a source change
  triggers detection again instead of silently reusing stale mappings.
- After source changes to firmware with an embedded adapter, use **Reload
  firmware** to rebuild the app from the latest source. Firmware Manager does
  not route these projects through the generic QEMU adaptation path.
- Generic source-project adaptation currently targets StickS3 projects using
  M5Unified/M5GFX for display, both physical buttons, and BMI270 input. An
  unknown project that uses custom `esp_lcd` or other hardware drivers needs a
  dedicated adapter; the app reports that boundary instead of claiming it can
  run the project directly.
- Imported directories remain read-only and are never modified by the app.
- Private builds are cached only while the source, adapter, and hardware profile
  signatures match. Removing a catalog entry also removes its test cache, not
  the imported project.
- Projects that directly require Wi-Fi, Bluetooth, cloud services, USB, ULP,
  or custom hardware drivers are clearly identified when further work is needed.
- Precompiled `.bin` files are not imported; use a source project that the app
  can copy and adapt privately.

The project catalog is stored under
`Application Support/Stick S3 Firmware Simulator/`. It remains outside the
synchronized workspace and outside Git.

## Project structure

```text
.
├── assets/screenshots/
│   ├── landscape-control-console.png
│   ├── running-firmware.png
│   └── sticks3-firmware-lab-brand.png
├── Resources/
│   ├── AppIcon-1024.png
│   ├── Info.plist
│   ├── SplashAvatar.png
│   └── VirtualBoard/
├── Sources/
├── Tests/
├── Vendor/
├── scripts/
├── Package.swift
├── README.md
└── README.zh-CN.md
```

Build products, local SwiftPM state, firmware binaries, logs, credentials,
recordings, and machine state are intentionally excluded from Git.

## Build

```sh
swift test
./scripts/build-app.sh
```

Install the built application on the desktop:

```sh
./scripts/install-desktop.sh
```

Local builds use ad-hoc signing by default. A distributor can explicitly set
`CODESIGN_IDENTITY` and complete Developer ID signing and notarization.

## Privacy and local data

- Imported project paths are stored only in local Application Support.
- Optional local connection credentials are used only when explicitly
  provided by the user.
- The firmware host-data bridge accepts only loopback services on the same Mac;
  remote and LAN destinations are rejected.
- Credentials remain in memory and are not displayed, copied, or written to
  the simulator catalog.
- A clean installation does not read unrelated macOS Keychain entries.
- User project paths are not frozen into the distributed application binary.
- The simulator does not flash, erase, or modify a physical StickS3.

## Asset and dependency notes

The application artwork is project-owned. LVGL, Montserrat, and imported
firmware snapshots retain their upstream licenses and notices under
`Vendor/Licenses/`, `NOTICE`, and `THIRD_PARTY_NOTICES.md`.
Every public binary release must also attach the third-party source bundle
generated by `scripts/prepare-third-party-sources.sh`. Release builds pin the
reviewed Espressif QEMU executable by SHA-256 and include a checksum manifest
for the signed runtime payload inside the application bundle.

## License

StickS3 Firmware Lab is open source under the [MIT License](LICENSE).
Third-party attribution and firmware snapshot terms are provided in [NOTICE](NOTICE) and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
