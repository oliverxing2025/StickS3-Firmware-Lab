import AppKit
import SimulatorSupport
import SwiftUI

struct ProjectManagerView: View {
    @ObservedObject var model: SimulatorModel
    @AppStorage("simulator.language") private var language = SimulatorLanguage.chinese.rawValue
    @Environment(\.dismiss) private var dismiss
    @State private var pendingRemoval: SimulatorFirmwareCatalogItem?
    @State private var shownPath: String?
    @State private var showsBuildDetails = false
    @State private var dismissWhenQEMURuns = false
    @State private var calibrationItem: SimulatorFirmwareCatalogItem?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(t("固件管理", "Firmware Manager")).font(.title2.bold())
                    Text(t("只显示你主动导入的项目；删除条目不修改原始源码或真实设备。",
                           "Only explicitly imported projects are shown. Removing an entry does not modify its source or a physical device."))
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(t("关闭", "Close")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(20)

            Divider()

            buildToolsSection

            Divider()

            if model.firmwareCatalog.isEmpty {
                ContentUnavailableView(
                    t("尚未导入固件", "No Firmware Imported"),
                    systemImage: "shippingbox",
                    description: Text(t("返回主界面选择“导入固件或项目”。",
                                        "Return to the main window and choose Import Firmware or Project."))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.firmwareCatalog) { item in
                    firmwareRow(item).padding(.vertical, 5)
                }
                .listStyle(.inset)
            }

            if !model.projectLibraryMessage.isEmpty {
                Divider()
                Text(localizedSimulatorMessage(model.projectLibraryMessage, language: language))
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.vertical, 10)
            }
            if model.qemuFirmwareName != nil || !model.qemuLog.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(qemuStateTitle, systemImage: "cpu")
                            .font(.callout.bold())
                        Spacer()
                        if model.qemuState.isActive {
                            Button(t("停止模拟", "Stop Simulation")) { model.stopQEMU() }
                        }
                    }
                    HStack(spacing: 10) {
                        Group {
                            if let progress = qemuProgress {
                                ProgressView(value: progress)
                            } else {
                                ProgressView()
                            }
                        }
                        .progressViewStyle(.linear)
                        Text(qemuProgressCaption)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 46, alignment: .trailing)
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showsBuildDetails.toggle()
                            }
                        } label: {
                            Label(showsBuildDetails
                                  ? t("收起详情", "Hide Details")
                                  : t("构建详情", "Build Details"),
                                  systemImage: showsBuildDetails ? "chevron.up" : "chevron.down")
                        }
                        .buttonStyle(.bordered)
                    }
                    if showsBuildDetails {
                        ScrollView {
                            Text(model.qemuLog.isEmpty ? t("等待串口输出…", "Waiting for serial output…") : model.qemuLog)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 120)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
            }
        }
        .frame(minWidth: 900, minHeight: 480)
        .onChange(of: model.qemuState) { _, state in
            if dismissWhenQEMURuns && state == .running {
                dismissWhenQEMURuns = false
                dismiss()
            } else if state == .failed || state == .stopped || state == .unavailable {
                dismissWhenQEMURuns = false
            }
        }
        .confirmationDialog(
            t("从固件列表删除？", "Remove from Firmware List?"),
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { item in
            Button(t("删除 \(item.displayName)", "Remove \(item.displayName)"), role: .destructive) {
                if let referenceID = item.projectReferenceID {
                    model.removeTestProject(id: referenceID)
                }
                pendingRemoval = nil
            }
            Button(t("取消", "Cancel"), role: .cancel) { pendingRemoval = nil }
        } message: { _ in
            Text(t("会删除模拟器中的目录引用和测试缓存，原项目保持不变。需要时可以重新导入。",
                   "This removes the simulator reference and test cache. The original project remains unchanged and can be imported again."))
        }
        .alert(
            t("项目路径", "Project Path"),
            isPresented: Binding(
                get: { shownPath != nil },
                set: { if !$0 { shownPath = nil } }
            )
        ) {
            Button(t("复制路径", "Copy Path")) {
                guard let shownPath else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(shownPath, forType: .string)
            }
            Button(t("关闭", "Close"), role: .cancel) { shownPath = nil }
        } message: {
            Text(shownPath ?? "")
        }
        .sheet(item: $calibrationItem) { item in
            if let id = item.projectReferenceID, let profile = item.hardwareProfile {
                HardwareCalibrationView(projectName: item.displayName, projectID: id, profile: profile) {
                    model.saveHardwareCalibration(projectID: $0, profile: $1)
                }
            }
        }
    }

    private var buildToolsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(t("本机构建环境", "Local Build Environments"))
                    .font(.callout.bold())
                Spacer()
                Button(t("PlatformIO 下载", "Download PlatformIO")) {
                    model.openPlatformIODownload()
                }
                Button(t("ESP-IDF 下载", "Download ESP-IDF")) {
                    model.openESPIDFDownload()
                }
                Button(t("重新检测", "Check Again")) { model.refreshBuildToolStatus() }
            }
            HStack(spacing: 10) {
                Image(systemName: model.platformIOIsAvailable ? "checkmark.circle.fill" : "arrow.down.circle")
                    .foregroundStyle(model.platformIOIsAvailable ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Arduino / PlatformIO 构建工具", "Arduino / PlatformIO Build Tool"))
                        .font(.callout.bold())
                    Text(model.platformIOIsAvailable
                         ? t("已检测到 PlatformIO；它会共用已下载的基础组件。",
                             "PlatformIO detected; it reuses downloaded base components.")
                         : t("尚未安装。普通 Arduino/PlatformIO 源码工程需要先自行下载安装。",
                             "Not installed. Install it before building Arduino/PlatformIO source projects."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                Image(systemName: model.espIDFIsAvailable ? "checkmark.circle.fill" : "arrow.down.circle")
                    .foregroundStyle(model.espIDFIsAvailable ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("ESP-IDF 构建工具", "ESP-IDF Build Tool"))
                        .font(.callout.bold())
                    Text(model.espIDFIsAvailable
                         ? t("已检测到 ESP-IDF；ESP-IDF 源码项目使用它。",
                             "ESP-IDF detected; ESP-IDF source projects use it.")
                         : t("尚未安装。只有 ESP-IDF 源码项目需要先安装它。",
                             "Not installed. Install it before building ESP-IDF source projects."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    private func firmwareRow(_ item: SimulatorFirmwareCatalogItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusSymbol(item.compatibility))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(statusColor(item.compatibility))
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(item.displayName).font(.headline)
                    Text(sourceTitle(item.source))
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.secondary.opacity(0.12), in: Capsule())
                }
                Text(compatibilityTitle(item))
                    .font(.callout.bold()).foregroundStyle(statusColor(item.compatibility))
                if let profile = item.hardwareProfile {
                    Label(profile.compatibility.title,
                          systemImage: hardwareStatusSymbol(profile.compatibility))
                        .font(.caption.bold())
                        .foregroundStyle(hardwareStatusColor(profile.compatibility))
                    Text(profile.detectionNote).font(.caption).foregroundStyle(.secondary)
                }
                Text(localizedDetail(item.detail)).font(.callout).foregroundStyle(.secondary)
                if let sourcePath = item.sourcePath {
                    Text(sourcePath)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button(startButtonTitle(item)) { simulate(item) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!item.canSimulate
                              && !item.requiresEmbeddedReload
                              && !model.canStartQEMU(item))

                Button(t("显示路径", "Show Path")) { showPath(item) }
                    .buttonStyle(.bordered)
                    .disabled(item.sourcePath == nil)

                if let profile = item.hardwareProfile,
                   profile.compatibility == .needsCalibration || profile.compatibility == .verified {
                    Button(profile.compatibility == .verified
                           ? t("重新校准", "Recalibrate")
                           : t("校准", "Calibrate")) {
                        calibrationItem = item
                    }
                    .buttonStyle(.bordered)
                }

                Button(t("从固件列表删除", "Remove from List"), role: .destructive) {
                    pendingRemoval = item
                }
                .buttonStyle(.bordered)
                .disabled(item.projectReferenceID == nil)
            }
            .controlSize(.regular)
        }
    }

    private func simulate(_ item: SimulatorFirmwareCatalogItem) {
        if item.canSimulate,
           let runtimeID = item.runtimeID,
           let project = VirtualProject(runtimeID: runtimeID) {
            model.stopQEMU()
            model.selectedProject = project
            model.eventText = "FIRMWARE \(project.rawValue.uppercased())"
            dismiss()
        } else if item.requiresEmbeddedReload,
                  let runtimeID = item.runtimeID,
                  let project = VirtualProject(runtimeID: runtimeID) {
            model.stopQEMU()
            model.selectedProject = project
            model.rebuildSimulator()
            dismiss()
        } else if let referenceID = item.projectReferenceID, model.canStartQEMU(item) {
            dismissWhenQEMURuns = true
            model.startQEMU(referenceID: referenceID)
        }
    }

    private func startButtonTitle(_ item: SimulatorFirmwareCatalogItem) -> String {
        if item.requiresEmbeddedReload {
            return t("重新载入固件", "Reload Firmware")
        }
        return t("开始模拟", "Start Simulation")
    }

    private var qemuStateTitle: String {
        let name = model.qemuFirmwareName ?? t("固件", "Firmware")
        switch model.qemuState {
        case .unavailable: return t("模拟运行时不可用", "Simulation runtime unavailable")
        case .stopped: return t("模拟已停止：\(name)", "Simulation stopped: \(name)")
        case .starting: return t("正在构建并启动：\(name)", "Building and starting: \(name)")
        case .running: return t("固件正在运行：\(name)", "Firmware running: \(name)")
        case .failed: return t("固件启动失败：\(name)", "Firmware failed to start: \(name)")
        }
    }

    private var qemuProgress: Double? {
        if model.qemuState == .running { return 1 }
        return SimulatorRebuildOutputParser().fraction(for: model.qemuLog)
    }

    private var qemuProgressCaption: String {
        if let progress = qemuProgress {
            return "\(Int((progress * 100).rounded()))%"
        }
        switch model.qemuState {
        case .starting: return t("准备中", "Starting")
        case .failed: return t("失败", "Failed")
        case .stopped: return t("已停止", "Stopped")
        case .unavailable: return t("不可用", "Unavailable")
        case .running: return "100%"
        }
    }

    private func showPath(_ item: SimulatorFirmwareCatalogItem) {
        shownPath = item.sourcePath
    }

    private func t(_ chinese: String, _ english: String) -> String {
        simulatorText(chinese, english, language: language)
    }

    private func sourceTitle(_ source: SimulatorFirmwareSource) -> String {
        switch source {
        case .linked: return t("本地项目", "Local Project")
        case .managedCopy: return t("测试副本", "Test Copy")
        }
    }

    private func compatibilityTitle(_ item: SimulatorFirmwareCatalogItem) -> String {
        if item.requiresEmbeddedReload {
            return t("源码已更新，需要重新载入固件", "Source updated; firmware reload required")
        }
        switch item.compatibility {
        case .ready: return t("可模拟", "Ready")
        case .sourceNeedsAdapter: return t("源码已识别，可自动生成模拟接口", "Recognized; simulator adapter can be generated automatically")
        case .invalid: return t("不是可识别的 Stick S3 项目", "Unrecognized Stick S3 project")
        case .missing: return t("原目录已不存在", "Original folder is missing")
        }
    }

    private func localizedDetail(_ detail: String) -> String {
        guard language == SimulatorLanguage.english.rawValue else { return detail }
        let translations = [
            "导入时记录的路径已经不存在。": "The imported path no longer exists.",
            "当前产品只导入 StickS3 源码工程目录，不导入已编译固件文件。": "This product imports StickS3 source-project directories, not precompiled firmware files.",
            "当前应用由该版本源码构建；导入只保存只读目录引用。": "This app was built from this source version; import stores only a read-only folder reference.",
            "固件源码与当前虚拟设备中的版本不同，请点“重新载入固件”。": "The firmware source differs from the embedded version. Choose Reload Firmware.",
            "已识别 PlatformIO/Arduino StickS3 工程；点击“开始模拟”后会在私有副本中自动生成模拟接口，原项目不会被修改。": "PlatformIO/Arduino StickS3 project recognized. Start Simulation automatically generates the simulator interface in a private copy; the original project is not modified.",
            "已识别 Arduino StickS3 工程；点击“开始模拟”后会在私有副本中自动生成模拟接口，原项目不会被修改。": "Arduino StickS3 project recognized. Start Simulation automatically generates the simulator interface in a private copy; the original project is not modified.",
            "已识别 ESP-IDF StickS3 工程；点击“开始模拟”后会在私有副本中自动生成模拟接口，原项目不会被修改。": "ESP-IDF StickS3 project recognized. Start Simulation automatically generates the simulator interface in a private copy; the original project is not modified.",
            "已找到 PlatformIO 工程，但未确认它以 M5Stack StickS3 为目标。": "A PlatformIO project was found, but its M5Stack StickS3 target could not be confirmed.",
            "已找到 Arduino 工程，但未确认它使用 M5Stack StickS3/M5Unified。": "An Arduino project was found, but M5Stack StickS3/M5Unified usage could not be confirmed.",
        ]
        return translations[detail] ?? detail
    }

    private func statusSymbol(_ status: SimulatorProjectCompatibility) -> String {
        switch status {
        case .ready: return "checkmark.circle.fill"
        case .sourceNeedsAdapter: return "wrench.and.screwdriver.fill"
        case .invalid, .missing: return "exclamationmark.triangle.fill"
        }
    }

    private func statusColor(_ status: SimulatorProjectCompatibility) -> Color {
        switch status {
        case .ready, .sourceNeedsAdapter: return .green
        case .invalid, .missing: return .red
        }
    }

    private func hardwareStatusSymbol(_ status: StickS3HardwareCompatibility) -> String {
        switch status {
        case .verified: return "checkmark.seal.fill"
        case .autoDetected: return "wand.and.stars"
        case .needsCalibration: return "scope"
        case .unsupported: return "xmark.octagon.fill"
        }
    }

    private func hardwareStatusColor(_ status: StickS3HardwareCompatibility) -> Color {
        switch status {
        case .verified, .autoDetected: return .green
        case .needsCalibration: return .orange
        case .unsupported: return .red
        }
    }
}
