import Foundation

public enum SimulatorRebuildPhase: String, Codable, Sendable {
    case idle
    case preparing
    case testing
    case compiling
    case linking
    case signing
    case installing
    case failed

    public var title: String {
        switch self {
        case .idle: return "就绪"
        case .preparing: return "正在准备构建"
        case .testing: return "正在运行测试"
        case .compiling: return "正在编译最新源码"
        case .linking: return "正在生成应用"
        case .signing: return "正在校验并签名"
        case .installing: return "构建成功，正在更新并重启"
        case .failed: return "构建失败，已保留当前版本"
        }
    }
}

public struct SimulatorRebuildOutputParser: Sendable {
    public init() {}

    public func phase(for output: String, current: SimulatorRebuildPhase) -> SimulatorRebuildPhase {
        let text = output.lowercased()
        if text.contains("error:") || text.contains("fatalerror") || text.contains("test suite 'all tests' failed") {
            return .failed
        }
        if text.contains("rebuild-step:tests") || text.contains("test suite 'all tests' started") {
            return .testing
        }
        if text.contains("rebuild-step:build") || text.contains("planning build") {
            return .preparing
        }
        if text.contains("compiling ") || text.contains("building for production") {
            return .compiling
        }
        if text.contains("linking ") {
            return .linking
        }
        if text.contains("replacing existing signature") || text.contains("rebuild-step:signing") {
            return .signing
        }
        return current
    }
}

public enum SimulatorRuntimeID: String, Codable, CaseIterable, Sendable {
    case breakout
    case fruit
    case hourglass
    case hourglassLiquid
    case codex

    public var firmwareName: String {
        switch self {
        case .breakout: return "VibeStick-Neon-Brick-Pulse"
        case .fruit: return "VibeStick-Fruit-Machine"
        case .hourglass: return "VibeStick-Hourglass"
        case .hourglassLiquid: return "VibeStick-Hourglass-Liquid"
        case .codex: return "VibeStick-Codex"
        }
    }

    public static func detect(projectName: String) -> SimulatorRuntimeID? {
        let normalized = projectName.lowercased()
        return allCases.first { runtime in
            normalized == runtime.firmwareName.lowercased()
        }
    }
}

public enum SimulatorFirmwareDisplayLayout: String, Codable, Sendable {
    case fixedPortrait
    case poseAdaptive
}

public enum SimulatorFirmwareLiveDataPolicy: String, Codable, Sendable {
    case none
    case importedProjectEnvironment
}

public extension SimulatorRuntimeID {
    /// 新增适配器必须在这里明确声明屏幕布局，不允许用当前帧尺寸猜测机身方向。
    var displayLayout: SimulatorFirmwareDisplayLayout {
        switch self {
        case .codex: return .poseAdaptive
        case .breakout, .fruit, .hourglass, .hourglassLiquid: return .fixedPortrait
        }
    }

    /// 数据源也必须由适配器明确声明，不允许隐式读取开发电脑状态。
    var liveDataPolicy: SimulatorFirmwareLiveDataPolicy {
        switch self {
        case .codex: return .importedProjectEnvironment
        case .breakout, .fruit, .hourglass, .hourglassLiquid: return .none
        }
    }

    func posedDevicePixelSize(isQuarterTurn: Bool) -> (width: Int, height: Int) {
        isQuarterTurn ? (240, 135) : (135, 240)
    }
}

public enum SimulatorProjectCompatibility: String, Codable, Sendable {
    case ready
    case sourceNeedsAdapter
    case binaryOnly
    case invalid
    case missing

    public var canSimulate: Bool { self == .ready }

    public var title: String {
        switch self {
        case .ready: return "可模拟"
        case .sourceNeedsAdapter: return "源码已识别，缺少模拟接口"
        case .binaryOnly: return "仅识别，当前不可模拟"
        case .invalid: return "不是可识别的 Stick S3 项目"
        case .missing: return "原目录已不存在"
        }
    }
}

public enum SimulatorProjectOrigin: String, Codable, Sendable {
    case linked
    case managedCopy

    public var title: String {
        switch self {
        case .linked: return "本地链接"
        case .managedCopy: return "测试副本"
        }
    }
}

public struct SimulatorProjectReference: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var displayName: String
    public var sourcePath: String
    public var firmwarePath: String?
    public var origin: SimulatorProjectOrigin
    public var runtimeID: SimulatorRuntimeID?
    public var compatibility: SimulatorProjectCompatibility
    public var detail: String
    public var sourceFingerprint: String?
    public var addedAt: Date
    public var lastCheckedAt: Date

    public init(
        id: UUID = UUID(),
        displayName: String,
        sourcePath: String,
        firmwarePath: String?,
        origin: SimulatorProjectOrigin = .linked,
        runtimeID: SimulatorRuntimeID?,
        compatibility: SimulatorProjectCompatibility,
        detail: String,
        sourceFingerprint: String? = nil,
        addedAt: Date = Date(),
        lastCheckedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.sourcePath = sourcePath
        self.firmwarePath = firmwarePath
        self.origin = origin
        self.runtimeID = runtimeID
        self.compatibility = compatibility
        self.detail = detail
        self.sourceFingerprint = sourceFingerprint
        self.addedAt = addedAt
        self.lastCheckedAt = lastCheckedAt
    }
}

public enum SimulatorFirmwareSource: String, Sendable {
    case linked
    case managedCopy

    public var title: String {
        switch self {
        case .linked: return "本地项目"
        case .managedCopy: return "测试副本"
        }
    }
}

public struct SimulatorFirmwareCatalogItem: Identifiable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var runtimeID: SimulatorRuntimeID?
    public var source: SimulatorFirmwareSource
    public var sourcePath: String?
    public var projectReferenceID: UUID?
    public var compatibility: SimulatorProjectCompatibility
    public var detail: String
    public var isVisible: Bool

    public var canSimulate: Bool { compatibility.canSimulate && runtimeID != nil }
}

public struct SimulatorFirmwareCatalogComposer: Sendable {
    public init() {}

    public func compose(projects: [SimulatorProjectReference]) -> [SimulatorFirmwareCatalogItem] {
        projects.map { project in
            SimulatorFirmwareCatalogItem(
                id: "import:\(project.id.uuidString)",
                displayName: project.displayName,
                runtimeID: project.runtimeID,
                source: project.origin == .linked ? .linked : .managedCopy,
                sourcePath: project.sourcePath,
                projectReferenceID: project.id,
                compatibility: project.compatibility,
                detail: project.detail,
                isVisible: true
            )
        }
        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }

    }
}

public struct SimulatorProjectInspector {
    private let fileManager: FileManager
    private let readyProjectRoots: [SimulatorRuntimeID: String]
    private let packagedRuntimeIDs: Set<SimulatorRuntimeID>
    private let packagedFingerprints: [SimulatorRuntimeID: String]

    public init(
        fileManager: FileManager = .default,
        readyProjectRoots: [SimulatorRuntimeID: String] = [:],
        packagedRuntimeIDs: Set<SimulatorRuntimeID> = [],
        packagedFingerprints: [SimulatorRuntimeID: String] = [:]
    ) {
        self.fileManager = fileManager
        self.packagedRuntimeIDs = packagedRuntimeIDs
        self.packagedFingerprints = packagedFingerprints
        self.readyProjectRoots = readyProjectRoots.mapValues {
            URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath().path
        }
    }

    public func inspect(_ inputURL: URL) -> SimulatorProjectReference {
        let url = inputURL.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return SimulatorProjectReference(
                displayName: url.deletingPathExtension().lastPathComponent,
                sourcePath: url.path,
                firmwarePath: nil,
                runtimeID: nil,
                compatibility: .missing,
                detail: "导入时记录的路径已经不存在。"
            )
        }

        if !isDirectory.boolValue {
            let suffix = url.pathExtension.lowercased()
            if suffix == "bin" {
                return SimulatorProjectReference(
                    displayName: url.deletingPathExtension().lastPathComponent,
                    sourcePath: url.path,
                    firmwarePath: nil,
                    runtimeID: nil,
                    compatibility: .binaryOnly,
                    detail: "ESP32 二进制固件不能由当前 macOS 源码模拟器直接执行。"
                )
            }
            return SimulatorProjectReference(
                displayName: url.deletingPathExtension().lastPathComponent,
                sourcePath: url.path,
                firmwarePath: nil,
                runtimeID: nil,
                compatibility: .invalid,
                detail: "请选择项目目录，或选择用于识别的 .bin 固件。"
            )
        }

        let resolved = resolveProjectAndFirmwareRoot(url)
        guard let firmwareRoot = resolved.firmwareRoot else {
            return SimulatorProjectReference(
                displayName: url.lastPathComponent,
                sourcePath: url.path,
                firmwarePath: nil,
                runtimeID: nil,
                compatibility: .invalid,
                detail: "未找到 firmware/sticks3，且所选目录不是 ESP-IDF 固件根目录。"
            )
        }

        let projectRoot = resolved.projectRoot
        let name = projectRoot.lastPathComponent
        let runtime = SimulatorRuntimeID.detect(projectName: name)
        let hasMain = ["main.c", "main.cpp", "main.cc"].contains { file in
            fileManager.fileExists(atPath: firmwareRoot.appendingPathComponent("src/\(file)").path)
        }
        let hasCMake = fileManager.fileExists(atPath: firmwareRoot.appendingPathComponent("CMakeLists.txt").path)

        guard hasCMake && hasMain else {
            return SimulatorProjectReference(
                displayName: name,
                sourcePath: projectRoot.path,
                firmwarePath: firmwareRoot.path,
                runtimeID: nil,
                compatibility: .invalid,
                detail: "固件目录缺少 CMakeLists.txt 或 src/main.c/main.cpp。"
            )
        }

        let canonicalProjectPath = projectRoot.standardizedFileURL.resolvingSymlinksInPath().path
        let sourceFingerprint = runtime.flatMap { try? SimulatorSourceFingerprint.calculate(runtime: $0, firmwareRoot: firmwareRoot) }
        let fingerprintMatches: Bool
        if let runtime, let expected = packagedFingerprints[runtime], let sourceFingerprint {
            fingerprintMatches = expected == sourceFingerprint
        } else {
            fingerprintMatches = false
        }
        if let runtime,
           packagedRuntimeIDs.contains(runtime)
            || readyProjectRoots[runtime] == canonicalProjectPath
            || fingerprintMatches {
            return SimulatorProjectReference(
                displayName: name,
                sourcePath: projectRoot.path,
                firmwarePath: firmwareRoot.path,
                runtimeID: runtime,
                compatibility: .ready,
                detail: "当前应用由该版本源码构建；导入只保存只读目录引用。",
                sourceFingerprint: sourceFingerprint
            )
        }

        return SimulatorProjectReference(
            displayName: name,
            sourcePath: projectRoot.path,
            firmwarePath: firmwareRoot.path,
            runtimeID: runtime,
            compatibility: .sourceNeedsAdapter,
            detail: runtime == nil
                ? "项目结构有效，但尚未提供模拟器测试接口；不会自动修改源码。"
                : (sourceFingerprint == nil
                   ? "项目名称已识别，但缺少该适配器需要的源码文件。"
                   : "固件源码与当前虚拟设备中的版本不同，请点“重新载入固件”。"),
            sourceFingerprint: sourceFingerprint
        )
    }

    private func resolveProjectAndFirmwareRoot(_ url: URL) -> (projectRoot: URL, firmwareRoot: URL?) {
        let nested = url.appendingPathComponent("firmware/sticks3", isDirectory: true)
        if fileManager.fileExists(atPath: nested.appendingPathComponent("CMakeLists.txt").path) {
            return (url, nested)
        }
        if fileManager.fileExists(atPath: url.appendingPathComponent("CMakeLists.txt").path),
           fileManager.fileExists(atPath: url.appendingPathComponent("src").path) {
            if url.lastPathComponent == "sticks3", url.deletingLastPathComponent().lastPathComponent == "firmware" {
                return (url.deletingLastPathComponent().deletingLastPathComponent(), url)
            }
            return (url, url)
        }
        return (url, nil)
    }
}

public final class SimulatorProjectLibrary: @unchecked Sendable {
    public let storageURL: URL
    public let cacheRootURL: URL
    private let fileManager: FileManager
    private let inspector: SimulatorProjectInspector

    public init(
        storageURL: URL? = nil,
        cacheRootURL: URL? = nil,
        readyProjectRoots: [SimulatorRuntimeID: String] = [:],
        packagedRuntimeIDs: Set<SimulatorRuntimeID> = [],
        packagedFingerprints: [SimulatorRuntimeID: String] = [:],
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.inspector = SimulatorProjectInspector(
            fileManager: fileManager,
            readyProjectRoots: readyProjectRoots,
            packagedRuntimeIDs: packagedRuntimeIDs,
            packagedFingerprints: packagedFingerprints
        )
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Stick S3 Firmware Simulator", isDirectory: true)
        self.storageURL = storageURL ?? applicationSupport.appendingPathComponent("test-projects.json")
        self.cacheRootURL = cacheRootURL ?? applicationSupport.appendingPathComponent("TestCache", isDirectory: true)
    }

    public func load() -> [SimulatorProjectReference] {
        guard let data = try? Data(contentsOf: storageURL) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return (try? decoder.decode([SimulatorProjectReference].self, from: data)) ?? []
    }

    public func save(_ projects: [SimulatorProjectReference]) throws {
        try fileManager.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(projects)
        try data.write(to: storageURL, options: .atomic)
    }

    public func inspect(_ url: URL) -> SimulatorProjectReference {
        inspector.inspect(url)
    }

    public func refresh(_ project: SimulatorProjectReference) -> SimulatorProjectReference {
        var refreshed = inspector.inspect(URL(fileURLWithPath: project.sourcePath))
        refreshed.id = project.id
        refreshed.addedAt = project.addedAt
        return refreshed
    }

    public func merging(_ additions: [SimulatorProjectReference], into existing: [SimulatorProjectReference]) -> [SimulatorProjectReference] {
        var merged = existing
        for addition in additions {
            if let index = merged.firstIndex(where: { $0.sourcePath == addition.sourcePath }) {
                var refreshed = addition
                refreshed.id = merged[index].id
                refreshed.addedAt = merged[index].addedAt
                merged[index] = refreshed
            } else {
                merged.append(addition)
            }
        }
        return merged.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    public func clearCache(for project: SimulatorProjectReference) throws {
        let target = cacheRootURL.appendingPathComponent(project.id.uuidString, isDirectory: true)
        guard target.standardizedFileURL.path.hasPrefix(cacheRootURL.standardizedFileURL.path + "/") else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        if fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
        }
    }
}
