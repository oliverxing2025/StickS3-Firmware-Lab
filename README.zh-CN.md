<div align="center">
  <h1>Stick S3 虚拟设备</h1>
  <p><strong>面向 M5Stack StickS3 固件的原生 macOS 虚拟设备</strong></p>
  <p>
    直接运行真实固件渲染、交互逻辑、姿态输入、按键、声音时序与<br>
    RGB565 帧缓冲，不在 SwiftUI 中另画一套相似界面。
  </p>
  <p>
    <a href="#项目概览">项目概览</a> ·
    <a href="#v010-更新">v0.1.0</a> ·
    <a href="#支持大部分-sticks3-固件">固件兼容</a> ·
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
    <img alt="版本：0.1.0" src="https://img.shields.io/badge/version-0.1.0-2F80ED">
    <img alt="模式：本地优先" src="https://img.shields.io/badge/mode-local--first-2E8B57">
  </p>
</div>

## v0.1.0 更新

发布于 2026 年 8 月 3 日。仓库成员可在
[v0.1.0 发布页](https://github.com/oliverxing2025/StickS3-Virtual-Device/releases/tag/v0.1.0)
下载安装包并查看完整说明。

- **广泛固件导入：**将大部分 StickS3 源码项目加入本机目录，并在运行前检查兼容状态。
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
| **01** | 广泛固件导入 | 将大部分 StickS3 源码项目加入本机目录，检查兼容状态并进行模拟 |
| **02** | 完整设备控制 | 模拟 BMI270 重力轴、两个实体按键、电量、充电、声音和刷新率 |
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
- 调整电量、充电、声音、亮度和 30/60 FPS 状态。
- 暂停模拟或重启当前固件，不必重启应用。
- 查看分区容量和应用镜像资源使用情况。
- 查看重新载入进度和日志。

<div align="center">
  <img src="assets/screenshots/landscape-control-console.png" alt="固件横屏运行及虚拟姿态和设备控制" width="1000">
</div>

## 支持大部分 StickS3 固件

本应用面向大部分 StickS3 固件源码项目设计。用户可以导入项目根目录或
`firmware/sticks3` 目录，检查源码结构和资源占用，并通过统一的固件目录
进行管理。

使用常见 RGB565 或 LVGL 渲染、实体按键、BMI270 姿态和声音接口的项目，
通常可以直接模拟。应用会检查每个导入项目，并明确报告它是否可以运行或需要
兼容性更新。ESP32 原始 `.bin` 文件可以登记和识别，但不能在当前源码型
macOS 应用中直接执行。

## 系统要求

| 项目 | 要求 |
| --- | --- |
| Mac | Apple Silicon |
| 操作系统 | macOS 14 或更高版本 |
| 源码构建 | Xcode 命令行工具与 Swift 6 |
| 页面 | 固定应用窗口，不允许上下或左右滚动 |

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
下载 `Stick-S3-Virtual-Device-v0.1.0-macOS-arm64.zip`。

1. 在 Apple Silicon Mac 上解压 ZIP。
2. 将“Stick S3 虚拟设备.app”拖入“应用程序”。
3. 打开应用。

首个私有测试版使用 ad-hoc 签名，尚未完成 Apple 公证。对外分发前应使用
Developer ID 签名、Apple 公证和 Gatekeeper 验证。

### 从源码运行

```sh
./scripts/run.sh
```

## 快速开始

1. 启动应用。
2. 选择“导入固件或项目”，指定一个项目根目录、`firmware/sticks3` 目录或 ESP32 `.bin` 文件。
3. 打开“管理”检查兼容性与项目状态。
4. 启动兼容的固件项目。
5. 使用姿态、重力、按键、电量和声音控制测试固件。
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

- 每次导入一个项目根目录、`firmware/sticks3` 目录或 `.bin` 文件。
- 应用会检查项目结构并报告它是否可以运行。
- 源码变化后，使用“重新载入固件”刷新项目。
- 导入目录始终保持只读，应用不会修改原始文件。
- 需要进一步兼容处理的项目会得到明确提示。
- ESP32 原始二进制可以登记和识别，但不能在当前源码型 macOS 主机中直接执行。

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
│   └── SplashAvatar.png
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

## 许可证

源码许可见 [LICENSE](LICENSE)。第三方归属与固件快照条款见
[NOTICE](NOTICE) 和 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
