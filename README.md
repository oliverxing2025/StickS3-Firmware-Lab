<div align="center">
  <h1>Stick S3 Virtual Device</h1>
  <p><strong>Native macOS virtual device for M5Stack StickS3 firmware</strong></p>
  <p>
    Run real firmware renderers, interaction logic, motion input, buttons,<br>
    audio timing, and RGB565 frames without rewriting the UI in SwiftUI.
  </p>
  <p>
    <a href="#overview">Overview</a> ·
    <a href="#whats-new-in-v010">v0.1.0</a> ·
    <a href="#broad-firmware-compatibility">Compatibility</a> ·
    <a href="#complete-controls">Controls</a> ·
    <a href="#installation">Install</a> ·
    <a href="#testing-status-and-windows-support">Support</a> ·
    <a href="#build">Build</a> ·
    <a href="README.zh-CN.md">简体中文</a>
  </p>
  <p>
    <img alt="Platform: macOS 14+" src="https://img.shields.io/badge/platform-macOS%2014%2B-111111">
    <img alt="Architecture: Apple Silicon" src="https://img.shields.io/badge/architecture-Apple%20Silicon-5A5A5A">
    <img alt="Swift: 6" src="https://img.shields.io/badge/Swift-6-F05138">
    <img alt="Version: 0.1.0" src="https://img.shields.io/badge/version-0.1.0-2F80ED">
    <img alt="Mode: local first" src="https://img.shields.io/badge/mode-local--first-2E8B57">
  </p>
</div>

## What's new in v0.1.0

Released on August 3, 2026. Repository members can download the app and view
the complete notes on the
[v0.1.0 release page](https://github.com/oliverxing2025/StickS3-Virtual-Device/releases/tag/v0.1.0).

- **Broad firmware import:** add most StickS3 source projects to one local
  catalog and check their compatibility before starting.
- **Whole-device pose simulation:** portrait, left 90°, right 90°, and upside
  down rotate the body, display, and physical buttons together.
- **Fixed desktop viewport:** the application does not scroll horizontally or
  vertically; the complete control surface stays in one window.
- **Safe project reload:** refresh an imported source project without modifying
  its original files.

## Overview

<div align="center">
  <img src="assets/screenshots/stick-s3-virtual-device-brand.png" alt="Stick S3 Virtual Device and XiaoAo Technology brand artwork" width="520">
</div>

Stick S3 Virtual Device is a native macOS environment for importing, running,
and interacting with StickS3 firmware projects in a physical-device shell.

| | Capability | What it adds |
| --- | --- | --- |
| **01** | Broad firmware import | Adds most StickS3 source projects to one local catalog for compatibility checks and simulation. |
| **02** | Complete device controls | Simulates BMI270 gravity axes, both physical buttons, battery, charging, sound, and display refresh rate. |
| **03** | Safe project reload | Refreshes changed project source without modifying the original directory. |
| **04** | Local-first data | Keeps imported paths, settings, and test data on the Mac rather than uploading them to a service. |

> [!NOTE]
> This application complements real-device testing. Display color, physical
> sensor noise, ES8311 response, ESP32 memory and task scheduling, OTA metadata,
> partitions, and flash safety still require a physical StickS3.

<div align="center">
  <img src="assets/screenshots/empty-firmware-library.png" alt="Clean first-run state before a firmware project is imported" width="1000">
</div>

## Device experience

- Choose imported firmware from one shared catalog.
- Switch between the readable default scale and a physical-size reference.
- Rotate the complete virtual device to four supported poses.
- Drive X, Y, and Z gravity independently with the control console.
- Trigger single, double, triple, quadruple, and long presses for both buttons.
- Adjust battery, charging, audio, brightness, and 30/60 FPS state.
- Pause simulation or restart the current firmware without restarting the app.
- Inspect firmware capacity and application-image resource usage.
- View reload progress and logs.

<div align="center">
  <img src="assets/screenshots/landscape-control-console.png" alt="Firmware running in landscape pose with virtual motion and device controls" width="1000">
</div>

## Broad firmware compatibility

The application is designed for broad compatibility with most StickS3
firmware source projects. It can import a project root or
`firmware/sticks3` directory, inspect its structure and resource usage, and
manage it from the shared firmware catalog.

Projects using common RGB565 or LVGL rendering, physical buttons, BMI270 motion,
and audio interfaces can usually be simulated directly. The application checks
each imported project and clearly reports whether it can run or needs a
compatibility update. Raw ESP32 `.bin` files can be cataloged and identified,
but cannot execute directly inside the source-based macOS application.

## System requirements

| Item | Requirement |
| --- | --- |
| Mac | Apple Silicon |
| Operating system | macOS 14 or later |
| Source build | Xcode command-line tools and Swift 6 |
| Display | Fixed application window; no horizontal or vertical page scrolling |

## Testing status and Windows support

> [!IMPORTANT]
> This early release has not yet undergone repeated validation across multiple
> Mac models, macOS versions, and hardware configurations. If you encounter any
> problem, please report it through
> [GitHub Issues](https://github.com/oliverxing2025/StickS3-Virtual-Device/issues).
> Feedback is welcome, and the application will continue to be corrected and
> updated as issues are identified.

> [!NOTE]
> A Windows version is not currently available. As an independent developer
> with limited time and development capacity, I have focused on the macOS
> version. Thank you for your understanding.

## Installation

### Release build

Repository members can download
`Stick-S3-Virtual-Device-v0.1.0-macOS-arm64.zip` from
[GitHub Releases](https://github.com/oliverxing2025/StickS3-Virtual-Device/releases).

1. Extract the ZIP on an Apple Silicon Mac.
2. Drag **Stick S3 虚拟设备.app** into **Applications**.
3. Open the application.

The first private test build uses ad-hoc signing and is not yet notarized with
Apple. External distribution should use Developer ID signing, Apple
notarization, and Gatekeeper verification.

### Run from source

```sh
./scripts/run.sh
```

## Quick start

1. Launch the application.
2. Select **Import firmware or project** and choose one project root,
   `firmware/sticks3` directory, or ESP32 `.bin` file.
3. Open **Manage** to inspect compatibility and project status.
4. Start a compatible firmware project.
5. Use pose, motion, button, battery, and audio controls to exercise the
   firmware.
6. After changing firmware source, choose **Reload firmware**.

Imported source directories are read-only references. Removing an entry from
the catalog does not delete or modify the original project.

<div align="center">
  <img src="assets/screenshots/running-firmware-console.png" alt="Firmware running inside the Stick S3 Virtual Device console" width="1000">
</div>

## Complete controls

### Device console

| Control | Effect |
| --- | --- |
| Default / Physical size | Switch between readable scale and a 2× reference based on the 48 × 24 mm device face |
| Upright | Send the default StickS3 gravity pose |
| Left 90° / Right 90° | Rotate the complete body, display, buttons, and gravity axes |
| Upside down | Rotate the complete device by 180° |
| X / Y / Z | Adjust simulated BMI270 gravity |
| Blue front button | Single, double, triple, quadruple, or long press |
| Gray side button | Single, double, triple, quadruple, or long press |
| Brightness / Battery | Update the simulated device state |
| Charging / Sound | Toggle charging and firmware audio |
| 30 FPS / 60 FPS | Select display refresh rate |

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

- Import one project root, `firmware/sticks3` directory, or `.bin` file at
  a time.
- The application checks the project structure and reports whether it can run.
- After source files change, use **Reload firmware** to refresh the project.
- Imported directories remain read-only and are never modified by the app.
- Projects that need additional compatibility work are clearly identified.
- Raw ESP32 binaries can be cataloged and identified, but they cannot execute
  inside the current source-based macOS host.

The project catalog is stored under
`Application Support/Stick S3 Firmware Simulator/`. It remains outside the
synchronized workspace and outside Git.

## Project structure

```text
.
├── assets/screenshots/
│   ├── empty-firmware-library.png
│   ├── landscape-control-console.png
│   ├── running-firmware-console.png
│   └── stick-s3-virtual-device-brand.png
├── Resources/
│   ├── AppIcon-1024.png
│   ├── Info.plist
│   └── SplashAvatar.png
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
- Credentials remain in memory and are not displayed, copied, or written to
  the simulator catalog.
- A clean installation does not read unrelated macOS Keychain entries.
- User project paths are not frozen into the distributed application binary.
- The simulator does not flash, erase, or modify a physical StickS3.

## Asset and dependency notes

The application artwork is project-owned. LVGL, Montserrat, and imported
firmware snapshots retain their upstream licenses and notices under
`Vendor/Licenses/`, `NOTICE`, and `THIRD_PARTY_NOTICES.md`.

## License

Source license terms are provided in [LICENSE](LICENSE). Third-party attribution
and firmware snapshot terms are provided in [NOTICE](NOTICE) and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
