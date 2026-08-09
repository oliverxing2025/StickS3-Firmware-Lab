import SimulatorSupport
import SwiftUI

struct HardwareCalibrationView: View {
    let projectName: String
    let projectID: UUID
    let onSave: (UUID, StickS3VirtualHardwareProfile) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var profile: StickS3VirtualHardwareProfile

    init(projectName: String, projectID: UUID, profile: StickS3VirtualHardwareProfile,
         onSave: @escaping (UUID, StickS3VirtualHardwareProfile) -> Void) {
        self.projectName = projectName
        self.projectID = projectID
        self.onSave = onSave
        _profile = State(initialValue: profile)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("虚拟硬件校准").font(.title2.bold())
                    Text(projectName).foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }
                Button("保存并标记已验证") {
                    onSave(projectID, profile)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }

            Text("请先启动固件，依次测试左右、上下和两颗按键。选择固件实际读取的传感器轴；若方向相反，打开“反向”。实验台对外始终显示 X=左右、Y=上下、Z=正反。")
                .font(.callout)
                .padding(10)
                .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

            Form {
                Section("传感器轴") {
                    axisRow("左右（逻辑 X）", binding: $profile.logicalX)
                    axisRow("上下（逻辑 Y）", binding: $profile.logicalY)
                    axisRow("正反（逻辑 Z）", binding: $profile.logicalZ)
                }
                Section("两颗按键") {
                    Stepper("蓝色前键：GPIO \(profile.frontButton.gpio)", value: $profile.frontButton.gpio, in: 0...48)
                    Toggle("蓝色前键低电平有效", isOn: $profile.frontButton.activeLow)
                    Stepper("灰色侧键：GPIO \(profile.sideButton.gpio)", value: $profile.sideButton.gpio, in: 0...48)
                    Toggle("灰色侧键低电平有效", isOn: $profile.sideButton.activeLow)
                }
                Section("屏幕") {
                    Picker("实际方向", selection: $profile.displayRotation) {
                        ForEach(StickS3DisplayRotation.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
            }
            .formStyle(.grouped)

            Text("校准只保存在本机，绑定当前源码指纹 \(profile.sourceFingerprint.prefix(12))…；源码变化后会自动重新检测。原项目不会被修改。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 650, height: 650)
    }

    private func axisRow(_ title: String, binding: Binding<StickS3AxisBinding>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Picker("轴", selection: binding.sensorAxis) {
                ForEach(StickS3SensorAxis.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden().frame(width: 90)
            Toggle("反向", isOn: binding.inverted).toggleStyle(.checkbox)
        }
    }
}

private extension Binding where Value == StickS3AxisBinding {
    var sensorAxis: Binding<StickS3SensorAxis> {
        .init(get: { wrappedValue.sensorAxis }, set: { wrappedValue.sensorAxis = $0 })
    }
    var inverted: Binding<Bool> {
        .init(get: { wrappedValue.inverted }, set: { wrappedValue.inverted = $0 })
    }
}
