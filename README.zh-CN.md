<div align="center">
  <h1>Stick S3 虚拟设备</h1>
  <p><strong>面向 M5Stack StickS3 固件的原生 macOS 虚拟设备</strong></p>
  <p>
    在私有副本中构建兼容的 StickS3 源码工程，并将固件画面、<br>
    实体按键和 BMI270 姿态输入接入同一个 macOS 控制台。
  </p>
  <p>
    <a href="#项目概览">项目概览</a> ·
    <a href="#v020-更新">v0.2.0</a> ·
    <a href="#sticks3-源码工程兼容">固件兼容</a> ·
    <a href="#完整控制">完整控制</a> ·
    <a href="#安装">安装</a> ·
    <a href="#测试状态与-windows-支持">支持说明</a> ·
    <a href="#构建">构建</a> ·
    <a href="README.md">English</a>
  </p>
  <p>
    <img alt="平台：macOS 14+" src="https://img.shields.io/badge/platform-macOS%2014%2B-111111">
    <img alt="架构：Apple Silicon" src="https://img.shields.io/badge/architecture-Apple%20Silicon-5A5A5A">
    <img alt="Swift：6" src="https://img.shields.io/badge/Swift-6-F05138">
    <img alt="版本：0.2.0" src="https://img.shields.io/badge/version-0.2.0-2F80ED">
    <img alt="模式：本地优先" src="https://img.shields.io/badge/mode-local--first-2E8B57">
  </p>
</div>

## v0.2.0 更新

当前私有测试版更新于 2026 年 8 月 3 日。完成正式签名、公证和
发布门禁后，安装包将在 GitHub Releases 提供。

- **源码工程模拟：**已完成 ESP-IDF、PlatformIO 和 Arduino 源码工程的构建、画面、按键与 BMI270 端到端验证。
- **整机姿态模拟：**正放、左转 90°、右转 90°、反放会同时旋转机身、屏幕和实体按键。
- **固定桌面视口：**页面不能上下或左右滚动，完整控制区始终保持在同一个窗口内。
- **安全项目重载：**固件源码变化后可以重新载入，不修改原项目文件。

## 项目概览

<div align="center">
  <img src="assets/screenshots/stick-s3-virtual-device-brand.png" alt="Stick S3 虚拟设备与小奥科技品牌图" width="520">
</div>

Stick S3 虚拟设备是用于导入、运行和操作 StickS3 固件项目的原生 macOS
环境，并通过完整的虚拟机身呈现固件界面。

| | 能力 | 作用 |
| --- | --- | --- |
| **01** | 源码工程导入 | 将兼容的 StickS3 源码工程加入本机目录，识别构建体系并检查模拟兼容状态 |
| **02** | 常规显示与操作 | 为兼容的源码工程接入固件画面、两个实体按键和 BMI270 姿态输入 |
| **03** | 安全项目重载 | 源码变化后重新载入，不修改原始项目目录 |
| **04** | 本地数据优先 | 导入路径、设置和测试数据保留在 Mac 本机，不上传到网络服务 |

> [!NOTE]
> 本应用用于补充真机测试。屏幕色差、真实传感器噪声、ES8311 响应、
> ESP32 内存与任务调度、OTA 元数据、分区和烧录安全仍需 StickS3 真机验收。

<div align="center">
  <img src="assets/screenshots/empty-firmware-library.png" alt="尚未导入固件时的干净首次运行状态" width="1000">
</div>

## 设备体验

- 从同一份目录选择用户主动导入的固件。
- 在清晰的默认比例和实体尺寸参考之间切换。
- 将完整虚拟设备旋转为四种支持姿态。
- 通过控制台独立调整 X、Y、Z 重力方向。
- 触发两个实体按键的单击、双击、三击、四击和长按。
- 在当前固件支持时调整电量、充电、声音、亮度和刷新率状态。
- 暂停模拟或重启当前固件，不必重启应用。
- 查看分区容量和应用镜像资源使用情况。
- 查看重新载入进度和日志。

<div align="center">
  <img src="assets/screenshots/landscape-control-console.png" alt="固件横屏运行及虚拟姿态和设备控制" width="1000">
</div>

## StickS3 源码工程兼容

本应用面向常见 StickS3 固件源码项目设计。用户可以导入 ESP-IDF 项目根目录、
`firmware/sticks3` 目录、带 `platformio.ini` 的 PlatformIO/Arduino 工程，或
包含 `.ino` 草图的 Arduino 工程，并通过统一的固件目录检查和管理。

应用会在原工程之外创建私有构建副本，并为采用 M5Unified/M5GFX 的常见 StickS3
固件接入屏幕、两个实体按键和 BMI270 姿态桥接。QEMU 已随应用提供；源码工程需要
用户按项目类型自行安装 [PlatformIO Core](https://docs.platformio.org/en/latest/core/installation/methods/installer-script.html)
或可选的 [ESP-IDF Installation Manager](https://docs.espressif.com/projects/idf-im-ui/en/latest/)。
应用内提供相同的官方下载入口，不要求使用 Homebrew。

本版本聚焦普通固件的画面与常规操作，不模拟 Wi-Fi、蓝牙、云服务、USB 和 ULP
程序。直接访问这些外设、采用自定义显示驱动或不使用 M5Unified/M5GFX 的项目，
仍可能需要进一步兼容。本产品不导入 M5Burner 或其他渠道提供的已编译 `.bin`；
内置 QEMU 仅作为适配后源码构建结果的内部执行后端。

## 系统要求

| 项目 | 要求 |
| --- | --- |
| Mac | Apple Silicon |
| 操作系统 | macOS 14 或更高版本 |
| 源码构建 | Xcode 命令行工具与 Swift 6 |
| 页面 | 固定应用窗口，不允许上下或左右滚动 |
| QEMU | 随应用提供，无需另行安装 |
| PlatformIO | Arduino/PlatformIO 源码工程需要；应用内提供官方下载入口 |
| ESP-IDF | 仅 ESP-IDF 源码工程需要；属于可选安装 |
| 网络 | 安装构建工具及项目新增依赖时需要联网；已缓存组件会复用 |

## 测试状态与 Windows 支持

> [!IMPORTANT]
> 当前版本尚未在多台不同型号的 Mac、多个 macOS 系统版本及不同硬件环境下
> 进行多轮完整测试。如在使用过程中遇到任何问题，欢迎随时通过
> [GitHub Issues](https://github.com/oliverxing2025/StickS3-Virtual-Device/issues)
> 反馈，我会根据实际情况持续修复和更新。

> [!NOTE]
> 由于个人时间和精力有限，目前尚未开发 Windows 版本，敬请谅解。

## 安装

### 安装发布版

仓库成员可从
[GitHub Releases](https://github.com/oliverxing2025/StickS3-Virtual-Device/releases)
下载 `Stick-S3-Virtual-Device-v0.2.0-macOS-arm64.zip`。

1. 在 Apple Silicon Mac 上解压 ZIP。
2. 将“Stick S3 虚拟设备.app”拖入“应用程序”。
3. 打开应用。

如果要导入源码工程，请在“固件管理”中使用对应的官方下载按钮：

- 普通 Arduino / PlatformIO 工程：[下载 PlatformIO Core](https://docs.platformio.org/en/latest/core/installation/methods/installer-script.html)
- ESP-IDF 工程（可选）：[下载 ESP-IDF Installation Manager](https://docs.espressif.com/projects/idf-im-ui/en/latest/)

安装完成后返回应用点击“重新检测”。

首个私有测试版使用 ad-hoc 签名，尚未完成 Apple 公证。对外分发前应使用
Developer ID 签名、Apple 公证和 Gatekeeper 验证。

### 从源码运行

```sh
./scripts/run.sh
```

## 快速开始

1. 启动应用。
2. 选择“导入固件或项目”，指定 ESP-IDF、PlatformIO/Arduino 项目根目录、`firmware/sticks3` 目录或 `.ino` 工程目录。
3. 打开“管理”检查兼容性与项目状态。
4. 启动兼容的固件项目。
5. 使用姿态、重力和实体按键测试固件画面与常规操作。
6. 固件源码变化后选择“重新载入固件”。

导入目录只作为只读引用。把条目从目录中删除不会删除或修改原项目。

<div align="center">
  <img src="assets/screenshots/running-firmware-console.png" alt="固件运行在 Stick S3 虚拟设备控制台中" width="1000">
</div>

## 完整控制

### 设备控制台

| 控制项 | 效果 |
| --- | --- |
| 默认 / 实寸 | 在清晰比例和以 48 × 24 mm 正面尺寸为基础的 2 倍参考之间切换 |
| 正放 | 发送 StickS3 默认重力姿态 |
| 左转 90° / 右转 90° | 同时旋转机身、屏幕、按键和重力轴 |
| 反放 | 将完整设备旋转 180° |
| X / Y / Z | 调整模拟 BMI270 重力 |
| 蓝色前键 | 单击、双击、三击、四击或长按 |
| 灰色侧键 | 单击、双击、三击、四击或长按 |
| 亮度 / 电量 | 更新模拟设备状态 |
| 充电 / 声音 | 切换充电与固件声音 |
| 30 FPS / 60 FPS | 选择屏幕刷新率 |

具体控制项取决于当前固件和运行模式。通用源码工程兼容模式聚焦画面、
两个实体按键和 BMI270 姿态输入；未接入的控制会在界面中禁用。

按键功能由固件定义。淡显手势表示当前没有绑定，模拟器不会伪造功能。

### 键盘

| 按键 | 操作 |
| --- | --- |
| `←` / `→` | 左右倾斜 |
| `↑` / `↓` | 前后倾斜 |
| `Space` | 蓝色前键单击 |
| `L` | 蓝色前键长按 |
| `S` | 切换声音 |

## 导入与重新载入固件

- 每次导入一个 ESP-IDF、PlatformIO/Arduino 项目根目录、`firmware/sticks3` 目录或 `.ino` 工程目录。
- 应用会检查项目结构并报告它是否可以运行。
- 源码变化后，使用“重新载入固件”刷新项目。
- 导入目录始终保持只读，应用不会修改原始文件。
- 需要直接访问 Wi-Fi、蓝牙、云服务、USB、ULP 或自定义硬件驱动的项目会得到明确提示。
- 不导入已编译 `.bin`；请使用可供应用创建私有适配副本的源码工程。

项目目录保存在
`Application Support/Stick S3 Firmware Simulator/`，不进入同步工作区或 Git。

## 项目结构

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

构建产物、SwiftPM 本地状态、固件二进制、日志、凭据、录音和设备状态均明确排除
在 Git 之外。

## 构建

```sh
swift test
./scripts/build-app.sh
```

将构建结果安装到桌面：

```sh
./scripts/install-desktop.sh
```

本机构建默认使用 ad-hoc 签名。正式分发者可以显式设置
`CODESIGN_IDENTITY`，并完成 Developer ID 签名与公证。

## 隐私与本地数据

- 导入项目路径只保存在本机 Application Support。
- 可选本地连接凭据只有在用户明确提供时才会使用。
- 凭据只保留在内存中，不显示、不复制、不写入模拟器目录。
- 干净安装不会读取无关的 macOS 钥匙串条目。
- 用户项目路径不会固化到分发应用的二进制中。
- 模拟器不会烧录、擦除或修改真实 StickS3。

## 资产与依赖说明

应用美术由项目自有。LVGL、Montserrat 和导入固件快照保留各自上游许可证，
详见 `Vendor/Licenses/`、`NOTICE` 与 `THIRD_PARTY_NOTICES.md`。
公开发布的安装包必须同时附带
`scripts/prepare-third-party-sources.sh` 生成的第三方源码包。

## 许可证

源码许可见 [LICENSE](LICENSE)。第三方归属与固件快照条款见
[NOTICE](NOTICE) 和 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
