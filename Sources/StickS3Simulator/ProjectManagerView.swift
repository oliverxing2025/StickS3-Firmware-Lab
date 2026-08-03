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
                Button(t("开始模拟", "Start Simulation")) { simulate(item) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!item.canSimulate)

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
        guard item.canSimulate,
              let runtimeID = item.runtimeID,
              let project = VirtualProject(runtimeID: runtimeID) else { return }
        model.selectedProject = project
        model.eventText = "FIRMWARE \(project.rawValue.uppercased())"
        dismiss()
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
        case .sourceNeedsAdapter: return t("源码已识别，缺少模拟接口", "Recognized; simulator adapter required")
        case .binaryOnly: return t("仅识别，当前不可模拟", "Recognized; simulation unavailable")
        case .invalid: return t("不是可识别的 Stick S3 项目", "Unrecognized Stick S3 project")
        case .missing: return t("原目录已不存在", "Original folder is missing")
        }
    }

    private func localizedDetail(_ detail: String) -> String {
        guard language == SimulatorLanguage.english.rawValue else { return detail }
        let translations = [
            "导入时记录的路径已经不存在。": "The imported path no longer exists.",
            "ESP32 二进制固件不能由当前 macOS 源码模拟器直接执行。": "ESP32 binary firmware cannot run directly in this macOS source simulator.",
            "当前应用由该版本源码构建；导入只保存只读目录引用。": "This app was built from this source version; import stores only a read-only folder reference.",
            "固件源码与当前虚拟设备中的版本不同，请点“重新载入固件”。": "The firmware source differs from the embedded version. Choose Reload Firmware.",
        ]
        return translations[detail] ?? detail
    }

    private func statusSymbol(_ status: SimulatorProjectCompatibility) -> String {
        switch status {
        case .ready: return "checkmark.circle.fill"
        case .sourceNeedsAdapter: return "wrench.and.screwdriver.fill"
        case .binaryOnly: return "cpu"
        case .invalid, .missing: return "exclamationmark.triangle.fill"
        }
    }

    private func statusColor(_ status: SimulatorProjectCompatibility) -> Color {
        switch status {
        case .ready: return .green
        case .sourceNeedsAdapter, .binaryOnly: return .orange
        case .invalid, .missing: return .red
        }
    }
}
