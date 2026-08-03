import AppKit
import SimulatorSupport
import SwiftUI

struct ProjectManagerView: View {
    @ObservedObject var model: SimulatorModel
    @AppStorage("simulator.language") private var language = SimulatorLanguage.chinese.rawValue
    @Environment(\.dismiss) private var dismiss
    @State private var pendingRemoval: SimulatorFirmwareCatalogItem?
    @State private var shownPath: String?

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
                    ScrollView {
                        Text(model.qemuLog.isEmpty ? t("等待串口输出…", "Waiting for serial output…") : model.qemuLog)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 88)
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
            }
        }
        .frame(minWidth: 900, minHeight: 480)
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
    }

    private var buildToolsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
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
                Spacer()
                Button(t("PlatformIO 下载", "Download PlatformIO")) { model.openPlatformIODownload() }
                Button(t("重新检测", "Check Again")) { model.refreshBuildToolStatus() }
            }
            HStack {
                Text(model.espIDFIsAvailable
                     ? t("ESP-IDF 可选扩展：已检测到", "Optional ESP-IDF extension: detected")
                     : t("ESP-IDF 可选扩展：未安装", "Optional ESP-IDF extension: not installed"))
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button(t("ESP-IDF 下载", "Download ESP-IDF")) { model.openESPIDFDownload() }
                    .controlSize(.small)
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
                Text(compatibilityTitle(item.compatibility))
                    .font(.callout.bold()).foregroundStyle(statusColor(item.compatibility))
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
                    .disabled(!item.canSimulate && !model.canStartQEMU(item))

                Button(t("显示路径", "Show Path")) { showPath(item) }
                    .buttonStyle(.bordered)
                    .disabled(item.sourcePath == nil)

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
        } else if let referenceID = item.projectReferenceID, model.canStartQEMU(item) {
            model.startQEMU(referenceID: referenceID)
        }
    }

    private func startButtonTitle(_ item: SimulatorFirmwareCatalogItem) -> String {
        t("开始模拟", "Start Simulation")
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

    private func compatibilityTitle(_ status: SimulatorProjectCompatibility) -> String {
        switch status {
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
        case .ready: return .green
        case .sourceNeedsAdapter: return .orange
        case .invalid, .missing: return .red
        }
    }
}
