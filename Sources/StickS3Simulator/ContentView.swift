import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var model = SimulatorModel()
    @AppStorage("simulator.lightBackground") private var lightBackground = false
    @AppStorage("simulator.realDeviceSize") private var realDeviceSize = false
    @AppStorage("simulator.language") private var language = SimulatorLanguage.chinese.rawValue
    @State private var showsProjectManager = false
    @State private var showsRebuildLog = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                HStack(alignment: .top, spacing: 16) {
                    // 左侧设备在窗口可用高度内始终上下居中。
                    device
                        .fixedSize(horizontal: true, vertical: true)
                        // 旋转整台虚拟设备，包括机身、屏幕和实体按键。
                        .rotationEffect(.degrees(model.devicePose.angle))
                        .scaleEffect(deviceDisplayScale)
                        .animation(.spring(response: 0.42, dampingFraction: 0.84),
                                   value: realDeviceSize)
                        .animation(.spring(response: 0.42, dampingFraction: 0.84),
                                   value: model.devicePose)
                        // 竖屏机身向左留出资源卡的独立空间；横屏时下方空间充足，仍保持居中。
                        .offset(x: deviceHorizontalOffset, y: deviceVerticalOffset)
                        .frame(width: deviceRotationSlotWidth,
                               height: max(deviceRotationSlotHeight, geometry.size.height - contentInsets),
                               alignment: .center)
                    inspector
                }
                themeSwitch
                sizeSwitch
                    .frame(width: deviceRotationSlotWidth, alignment: .trailing)
                languageSwitch
                    .frame(maxWidth: .infinity,
                           minHeight: 0,
                           maxHeight: max(0, geometry.size.height - contentInsets),
                           alignment: .bottomLeading)
                resourceStatusCard
                    .frame(width: 164)
                    .frame(width: deviceRotationSlotWidth,
                           height: max(0, geometry.size.height - contentInsets),
                           alignment: .bottomTrailing)
            }
            .padding(18)
        }
        .frame(width: fixedWindowContentWidth,
               height: minimumWindowHeight,
               alignment: .topLeading)
        .background(
            LinearGradient(colors: workspaceColors,
                           startPoint: .topLeading, endPoint: .bottomTrailing))
        .preferredColorScheme(lightBackground ? .light : .dark)
        .onAppear {
            NSApplication.shared.activate(ignoringOtherApps: true)
            model.start()
        }
        .onDisappear { model.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            model.stop()
        }
        .sheet(isPresented: $showsProjectManager) {
            ProjectManagerView(model: model)
        }
        .sheet(isPresented: $showsRebuildLog) {
            RebuildLogView(model: model)
        }
    }

    private var themeSwitch: some View {
        HStack(spacing: 0) {
            themeButton(t("深色", "Dark"), symbol: "moon.fill", selected: !lightBackground) {
                lightBackground = false
            }
            themeButton(t("浅色", "Light"), symbol: "sun.max.fill", selected: lightBackground) {
                lightBackground = true
            }
        }
        .padding(3)
        .background(lightBackground ? Color.black.opacity(0.08) : Color.white.opacity(0.09),
                    in: Capsule())
        .overlay(Capsule().stroke(lightBackground ? Color.black.opacity(0.12) : Color.white.opacity(0.13)))
        .accessibilityLabel(t("背景主题", "Appearance"))
    }

    private func themeButton(_ title: String, symbol: String, selected: Bool,
                             action: @escaping () -> Void) -> some View {
        compactSwitchButton(title, symbol: symbol, selected: selected, action: action)
    }

    private var sizeSwitch: some View {
        HStack(spacing: 0) {
            compactSwitchButton(t("默认", "Default"), symbol: "rectangle.inset.filled",
                                selected: !realDeviceSize) {
                realDeviceSize = false
            }
            compactSwitchButton(t("实寸", "Actual"), symbol: "ruler", selected: realDeviceSize) {
                realDeviceSize = true
            }
        }
        .padding(3)
        .background(lightBackground ? Color.black.opacity(0.08) : Color.white.opacity(0.09),
                    in: Capsule())
        .overlay(Capsule().stroke(lightBackground ? Color.black.opacity(0.12) : Color.white.opacity(0.13)))
        .accessibilityLabel(t("设备显示尺寸", "Device display size"))
        .help(t("按 Stick S3 机身正面实寸的 2 倍显示",
                "Display at twice the physical front-face size of Stick S3"))
    }

    private var languageSwitch: some View {
        HStack(spacing: 0) {
            compactSwitchButton("中文", symbol: "character",
                                selected: language == SimulatorLanguage.chinese.rawValue) {
                language = SimulatorLanguage.chinese.rawValue
            }
            compactSwitchButton("English", symbol: "globe",
                                selected: language == SimulatorLanguage.english.rawValue) {
                language = SimulatorLanguage.english.rawValue
            }
        }
        .padding(3)
        .background(lightBackground ? Color.black.opacity(0.08) : Color.white.opacity(0.09),
                    in: Capsule())
        .overlay(Capsule().stroke(lightBackground ? Color.black.opacity(0.12) : Color.white.opacity(0.13)))
        .accessibilityLabel(t("界面语言", "Interface language"))
    }

    private func compactSwitchButton(_ title: String, symbol: String, selected: Bool,
                                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .semibold))
            }
            .frame(width: compactSwitchWidth(title), height: 20)
            .foregroundStyle(selected ? .white : .secondary)
            .background(selected ? Color(rgb: 0x267BFF) : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func compactSwitchWidth(_ title: String) -> CGFloat {
        if title.count >= 7 { return 72 }
        if title.count >= 5 { return 62 }
        return 48
    }

    private func t(_ chinese: String, _ english: String) -> String {
        simulatorText(chinese, english, language: language)
    }

    private var workspaceColors: [Color] {
        lightBackground
            ? [Color(rgb: 0xFCFCFC), Color(rgb: 0xF1F1F1)]
            : [Color(rgb: 0x0B1020), Color(rgb: 0x14182A)]
    }

    private var resourceStatusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                Text(t("设备资源", "Device Resources"))
                    .fontWeight(.bold)
            }
            .font(.caption)

            Divider()

            metricLine(t("分区状态", "Partition layout"), partitionStatusText)
            if let slotCapacity = appSlotCapacityText {
                metricLine(t("应用槽容量", "App slots"), slotCapacity)
            }

            if let imageBytes = model.resourceMetrics.appImageBytes,
               let partitionBytes = model.resourceMetrics.appPartitionBytes,
               let ratio = model.resourceMetrics.appUsageRatio {
                metricLine(t("当前固件", "Current firmware"),
                           "\(formatBytes(imageBytes)) / \(formatBytes(partitionBytes))")
                ProgressView(value: min(max(ratio, 0), 1))
                    .tint(resourceStatusColor)
                if let remaining = model.resourceMetrics.remainingAppBytes {
                    metricLine(t("当前槽剩余", "Current slot free"), formatBytes(max(0, remaining)))
                }
            } else {
                metricLine(t("当前固件", "Current firmware"),
                           t("未发现应用镜像", "App image unavailable"))
            }

            Label(resourceStatusText, systemImage: resourceStatusSymbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(resourceStatusColor)
        }
        .padding(10)
        .background(lightBackground ? .white.opacity(0.86) : .black.opacity(0.30),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(lightBackground ? .black.opacity(0.10) : .white.opacity(0.12)))
        .shadow(color: .black.opacity(lightBackground ? 0.06 : 0.18), radius: 6, y: 2)
    }

    private func metricLine(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
            Spacer(minLength: 2)
            Text(value).foregroundStyle(.secondary)
        }
        .font(.system(size: 9))
        .lineLimit(1)
        .minimumScaleFactor(0.68)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes >= 1_048_576 {
            return String(format: "%.2f MB", Double(bytes) / 1_048_576)
        }
        return String(format: "%.0f KB", Double(bytes) / 1024)
    }

    private var partitionStatusText: String {
        guard let partitions = model.resourceMetrics.appPartitions else {
            return t("未检测", "Not detected")
        }
        guard !partitions.isEmpty else {
            return t("无应用分区", "No app partition")
        }
        if partitions.count == 1, partitions[0].subtype == "factory" {
            return t("单应用分区", "Single app partition")
        }
        if partitions.count == 2,
           Set(partitions.map(\.subtype)) == Set(["ota_0", "ota_1"]) {
            return t("双 OTA 应用分区", "Dual OTA app partitions")
        }
        return t("\(partitions.count) 个应用分区", "\(partitions.count) app partitions")
    }

    private var appSlotCapacityText: String? {
        guard let partitions = model.resourceMetrics.appPartitions, !partitions.isEmpty else {
            return nil
        }
        let sizes = Set(partitions.map(\.sizeBytes))
        if sizes.count == 1, let size = sizes.first {
            return "\(partitions.count) × \(formatBytes(size))"
        }
        return partitions.map { formatBytes($0.sizeBytes) }.joined(separator: " + ")
    }

    private var resourceStatusColor: Color {
        guard let fits = model.resourceMetrics.appFitsPartition else { return .secondary }
        if !fits { return .red }
        if (model.resourceMetrics.appUsageRatio ?? 0) >= 0.90 { return .orange }
        return .green
    }

    private var resourceStatusText: String {
        guard let fits = model.resourceMetrics.appFitsPartition else {
            return t("等待可用的固件资源数据", "Waiting for firmware resource data")
        }
        if !fits { return t("固件已超出当前应用槽", "Firmware exceeds current app slot") }
        if (model.resourceMetrics.appUsageRatio ?? 0) >= 0.90 {
            return t("当前应用槽接近上限", "Current app slot near limit")
        }
        return t("当前应用槽空间正常", "Current app slot space normal")
    }

    private var resourceStatusSymbol: String {
        guard let fits = model.resourceMetrics.appFitsPartition else { return "questionmark.circle" }
        if !fits { return "xmark.circle.fill" }
        if (model.resourceMetrics.appUsageRatio ?? 0) >= 0.90 { return "exclamationmark.triangle.fill" }
        return "checkmark.circle.fill"
    }

    private var device: some View {
        VStack(spacing: 10) {
            HStack {
                Circle().fill(model.hasRunnableFirmware || model.hasActiveQEMUFirmware ? .green : .gray)
                    .frame(width: 7, height: 7)
                Text(t("设备屏幕", "DEVICE SCREEN"))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                Spacer()
                Text(posedPixelLabel)
                    .foregroundStyle(.secondary).font(.system(size: 10, design: .monospaced))
            }
            ZStack {
                deviceFace
                    .fixedSize(horizontal: true, vertical: true)
            }
            .frame(width: baseFaceSize.width, height: baseFaceSize.height)
            .shadow(color: .blue.opacity(0.2), radius: 18)
        }
        .padding(16)
        .frame(width: devicePanelWidth)
        .frame(height: devicePanelHeight)
        .background(
            LinearGradient(
                colors: lightBackground
                    ? [Color(rgb: 0x393B3D), Color(rgb: 0x26282A)]
                    : [.black.opacity(0.72), .black.opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 32, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 32)
            .stroke(lightBackground ? .white.opacity(0.72) : .white.opacity(0.14), lineWidth: 1.2))
        .shadow(color: lightBackground ? .black.opacity(0.18) : .clear,
                radius: lightBackground ? 14 : 0, y: lightBackground ? 7 : 0)
        .foregroundStyle(.white)
    }

    private var deviceFace: some View {
        VStack(spacing: 10) {
            if model.hasActiveQEMUFirmware {
                if model.qemuDisplayReady {
                    QEMUFrameView(model: model)
                        .frame(width: 337.5, height: 600)
                        .colorMultiply(Color(white: model.screenBrightnessPercent / 100))
                } else {
                    VStack(spacing: 14) {
                    Image(systemName: "display")
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(model.qemuState == .running ? .green : .secondary)
                    Text(model.qemuState == .running
                         ? t("固件已启动", "Firmware Started")
                         : t("正在准备固件", "Preparing Firmware"))
                        .font(.title3.bold())
                    Text(model.qemuFirmwareName ?? t("已导入固件", "Imported Firmware"))
                        .font(.callout).foregroundStyle(.secondary)
                    Text(t("等待 StickS3 屏幕像素输出。运行日志可在“固件管理”中查看。",
                           "Waiting for StickS3 display pixels. Runtime details are available in Firmware Manager."))
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(width: 270)
                    ProgressView().controlSize(.small)
                    Button(t("停止模拟", "Stop Simulation")) { model.stopQEMU() }
                        .buttonStyle(.bordered)
                    }
                    .frame(width: 337.5, height: 600)
                }
            } else if !model.hasRunnableFirmware {
                VStack(spacing: 12) {
                    Image(systemName: model.needsSimulatorAdapter
                          ? "wrench.and.screwdriver"
                          : model.hasImportedFirmware ? "hammer" : "shippingbox")
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(.secondary)
                    Text(model.needsSimulatorAdapter
                         ? t("源码工程已识别", "Source Project Recognized")
                         : model.hasImportedFirmware
                         ? t("固件需要重新载入", "Firmware Reload Required")
                         : t("尚未导入固件", "No Firmware Imported"))
                        .font(.title3.bold())
                    Text(model.needsSimulatorAdapter
                         ? t("开始模拟时会在私有副本中接入屏幕、按键和姿态接口。",
                             "Start Simulation connects display, button, and pose interfaces in a private copy.")
                         : model.hasImportedFirmware
                         ? t("所选项目源码与当前虚拟设备版本不同。",
                             "The selected source differs from this virtual device build.")
                         : t("选择一个 StickS3 固件源码项目文件夹。",
                             "Select a StickS3 firmware source-project folder."))
                        .font(.caption).foregroundStyle(.secondary)
                    Button(model.needsSimulatorAdapter
                           ? t("查看兼容状态", "View Compatibility")
                           : model.hasImportedFirmware
                           ? t("重新载入固件", "Reload Firmware")
                           : t("导入固件或项目", "Import Firmware or Project")) {
                        if model.needsSimulatorAdapter {
                            showsProjectManager = true
                        } else if model.hasImportedFirmware {
                            model.rebuildSimulator()
                            showsRebuildLog = true
                        } else {
                            chooseTestProject()
                        }
                    }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.hasImportedFirmware
                                  && !model.needsSimulatorAdapter
                                  && !model.canReloadSelectedFirmware)
                }
                .frame(width: 337.5, height: 600)
            } else {
                Group {
                    if model.selectedProject != .codex {
                        StickScreenView(model: model).frame(width: 337.5, height: 600)
                    } else {
                        CodexFirmwareScreenView(model: model).frame(width: 337.5, height: 600)
                    }
                }
                .colorMultiply(Color(white: model.screenBrightnessPercent / 100))
            }
            if (model.hasRunnableFirmware && !model.hasActiveQEMUFirmware)
                || (model.hasActiveQEMUFirmware && model.qemuBoardCapabilities.contains(.buttons)) {
                HStack(spacing: 28) {
                    Button {
                        model.blueButton(clicks: 1)
                    } label: {
                        VStack {
                            Capsule().fill(Color(rgb: 0x267BFF)).frame(width: 58, height: 18)
                                .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
                            Text(t("前键", "Front Button")).font(.caption)
                        }
                    }.buttonStyle(.plain)
                    Button {
                        model.grayButton(clicks: 1)
                    } label: {
                        VStack {
                            RoundedRectangle(cornerRadius: 2).fill(Color(rgb: 0x777D87))
                                .frame(width: 21, height: 21)
                                .overlay(RoundedRectangle(cornerRadius: 2).stroke(.white.opacity(0.3)))
                            Text(t("侧键", "Side Button")).font(.caption)
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
        .frame(width: baseFaceSize.width, height: baseFaceSize.height)
    }

    @ViewBuilder
    private var hostNetworkStatus: some View {
        switch model.hostNetworkState {
        case .idle:
            Label(t("已准备主机数据通道，等待固件请求",
                    "Host data channel ready; waiting for firmware"),
                  systemImage: "network")
                .foregroundStyle(.secondary)
        case .requesting(let host):
            Label(t("正在读取数据：\(host)", "Loading data: \(host)"),
                  systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
        case .connected(let host, let updatedAt):
            Label(t("数据已连接：\(host) · \(updatedAt.formatted(date: .omitted, time: .standard))",
                    "Data connected: \(host) · \(updatedAt.formatted(date: .omitted, time: .standard))"),
                  systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let host, let reason):
            Label(t("数据不可用：\(host) · \(reason)",
                    "Data unavailable: \(host) · \(reason)"),
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private var inspector: some View {
        redesignedInspector
        .frame(width: inspectorWidth, alignment: .topLeading)
    }

    private var redesignedInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            inspectorHeader
                .padding(.horizontal, 4)

            lightCard {
                firmwareSelectorContent
            }

            lightCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(t("虚拟设备控制台", "Virtual Device Controls"))
                        .font(.system(size: 15, weight: .bold))
                    Text(t("运行控制", "Simulation"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    runControlButtons
                        .disabled(model.hasActiveQEMUFirmware)
                    Divider()
                    poseControlButtons
                    Divider()
                    imuControlRows
                }
            }

            lightCard {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(t("设备按键", "Device Buttons"))
                            .font(.system(size: 14, weight: .bold))
                        deviceButtonRows
                    }
                    .frame(width: 204, alignment: .topLeading)

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text(t("设备状态", "Device Status"))
                            .font(.system(size: 14, weight: .bold))
                        hardwareControlRows
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .disabled(!(model.hasRunnableFirmware && !model.hasActiveQEMUFirmware) && !model.qemuControlsReady)
            .opacity((model.hasRunnableFirmware && !model.hasActiveQEMUFirmware) || model.qemuControlsReady ? 1 : 0.45)

            keyboardHelp
                .padding(.horizontal, 12)
                .padding(.top, 2)

            HStack(spacing: 8) {
                Text(t("版本 \(appVersion)", "Version \(appVersion)"))
                Text("·")
                Text(t("开发者：Oliver Xing", "Developer: Oliver Xing"))
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 2)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.trailing, 6)
        .padding(.bottom, 2)
    }

    private var keyboardHelp: some View {
        Text(t("键盘：←/→ 左右倾斜  ·  ↑/↓ 前后倾斜  ·  Space：蓝色前键单击  ·  L：蓝色前键长按  ·  S：开关声音",
               "Keyboard: ←/→ tilt left/right  ·  ↑/↓ tilt forward/back  ·  Space: click blue front button  ·  L: hold blue front button  ·  S: toggle sound"))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    private var orientationHint: String {
        if model.selectedProject == .codex {
            return t("135 × 240 正放 · 240 × 135 横放自适应固件",
                     "135 × 240 upright · 240 × 135 landscape adaptive")
        }
        return t("135 × 240 竖屏固件", "135 × 240 portrait firmware")
    }

    private var rebuildPhaseTitle: String {
        switch model.rebuildPhase {
        case .idle: return t("就绪", "Ready")
        case .preparing: return t("正在准备构建", "Preparing build")
        case .testing: return t("正在运行测试", "Running tests")
        case .compiling: return t("正在编译最新源码", "Compiling source")
        case .linking: return t("正在生成应用", "Creating application")
        case .signing: return t("正在校验并签名", "Verifying and signing")
        case .installing: return t("构建成功，正在更新并重启", "Built; updating and restarting")
        case .failed: return t("构建失败，已保留当前版本", "Build failed; current version preserved")
        }
    }

    private func lightCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(lightBackground ? .white.opacity(0.82) : .white.opacity(0.055),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(lightBackground ? .black.opacity(0.10) : .white.opacity(0.11), lineWidth: 1))
            .shadow(color: lightBackground ? .black.opacity(0.045) : .black.opacity(0.20),
                    radius: 8, y: 3)
    }

    private var inspectorHeader: some View {
        HStack(spacing: 10) {
            Label(t("StickS3 固件实验台", "StickS3 Firmware Lab"), systemImage: "display")
                .font(.headline)
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label(t("退出", "Quit"), systemImage: "power")
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .help(t("退出 StickS3 固件实验台", "Quit StickS3 Firmware Lab"))
        }
    }

    private var firmwareSelector: some View {
        GroupBox(t("固件选择", "Firmware")) {
            firmwareSelectorContent
        }
    }

    private var firmwareSelectorContent: some View {
        VStack(alignment: .leading, spacing: lightBackground ? 9 : 6) {
            Text(t("固件选择", "Firmware"))
                .font(.system(size: 15, weight: .bold))
            if model.hasActiveQEMUFirmware {
                Label(model.qemuFirmwareName ?? t("已导入固件", "Imported Firmware"), systemImage: "display")
                    .font(.callout.bold()).foregroundStyle(.green)
            } else if model.hasSelectableFirmware {
                Picker("当前固件", selection: $model.selectedProject) {
                    ForEach(model.visibleProjects) { project in
                        Text(project.firmwareName).tag(project)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: model.selectedProject) { _, project in
                    model.eventText = "FIRMWARE \(project.rawValue.uppercased())"
                }
            } else if model.hasImportedFirmware {
                Label(t("已识别项目，等待模拟适配", "Project recognized; adapter required"),
                      systemImage: "wrench.and.screwdriver")
                    .font(.callout.bold()).foregroundStyle(.orange)
            } else {
                Label(t("尚未导入固件", "No firmware imported"), systemImage: "tray")
                    .font(.callout.bold()).foregroundStyle(.secondary)
            }

            if model.hasActiveQEMUFirmware {
                HStack(spacing: 6) {
                    Circle().fill(.green).frame(width: 7, height: 7)
                    Text(t("固件模拟正在运行", "Firmware simulation is running"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if model.qemuBoardCapabilities.contains(.hostNetwork) {
                    hostNetworkStatus.font(.caption)
                }
            } else if model.hasRunnableFirmware {
                HStack(spacing: 6) {
                    Circle().fill(.green).frame(width: 7, height: 7)
                    Text(orientationHint)
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if model.needsSimulatorAdapter {
                HStack(spacing: 6) {
                    Circle().fill(.orange).frame(width: 7, height: 7)
                    Text(t("已识别 StickS3 源码工程，可生成模拟接口",
                           "StickS3 source project recognized; simulator interface is available"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if model.hasImportedFirmware {
                HStack(spacing: 6) {
                    Circle().fill(.orange).frame(width: 7, height: 7)
                    Text(t("源码版本不同，请重新载入固件",
                           "Source version differs; reload the firmware"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Divider()
            HStack(spacing: 8) {
                Button { chooseTestProject() } label: {
                    Label(t("导入固件或项目", "Import Firmware or Project"),
                          systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.blue)
                .help(t("选择 StickS3 固件源码项目",
                        "Choose a StickS3 firmware source project"))
                Button { showsProjectManager = true } label: {
                    Label(t("管理 \(model.firmwareCatalog.count)",
                            "Manage \(model.firmwareCatalog.count)"), systemImage: "shippingbox")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            if !model.projectLibraryMessage.isEmpty {
                Text(localizedSimulatorMessage(model.projectLibraryMessage, language: language))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }

            Divider()
            HStack(spacing: 8) {
                Button {
                    model.rebuildSimulator()
                    showsRebuildLog = true
                } label: {
                    Label(model.isRebuilding
                          ? t("正在重新载入", "Reloading")
                          : t("重新载入固件", "Reload Firmware"),
                          systemImage: "hammer.fill")
                }
                .disabled(model.isRebuilding || !model.canReloadSelectedFirmware)
                Spacer()
                Button(t("查看日志", "View Log")) { showsRebuildLog = true }
                    .buttonStyle(.borderless)
            }
            if model.isRebuilding {
                ProgressView().progressViewStyle(.linear)
            }
            HStack(spacing: 5) {
                Circle()
                    .fill(model.rebuildPhase == .failed ? Color.red
                          : model.isRebuilding ? Color.orange : Color.secondary.opacity(0.5))
                    .frame(width: 6, height: 6)
                Text(rebuildPhaseTitle)
                if let date = model.lastSuccessfulRebuild, !model.isRebuilding {
                    Text(t("· 上次 \(date.formatted(date: .numeric, time: .shortened))",
                           "· Last \(date.formatted(date: .numeric, time: .shortened))"))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var commonPoseControls: some View {
        GroupBox {
            poseControlButtons
        }
    }

    private var poseControlButtons: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) { poseButton(.upright, symbol: "↑"); poseButton(.left90, symbol: "↶") }
            HStack(spacing: 8) { poseButton(.right90, symbol: "↷"); poseButton(.upsideDown, symbol: "↓") }
        }
        .frame(maxWidth: .infinity)
    }

    private var commonRunControls: some View {
        GroupBox(t("运行控制", "Simulation")) {
            runControlButtons
        }
    }

    private var runControlButtons: some View {
        HStack(spacing: 12) {
            Button {
                model.setSimulationRunning(!model.running)
            } label: {
                Label(model.running
                      ? t("暂停模拟", "Pause Simulation")
                      : t("继续模拟", "Resume Simulation"),
                      systemImage: model.running ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                model.restartSelectedFirmware()
            } label: {
                Label(t("重启当前固件", "Restart Firmware"),
                      systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(lightBackground ? .large : .regular)
    }

    private var commonIMUControls: some View {
        GroupBox {
            imuControlRows
        }
    }

    private var imuControlRows: some View {
        VStack(alignment: .leading, spacing: 7) {
            axisRow("X", value: $model.tilt, neutralValue: 0)
            axisRow("Y", value: $model.tiltY, neutralValue: 0)
            axisRow("Z", value: $model.tiltZ, neutralValue: 1)
            Text(String(format: "X %+.2f  Y %+.2f  Z %+.2f g", model.tilt, model.tiltY, model.tiltZ))
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
        }
    }

    private var commonButtonControls: some View {
        GroupBox {
            deviceButtonRows
        }
    }

    private var deviceButtonRows: some View {
        VStack(spacing: 9) {
            Group {
                deviceButtonRow(title: t("蓝色前键", "Blue Front Button"),
                                color: Color(rgb: 0x267BFF), square: false,
                                button: .front) { model.blueButton(clicks: $0) }
                deviceButtonRow(title: t("灰色侧键", "Gray Side Button"),
                                color: Color(rgb: 0x777D87), square: true,
                                button: .side) { model.grayButton(clicks: $0) }
            }
            .disabled(model.hasActiveQEMUFirmware && !model.qemuControlsReady)

            HStack(spacing: 6) {
                shakeButton(t("左右晃动", "Side Shake"), symbol: "arrow.left.and.right",
                            gesture: .horizontal)
                shakeButton(t("上下晃动", "Up/Down Shake"), symbol: "arrow.up.and.down",
                            gesture: .vertical)
            }
            .disabled(!model.canPerformDeviceShake || model.activeShakeGesture != nil)
        }
        .frame(maxWidth: .infinity)
    }

    private func shakeButton(_ label: String, symbol: String,
                             gesture: DeviceShakeGesture) -> some View {
        Button {
            model.performDeviceShake(gesture)
        } label: {
            Label(label, systemImage: symbol)
                .font(.caption2.bold())
                .frame(maxWidth: .infinity, minHeight: 23)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .help(t("模拟 StickS3 的连续姿态晃动并自动回中",
                "Simulate a continuous StickS3 motion gesture and return to center"))
    }

    private var commonHardwareControls: some View {
        GroupBox(t("通用 · 设备状态", "Device Status")) {
            hardwareControlRows
        }
    }

    private var hardwareControlRows: some View {
        VStack(spacing: 9) {
            HStack {
                Text(t("亮度", "Brightness"))
                Slider(value: Binding(get: { model.screenBrightnessPercent },
                                      set: { model.setScreenBrightness($0) }), in: 0...100)
                Text("\(Int(model.screenBrightnessPercent))%")
                    .monospacedDigit().frame(width: 38, alignment: .trailing)
            }
            .disabled(model.hasActiveQEMUFirmware && !model.qemuDisplaySettingsReady)
            HStack {
                Text(t("电量", "Battery"))
                Slider(value: Binding(get: { model.batteryPercent },
                                      set: { model.setBatteryPercent($0) }), in: 0...100)
                Text("\(Int(model.batteryPercent.rounded()))%")
            }
            .disabled(model.hasActiveQEMUFirmware && !model.qemuPowerControlsReady)
            HStack(spacing: 8) {
                Toggle(t("充电", "Charging"), isOn: Binding(get: { model.batteryCharging },
                                                set: { model.setBatteryCharging($0) }))
                    .fixedSize()
                    .disabled(model.hasActiveQEMUFirmware && !model.qemuPowerControlsReady)
                Toggle(t("声音", "Sound"),
                       isOn: Binding(get: { model.soundEnabled }, set: { model.setSound($0) }))
                    .fixedSize()
                    .disabled(model.hasActiveQEMUFirmware && !model.qemuAudioControlsReady)
                Spacer(minLength: 2)
                Text(t("刷新率", "FPS")).font(.caption).fixedSize()
                HStack(spacing: 3) {
                    fpsButton(30)
                    fpsButton(60)
                }
                .fixedSize()
                .disabled(model.hasActiveQEMUFirmware && !model.qemuDisplaySettingsReady)
            }
        }
    }

    private func fpsButton(_ value: Double) -> some View {
        let selected = model.fps == value
        return Button {
            model.setFPS(value)
        } label: {
            Text("\(Int(value)) FPS")
                .font(.system(size: 9, weight: .medium))
                .frame(width: 38, height: 19)
                .foregroundStyle(selected ? .primary : .secondary)
                .background(selected
                            ? (lightBackground ? .black.opacity(0.09) : .white.opacity(0.16))
                            : inactiveControlFill,
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(selected
                            ? (lightBackground ? .black.opacity(0.12) : .white.opacity(0.17))
                            : inactiveControlStroke,
                            lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Int(value)) FPS")
    }

    private func axisRow(_ name: String, value: Binding<Double>, neutralValue: Double) -> some View {
        HStack {
            Text(name)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 14)
            Slider(value: value, in: -1...1) { isEditing in
                guard !isEditing else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    value.wrappedValue = neutralValue
                }
            }
        }
    }

    private var baseScreenSize: CGSize {
        // 实体屏幕在机身坐标中始终是竖向；固件横屏帧不得改变“正放”机身。
        CGSize(width: 337.5, height: 600)
    }

    private var baseFaceSize: CGSize {
        CGSize(width: baseScreenSize.width, height: baseScreenSize.height + 65)
    }

    private var devicePanelWidth: CGFloat {
        max(410, baseFaceSize.width + 70)
    }

    private var devicePanelHeight: CGFloat {
        max(485, baseFaceSize.height + 68)
    }

    private var inspectorWidth: CGFloat {
        540
    }

    private var fixedWindowContentWidth: CGFloat {
        deviceRotationSlotWidth + 16 + inspectorWidth + 36
    }

    private var deviceDisplayScale: CGFloat {
        guard realDeviceSize else { return 1 }

        // Stick S3 正面官方尺寸为 48 × 24 mm。macOS 不提供可靠的显示器物理 DPI，
        // 这里按 72 pt/in 换算，再放大到 2 倍以保证像素内容可读，
        // 并在旋转后自动交换长短边。
        let readabilityScale = CGFloat(2.0)
        let longEdge = CGFloat(48.0 / 25.4 * 72.0) * readabilityScale
        let shortEdge = CGFloat(24.0 / 25.4 * 72.0) * readabilityScale
        let targetWidth = devicePanelWidth >= devicePanelHeight ? longEdge : shortEdge
        let targetHeight = devicePanelWidth >= devicePanelHeight ? shortEdge : longEdge
        return min(targetWidth / devicePanelWidth, targetHeight / devicePanelHeight)
    }

    private var deviceRotationSlotWidth: CGFloat {
        // 使用横竖两种方向的最大宽度，旋转时右侧控制区不会位移。
        max(410, max(baseFaceSize.width, baseFaceSize.height) + 70)
    }

    private var deviceRotationSlotHeight: CGFloat {
        // 高度占位同样固定，避免旋转时窗口最小尺寸变化。
        max(485, max(baseFaceSize.width, baseFaceSize.height) + 68)
    }

    private var contentInsets: CGFloat { 36 }

    private var deviceHorizontalOffset: CGFloat {
        model.devicePose.isQuarterTurn ? 0 : -44
    }

    private var deviceVerticalOffset: CGFloat {
        model.devicePose.isQuarterTurn ? -16 : 0
    }

    private var minimumWindowHeight: CGFloat {
        // 给左上角主题开关留出空间，竖屏固件也不会与开关重叠。
        max(720, deviceRotationSlotHeight + 90)
    }

    private var posedPixelLabel: String {
        guard model.hasRunnableFirmware else { return "-- × --" }
        let size = model.selectedProject.runtimeID
            .posedDevicePixelSize(isQuarterTurn: model.devicePose.isQuarterTurn)
        return "\(size.width) × \(size.height)"
    }

    private func poseButton(_ pose: DevicePose, symbol: String) -> some View {
        Button {
            model.setDevicePose(pose)
        } label: {
            HStack(spacing: 6) {
                Text(symbol).font(.system(size: 16, weight: .bold))
                Text(poseTitle(pose)).font(.caption.bold())
            }
            .frame(maxWidth: .infinity, minHeight: 26)
            .foregroundStyle(model.devicePose == pose ? .white : .secondary)
            .background(model.devicePose == pose ? Color(rgb: 0x267BFF) : inactiveControlFill,
                        in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .stroke(model.devicePose == pose ? .white.opacity(0.25) : inactiveControlStroke))
        }.buttonStyle(.plain)
    }

    private var inactiveControlFill: Color {
        lightBackground ? .black.opacity(0.045) : .white.opacity(0.06)
    }

    private var inactiveControlStroke: Color {
        lightBackground ? .black.opacity(0.10) : .white.opacity(0.08)
    }

    private func poseTitle(_ pose: DevicePose) -> String {
        switch pose {
        case .upright: return t("正放", "Upright")
        case .left90: return t("左转 90°", "Left 90°")
        case .right90: return t("右转 90°", "Right 90°")
        case .upsideDown: return t("反放", "Upside Down")
        }
    }

    private func deviceButtonRow(title: String, color: Color, square: Bool,
                                 button: PhysicalButton,
                                 action: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Group {
                    if square {
                        RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 17, height: 17)
                    } else {
                        Capsule().fill(color).frame(width: 34, height: 12)
                    }
                }
                Text(title).font(.caption.bold())
                Spacer()
            }
            HStack(spacing: 6) {
                gestureButton(t("单击", "Click"), clicks: 1, button: button, action: action)
                gestureButton(t("双击", "2×"), clicks: 2, button: button, action: action)
                gestureButton(t("三击", "3×"), clicks: 3, button: button, action: action)
                gestureButton(t("四击", "4×"), clicks: 4, button: button, action: action)
                gestureButton(button == .front && model.codex.recording
                              ? t("松开", "Release") : t("长按", "Hold"),
                              clicks: 5, button: button, action: action)
            }.controlSize(.mini)
        }
    }

    private func gestureButton(_ label: String, clicks: Int, button: PhysicalButton,
                               action: @escaping (Int) -> Void) -> some View {
        let supported = model.supports(button: button, clicks: clicks)
        return Button(label) { action(clicks) }
            .opacity(supported ? 1 : 0.38)
            .help(supported
                  ? t("当前固件已绑定此手势", "This gesture is mapped by the current firmware")
                  : t("当前固件未绑定；点击后仅记录 UNBOUND",
                      "Not mapped by the current firmware; clicking only records UNBOUND"))
    }

    private func chooseTestProject() {
        let panel = NSOpenPanel()
        panel.title = t("导入固件或项目", "Import Firmware or Project")
        panel.message = t("选择一个 ESP-IDF、PlatformIO 或 Arduino StickS3 源码项目文件夹。导入不会修改所选内容。",
                          "Select an ESP-IDF, PlatformIO, or Arduino StickS3 source-project folder. Importing does not modify it.")
        panel.prompt = t("导入", "Import")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        if panel.runModal() == .OK, let url = panel.url {
            model.importTestProject(at: url)
            showsProjectManager = true
        }
    }

}
