import CryptoKit
import Foundation

public enum StickS3HardwareCompatibility: String, Codable, CaseIterable, Sendable {
    case verified
    case autoDetected
    case needsCalibration
    case unsupported

    public var title: String {
        switch self {
        case .verified: return "已验证"
        case .autoDetected: return "自动识别"
        case .needsCalibration: return "需要校准"
        case .unsupported: return "不支持"
        }
    }
}

public enum StickS3SensorAxis: Int8, Codable, CaseIterable, Sendable {
    case x = 0
    case y = 1
    case z = 2

    public var title: String { ["X", "Y", "Z"][Int(rawValue)] }
}

public struct StickS3AxisBinding: Codable, Equatable, Sendable {
    public var sensorAxis: StickS3SensorAxis
    public var inverted: Bool

    public init(_ sensorAxis: StickS3SensorAxis, inverted: Bool = false) {
        self.sensorAxis = sensorAxis
        self.inverted = inverted
    }

    public var wireValue: Int8 {
        let magnitude = sensorAxis.rawValue + 1
        return inverted ? -magnitude : magnitude
    }

    public init?(wireValue: Int8) {
        guard wireValue != 0,
              let axis = StickS3SensorAxis(rawValue: abs(wireValue) - 1) else { return nil }
        self.init(axis, inverted: wireValue < 0)
    }
}

public struct StickS3ButtonHardware: Codable, Equatable, Sendable {
    public var gpio: Int
    public var activeLow: Bool

    public init(gpio: Int, activeLow: Bool = true) {
        self.gpio = gpio
        self.activeLow = activeLow
    }
}

public enum StickS3DisplayRotation: Int, Codable, CaseIterable, Sendable {
    case degrees0 = 0
    case degrees90 = 90
    case degrees180 = 180
    case degrees270 = 270

    public var title: String { "\(rawValue)°" }
    public var wireValue: UInt8 { UInt8(rawValue / 90) }
}

public struct StickS3VirtualHardwareProfile: Codable, Equatable, Sendable {
    public var sourceFingerprint: String
    public var compatibility: StickS3HardwareCompatibility
    public var capabilities: StickS3VirtualBoardCapabilities
    public var logicalX: StickS3AxisBinding
    public var logicalY: StickS3AxisBinding
    public var logicalZ: StickS3AxisBinding
    public var frontButton: StickS3ButtonHardware
    public var sideButton: StickS3ButtonHardware
    public var displayRotation: StickS3DisplayRotation
    public var detectionNote: String

    public init(
        sourceFingerprint: String,
        compatibility: StickS3HardwareCompatibility,
        capabilities: StickS3VirtualBoardCapabilities,
        logicalX: StickS3AxisBinding = .init(.x),
        logicalY: StickS3AxisBinding = .init(.y),
        logicalZ: StickS3AxisBinding = .init(.z),
        frontButton: StickS3ButtonHardware = .init(gpio: 11),
        sideButton: StickS3ButtonHardware = .init(gpio: 12),
        displayRotation: StickS3DisplayRotation = .degrees0,
        detectionNote: String = ""
    ) {
        self.sourceFingerprint = sourceFingerprint
        self.compatibility = compatibility
        self.capabilities = capabilities
        self.logicalX = logicalX
        self.logicalY = logicalY
        self.logicalZ = logicalZ
        self.frontButton = frontButton
        self.sideButton = sideButton
        self.displayRotation = displayRotation
        self.detectionNote = detectionNote
    }

    public static func unsupported(fingerprint: String, note: String) -> Self {
        .init(sourceFingerprint: fingerprint, compatibility: .unsupported,
              capabilities: [], detectionNote: note)
    }

    public func sensorVector(logicalX x: Float, logicalY y: Float, logicalZ z: Float)
        -> StickS3VirtualBoardMotionVector {
        var raw = [Float](repeating: 0, count: 3)
        for (value, binding) in [(x, logicalX), (y, logicalY), (z, logicalZ)] {
            raw[Int(binding.sensorAxis.rawValue)] += binding.inverted ? -value : value
        }
        return .init(x: raw[0], y: raw[1], z: raw[2])
    }
}

public enum StickS3ProjectSourceFingerprint {
    private static let skipped = Set([".git", ".pio", ".build", "build", "managed_components"])

    public static func calculate(at root: URL, fileManager: FileManager = .default) throws -> String {
        var hasher = SHA256()
        guard let enumerator = fileManager.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]) else {
            throw StickS3FirmwareBuildPlanError.firmwarePathMissing
        }
        var files: [(String, URL)] = []
        for case let entry as URL in enumerator {
            let values = try entry.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values.isDirectory == true {
                if skipped.contains(entry.lastPathComponent) { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true else { continue }
            let relative = String(entry.path.dropFirst(root.path.count + 1))
            files.append((relative, entry))
        }
        for (relative, file) in files.sorted(by: { $0.0 < $1.0 }) {
            hasher.update(data: Data(relative.utf8)); hasher.update(data: Data([0]))
            hasher.update(data: try Data(contentsOf: file, options: .mappedIfSafe)); hasher.update(data: Data([0]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public struct StickS3VirtualHardwareDetector: Sendable {
    public init() {}

    public func detect(project: SimulatorProjectReference) -> StickS3VirtualHardwareProfile {
        guard let firmwarePath = project.firmwarePath else {
            return .unsupported(fingerprint: "", note: "固件源码目录不存在。")
        }
        let root = URL(fileURLWithPath: firmwarePath, isDirectory: true)
        let fingerprint = (try? StickS3ProjectSourceFingerprint.calculate(at: root)) ?? ""
        let source = sourceText(at: root)
        var capabilities: StickS3VirtualBoardCapabilities = []
        if source.contains("st7789") || source.contains("m5gfx") || source.contains("esp_lcd") { capabilities.insert(.display) }
        if source.contains("gpio_num_11") || source.contains("gpio_num_12")
            || source.contains("btn") || source.contains("button") { capabilities.insert(.buttons) }
        if source.contains("bmi270") || source.contains("accel") || source.contains("getimudata")
            || source.contains("imu") { capabilities.insert(.bmi270) }
        if source.contains("battery_level") || source.contains("battery_charging")
            || source.contains("usb_powered") { capabilities.insert(.power) }
        if source.contains("fruit_audio") || source.contains("i2s")
            || source.contains("speaker_set_enabled") || source.contains("esp_codec_dev") {
            capabilities.insert(.audio)
        }
        guard !capabilities.isEmpty else {
            return .unsupported(fingerprint: fingerprint, note: "未找到可桥接的屏幕、按键或 BMI270 访问。")
        }

        let detectedFront = detectGPIO(near: ["front", "primary", "btn_a", "button_a"], source: source)
        let detectedSide = detectGPIO(near: ["side", "secondary", "btn_b", "button_b"], source: source)
        let front = detectedFront ?? 11
        let side = detectedSide ?? 12
        let activeLow = source.contains("!gpio_get_level") || source.contains("gpio_pullup")
            || source.contains("pull_up") || source.contains("active_low")
            || source.contains("active_level=0") || source.contains("active_level = 0")
        let rotation: StickS3DisplayRotation = source.contains("rotation(3") || source.contains("rotation = 3")
            ? .degrees270 : source.contains("rotation(2") || source.contains("rotation = 2")
            ? .degrees180 : source.contains("rotation(1") || source.contains("rotation = 1")
            ? .degrees90 : .degrees0

        // Static analysis only accepts an axis assignment when source intent is explicit.
        // Ambiguous IMU use is surfaced for calibration instead of guessing from a project name.
        let xBinding = directionalAxis(
            positiveDirection: "right", negativeDirection: "left", source: source)
            ?? explicitAxis(for: ["horizontal_axis", "logical_x", "left_right_axis"], source: source)
        let yBinding = directionalAxis(
            positiveDirection: "up", negativeDirection: "down", source: source)
            ?? explicitAxis(for: ["vertical_axis", "logical_y", "up_down_axis"], source: source)
        let needsMotionCalibration = capabilities.contains(.bmi270) && (xBinding == nil || yBinding == nil)
        let needsButtonCalibration = capabilities.contains(.buttons)
            && (detectedFront == nil || detectedSide == nil)
        let status: StickS3HardwareCompatibility = needsMotionCalibration || needsButtonCalibration
            ? .needsCalibration : .autoDetected
        let note = status == .needsCalibration
            ? "已识别实际能力，但传感器方向或按键定义不够明确。"
            : "已从源码明确识别轴向、按键和屏幕配置。"
        return .init(
            sourceFingerprint: fingerprint, compatibility: status, capabilities: capabilities,
            logicalX: xBinding ?? .init(.x), logicalY: yBinding ?? .init(.y), logicalZ: .init(.z),
            frontButton: .init(gpio: front, activeLow: activeLow),
            sideButton: .init(gpio: side, activeLow: activeLow),
            displayRotation: rotation, detectionNote: note)
    }

    private func sourceText(at root: URL) -> String {
        let extensions = Set(["c", "cc", "cpp", "h", "hpp", "ino", "ini", "yml", "yaml", "txt"])
        let skipped = Set(["build", ".build", ".pio", "managed_components", ".git",
                           ".sticks3-virtual-board"])
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return "" }
        var result = ""
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values?.isDirectory == true {
                if skipped.contains(file.lastPathComponent) { enumerator.skipDescendants() }
                continue
            }
            guard values?.isRegularFile == true,
                  extensions.contains(file.pathExtension.lowercased()) else { continue }
            guard result.utf8.count < 4_000_000,
                  let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            result += "\n" + text.lowercased()
        }
        return result
    }

    private func detectGPIO(near labels: [String], source: String) -> Int? {
        for label in labels {
            let patterns = [
                #"#define\s+\w*\#(label)\w*\s+(\d+)"#,
                #"\#(label)[^\n]{0,100}gpio_num\D{0,20}(\d+)"#,
            ]
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
                   let range = Range(match.range(at: 1), in: source) { return Int(source[range]) }
            }
        }
        return nil
    }

    private func directionalAxis(
        positiveDirection: String, negativeDirection: String, source: String
    ) -> StickS3AxisBinding? {
        for axis in ["x", "y", "z"] {
            let positiveFirst = #"motion_\#(axis)\s*>\s*0\s*\?\s*event_(?:motion_)?\#(positiveDirection)\s*:\s*event_(?:motion_)?\#(negativeDirection)"#
            let negativeFirst = #"motion_\#(axis)\s*>\s*0\s*\?\s*event_(?:motion_)?\#(negativeDirection)\s*:\s*event_(?:motion_)?\#(positiveDirection)"#
            let sensorAxis: StickS3SensorAxis = axis == "x" ? .x : axis == "y" ? .y : .z
            if source.range(of: positiveFirst, options: .regularExpression) != nil {
                return .init(sensorAxis)
            }
            if source.range(of: negativeFirst, options: .regularExpression) != nil {
                return .init(sensorAxis, inverted: true)
            }
        }
        return nil
    }

    private func explicitAxis(for labels: [String], source: String) -> StickS3AxisBinding? {
        for label in labels {
            let pattern = #"\#(label)[^\n]{0,120}(?:accel[._]|\b)([xyz])\b"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
                  let range = Range(match.range(at: 1), in: source) else { continue }
            let axis: StickS3SensorAxis = source[range] == "x" ? .x : source[range] == "y" ? .y : .z
            let prefix = String(source[Range(match.range, in: source)!])
            return .init(axis, inverted: prefix.contains("-accel") || prefix.contains("= -"))
        }
        return nil
    }
}

public struct StickS3HardwareProfileStore {
    public let storageURL: URL
    private let fileManager: FileManager

    public init(storageURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Stick S3 Firmware Simulator", isDirectory: true)
        self.storageURL = storageURL ?? root.appendingPathComponent("hardware-profiles.json")
    }

    public func load(fingerprint: String) -> StickS3VirtualHardwareProfile? {
        guard !fingerprint.isEmpty, let data = try? Data(contentsOf: storageURL),
              let profiles = try? JSONDecoder().decode([String: StickS3VirtualHardwareProfile].self, from: data) else { return nil }
        return profiles[fingerprint]
    }

    public func save(_ profile: StickS3VirtualHardwareProfile) throws {
        var profiles: [String: StickS3VirtualHardwareProfile] = [:]
        if let data = try? Data(contentsOf: storageURL) {
            profiles = (try? JSONDecoder().decode([String: StickS3VirtualHardwareProfile].self, from: data)) ?? [:]
        }
        profiles[profile.sourceFingerprint] = profile
        try fileManager.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profiles).write(to: storageURL, options: .atomic)
    }
}
