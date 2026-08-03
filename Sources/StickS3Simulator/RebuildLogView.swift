import SwiftUI

struct RebuildLogView: View {
    @ObservedObject var model: SimulatorModel
    @AppStorage("simulator.language") private var language = SimulatorLanguage.chinese.rawValue
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(t("重新载入固件", "Reload Firmware")).font(.title2.bold())
                    Text(t("只读取当前固件源码；不修改项目、Git 或真实设备。",
                           "Reads the current firmware source only; does not modify the project, Git, or a physical device."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.isRebuilding {
                    ProgressView().controlSize(.small)
                }
                Button(t("关闭", "Close")) { dismiss() }
            }
            .padding(20)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: phaseSymbol)
                        .foregroundStyle(phaseColor)
                    Text(phaseTitle).font(.headline)
                }

                ScrollView {
                    Text(model.rebuildLog.isEmpty
                         ? t("尚未开始构建。", "Build has not started.")
                         : model.rebuildLog)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(12)
                }
                .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.white.opacity(0.88))
            }
            .padding(20)
        }
        .frame(minWidth: 760, minHeight: 500)
    }

    private var phaseSymbol: String {
        switch model.rebuildPhase {
        case .idle: return "circle"
        case .failed: return "xmark.circle.fill"
        case .installing: return "checkmark.circle.fill"
        default: return "hammer.fill"
        }
    }

    private var phaseColor: Color {
        switch model.rebuildPhase {
        case .failed: return .red
        case .installing: return .green
        case .idle: return .secondary
        default: return .orange
        }
    }

    private var phaseTitle: String {
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

    private func t(_ chinese: String, _ english: String) -> String {
        simulatorText(chinese, english, language: language)
    }
}
