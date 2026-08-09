import AppKit
import AgentHubCore
import BreakoutCore
import CodexCore
import Foundation
import HourglassCore
import HourglassLiquidCore
import SimulatorSupport

enum VirtualProject: String, CaseIterable, Identifiable {
    case breakout = "Neon Brick Pulse"
    case hourglass = "沙漏"
    case hourglassLiquid = "液态沙漏"
    case codex = "VibeStick-Codex"
    case agentHub = "VibeStick-Agent-Hub"
    var id: String { rawValue }

    var runtimeID: SimulatorRuntimeID {
        switch self {
        case .breakout: return .breakout
        case .hourglass: return .hourglass
        case .hourglassLiquid: return .hourglassLiquid
        case .codex: return .codex
        case .agentHub: return .agentHub
        }
    }

    var firmwareName: String {
        switch self {
        case .breakout: return "VibeStick-Neon-Brick-Pulse"
        case .hourglass: return "VibeStick-Hourglass"
        case .hourglassLiquid: return "VibeStick-Hourglass-Liquid"
        case .codex: return "VibeStick-Codex"
        case .agentHub: return "VibeStick-Agent-Hub"
        }
    }

    var orientationHint: String {
        switch self {
        case .breakout, .hourglass, .hourglassLiquid: return "135 × 240 竖屏固件"
        case .codex, .agentHub: return "135 × 240 正放 · 240 × 135 横放自适应固件"
        }
    }

    var fidelityStatus: String {
        "固件画面 · 实体按键 · 姿态输入"
    }

    init?(runtimeID: SimulatorRuntimeID) {
        switch runtimeID {
        case .breakout: self = .breakout
        case .hourglass: self = .hourglass
        case .hourglassLiquid: self = .hourglassLiquid
        case .codex: self = .codex
        case .agentHub: self = .agentHub
        }
    }
}

enum DevicePose: String, CaseIterable, Identifiable {
    case upright = "正放"
    case left90 = "左转 90°"
    case right90 = "右转 90°"
    case upsideDown = "反放"

    var id: String { rawValue }
    var angle: Double {
        switch self {
        case .upright: return 0
        case .left90: return -90
        case .right90: return 90
        case .upsideDown: return 180
        }
    }
    var isQuarterTurn: Bool { self == .left90 || self == .right90 }
}

enum PhysicalButton: String { case front = "FRONT", side = "SIDE" }

enum DeviceShakeGesture: String {
    case horizontal = "HORIZONTAL"
    case vertical = "VERTICAL"
}

struct CodexMockState {
    var status = "OFFLINE"
    var quota5h = 0.0
    var quota7d = 0.0
    var reset5hMinutes = 0
    var reset7dMinutes = 0
    var monthCost = 0.0
    var monthTokens = 0
    var todayUsedPercent = 0
    var todayTokens = 0
    var runningTasks = 0
    var waitingTasks = 0
    var finishedTasks = 0
    var quota5hValid = false
    var reset5hValid = false
    var quota7dValid = false
    var reset7dValid = false
    var monthCostValid = false
    var monthTokensValid = false
    var todayUsedPercentValid = false
    var todayTokensValid = false
    var quotaStale = false
    var quotaUpdatedAt = ""
    var project = "vibestick"
    var battery = 86.0
    var charging = true
    var recording = false
    var time = "--:--"
    var date = "--- --"
    var weekday = "---."
}

struct BrickViewData: Identifiable {
    let id: Int
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let color: UInt32
    let type: UInt8
    let hits: UInt8
    let active: Bool
}

@MainActor
final class SimulatorModel: ObservableObject {
    static let screenWidth: Int32 = 135
    static let screenHeight: Int32 = 240
    static let agentHubProviderIDs = ["codex", "claude-code", "kimi-code"]
    static func agentHubUsesCodexLiveData(providerIndex: Int32) -> Bool {
        providerIndex == 0
    }

    @Published var snapshot = BreakoutSnapshot()
    @Published var ball = BreakoutBallSnapshot()
    @Published var paddle = BreakoutPaddleSnapshot()
    @Published var bricks: [BrickViewData] = []
    @Published var breakoutFrameRGBA = Data()
    @Published var hourglassFrameRGBA = Data()
    @Published var hourglassLiquidFrameRGBA = Data()
    @Published var hourglassSnapshot = HourglassSnapshot()
    @Published var hourglassLiquidSnapshot = HourglassLiquidSnapshot()
    @Published var codexFrameRGBA = Data()
    @Published var agentHubFrameRGBA = Data()
    @Published var tilt: Double = 0 { didSet { sendQEMUMotionIfReady() } }
    @Published var tiltY: Double = 0 { didSet { sendQEMUMotionIfReady() } }
    @Published var tiltZ: Double = 1 { didSet { sendQEMUMotionIfReady() } }
    @Published var batteryPercent: Double = 86
    @Published var batteryCharging = true
    @Published var screenBrightnessPercent: Double = 100
    @Published var fps: Double = 60
    @Published var soundEnabled = true
    @Published var running = true
    @Published var eventText = "READY"
    @Published var selectedProject: VirtualProject = .breakout {
        didSet {
            defaults.set(selectedProject.rawValue, forKey: "simulator.firmware")
            if oldValue.runtimeID != selectedProject.runtimeID {
                resetCodexBridgeCredential()
                lastBridgePoll = 0
            }
            refreshResourceMetrics()
            syncFirmwareDisplayForPose()
        }
    }
    @Published var devicePose: DevicePose = .upright
    @Published var codex = CodexMockState()
    @Published var codexUsesBridge = true
    @Published var bridgeURL = "http://127.0.0.1:8765/state"
    @Published var bridgeToken = ""
    @Published private(set) var codexFrameWidth = 240
    @Published private(set) var codexFrameHeight = 135
    @Published private(set) var agentHubFrameWidth = 135
    @Published private(set) var agentHubFrameHeight = 240
    @Published private(set) var testProjects: [SimulatorProjectReference] = []
    @Published var projectLibraryMessage = ""
    @Published private(set) var isRebuilding = false
    @Published private(set) var rebuildPhase: SimulatorRebuildPhase = .idle
    @Published private(set) var rebuildLog = ""
    @Published private(set) var lastSuccessfulRebuild: Date?
    @Published private(set) var resourceMetrics = SimulatorResourceMetrics()
    @Published private(set) var measuredSimulatorFPS = 0.0
    @Published private(set) var qemuState: StickS3QEMUState = .unavailable
    @Published private(set) var qemuLog = ""
    @Published private(set) var qemuFirmwareName: String?
    @Published private(set) var qemuFrameRGBA = Data()
    @Published private(set) var qemuFrameWidth = 135
    @Published private(set) var qemuFrameHeight = 240
    @Published private(set) var qemuBoardCapabilities: StickS3VirtualBoardCapabilities = []
    @Published private(set) var qemuBoardReport: StickS3VirtualBoardReport?
    @Published private(set) var hostNetworkState: HostNetworkState = .idle
    @Published private(set) var activeShakeGesture: DeviceShakeGesture?
    @Published private(set) var platformIOIsAvailable = false
    @Published private(set) var espIDFIsAvailable = false

    private var qemuLogUTF8Count = 0
    private var context: UnsafeMutableRawPointer?
    private var hourglassContext: UnsafeMutableRawPointer?
    private var hourglassLiquidContext: UnsafeMutableRawPointer?
    private var codexFirmwareContext: UnsafeMutableRawPointer?
    private var agentHubFirmwareContext: UnsafeMutableRawPointer?
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()
    private var startedAt = CACurrentMediaTime()
    private var lastSoundSerial: UInt32 = 0
    private var lastLiquidChimeSerial: UInt32 = 0
    private var lastBreakoutFrameSerial = UInt32.max
    private var lastHourglassFrameSerial = UInt32.max
    private var lastLiquidFrameSerial = UInt32.max
    private var lastCodexFrameSerial = UInt32.max
    private var lastAgentHubFrameSerial = UInt32.max
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var lastBridgePoll = 0.0
    private var lastClockSecond = -1
    private var hasLoadedBridgeCredential = false
    private let defaults = UserDefaults.standard
    private let simulatorProjectRoot: URL?
    private let projectLibrary: SimulatorProjectLibrary
    private let rebuildOutputParser = SimulatorRebuildOutputParser()
    private let firmwareCatalogComposer = SimulatorFirmwareCatalogComposer()
    private let resourceInspector = SimulatorResourceInspector()
    private var rebuildProcess: Process?
    private var firmwareBuildProcess: Process?
    private var firmwareBuildPipe: Pipe?
    private var qemuProcess: Process?
    private var qemuConsolePipe: Pipe?
    private var qemuInputPipe: Pipe?
    private var qemuWorkingFlashURL: URL?
    private var deviceShakeTask: Task<Void, Never>?
    private var qemuFrameConversionTask: Task<Void, Never>?
    private var pendingQEMUFrame: StickS3VirtualBoardFrame?
    private var qemuFrameGate = QEMUFrameGate()
    private var qemuFrameGeneration: UInt64 = 0
    private let qemuOutputDecoder = QEMUOutputDecoder()
    private let hostNetworkProxy = HostNetworkProxy()
    private var hostNetworkTasks: [UInt32: Task<Void, Never>] = [:]
    private var qemuOutputGeneration: UInt64 = 0
    private var hasReportedQEMUAudio = false
    private let deviceAudio = DeviceAudioEngine()
    private var poseAudioMutedUntil = 0.0
    private var audioPlaybackAllowed: Bool {
        soundEnabled && CACurrentMediaTime() >= poseAudioMutedUntil
    }
    private var lastCodexStatus = "OFFLINE"
    private var lastCodexWaitingTasks = 0
    private var fpsMeasurementStartedAt = CACurrentMediaTime()
    private var fpsMeasurementTicks = 0

    private static func packagedFingerprints() -> [SimulatorRuntimeID: String] {
        var result: [SimulatorRuntimeID: String] = [:]
        for runtime in SimulatorRuntimeID.allCases {
            let key = "SimulatorFingerprint_\(runtime.rawValue)"
            if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
               !value.isEmpty {
                result[runtime] = value
            }
        }
        return result
    }

    private static func locateSimulatorSourceRoot() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        var candidates: [URL] = []
        if let explicit = environment["SIMULATOR_SOURCE_ROOT"], !explicit.isEmpty {
            candidates.append(URL(fileURLWithPath: explicit, isDirectory: true))
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Stick S3 Firmware Simulator/source-root.txt")
        if let saved = try? String(contentsOf: support, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !saved.isEmpty {
            candidates.append(URL(fileURLWithPath: saved, isDirectory: true))
        }
        return candidates.first { candidate in
            FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Package.swift").path)
                && FileManager.default.isExecutableFile(
                    atPath: candidate.appendingPathComponent("scripts/rebuild-from-app.sh").path)
        }?.standardizedFileURL
    }

    init() {
        simulatorProjectRoot = Self.locateSimulatorSourceRoot()
        projectLibrary = SimulatorProjectLibrary(
            packagedFingerprints: Self.packagedFingerprints()
        )
        testProjects = projectLibrary.load().map { projectLibrary.refresh($0) }
        lastSuccessfulRebuild = defaults.object(forKey: "simulator.lastSuccessfulRebuild") as? Date
        if let saved = defaults.string(forKey: "simulator.firmware"),
           let project = VirtualProject(rawValue: saved),
           visibleProjects.contains(project) {
            selectedProject = project
        } else if let first = visibleProjects.first {
            selectedProject = first
        }
        context = breakout_create(Self.screenWidth, Self.screenHeight)
        hourglassContext = hourglass_create()
        hourglassLiquidContext = hourglass_liquid_create()
        codexFirmwareContext = codex_firmware_create()
        agentHubFirmwareContext = agent_hub_firmware_create()
        syncFirmwareDisplayForPose()
        let high = UInt32(defaults.integer(forKey: "neonbrick.high"))
        let unlocked = UInt8(max(1, defaults.integer(forKey: "neonbrick.unlock")))
        soundEnabled = defaults.object(forKey: "neonbrick.sound") == nil
            ? true : defaults.bool(forKey: "neonbrick.sound")
        breakout_load_persistent(context, high, unlocked)
        breakout_set_sound_enabled(context, soundEnabled)
        refreshSnapshot()
        refreshHourglassSnapshot(liquid: false)
        refreshHourglassSnapshot(liquid: true)
        syncCodexFirmwareState(nowMs: 0)
        refreshResourceMetrics()
        refreshQEMUAvailability()
        refreshBuildToolStatus()
    }

    isolated deinit {
        deviceShakeTask?.cancel()
        timer?.invalidate()
        if let keyDownMonitor { NSEvent.removeMonitor(keyDownMonitor) }
        if let keyUpMonitor { NSEvent.removeMonitor(keyUpMonitor) }
        breakout_destroy(context)
        hourglass_destroy(hourglassContext)
        hourglass_liquid_destroy(hourglassLiquidContext)
        codex_firmware_destroy(codexFirmwareContext)
        agent_hub_firmware_destroy(agentHubFirmwareContext)
        stopQEMU()
    }

    func rebuildSimulator() {
        guard !isRebuilding else { return }
        guard canReloadSelectedFirmware else {
            rebuildPhase = .failed
            rebuildLog = "尚未选择可重新载入的源码项目。请先导入一个已支持的项目文件夹。\n"
            return
        }
        guard let simulatorProjectRoot else {
            rebuildPhase = .failed
            rebuildLog = "找不到虚拟设备源码目录。请从 Git 下载的源码目录运行 scripts/build-app.sh 后再试。\n"
            return
        }
        let script = simulatorProjectRoot.appendingPathComponent("scripts/rebuild-from-app.sh")
        guard FileManager.default.isExecutableFile(atPath: script.path) else {
            rebuildPhase = .failed
            rebuildLog = "未找到可执行的构建脚本：\n\(script.path)"
            return
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [script.path]
        process.currentDirectoryURL = simulatorProjectRoot
        process.standardOutput = pipe
        process.standardError = pipe
        var environment = ProcessInfo.processInfo.environment
        environment["SIMULATOR_FIRMWARE_RUNTIME"] = selectedProject.runtimeID.rawValue
        environment["SIMULATOR_FIRMWARE_ROOT"] = selectedSourceProject?.firmwarePath
        process.environment = environment

        isRebuilding = true
        rebuildPhase = .preparing
        rebuildLog = "开始读取最新固件源码。\n"
        rebuildProcess = process

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.appendRebuildOutput(output)
            }
        }

        process.terminationHandler = { [weak self] finished in
            pipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.rebuildProcess = nil
                if finished.terminationStatus == 0 {
                    self.lastSuccessfulRebuild = Date()
                    self.defaults.set(self.lastSuccessfulRebuild, forKey: "simulator.lastSuccessfulRebuild")
                    self.launchUpdaterAndRelaunch()
                } else {
                    self.isRebuilding = false
                    self.rebuildPhase = .failed
                    self.appendRebuildOutput("\n构建进程退出码：\(finished.terminationStatus)\n")
                }
            }
        }

        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            rebuildProcess = nil
            isRebuilding = false
            rebuildPhase = .failed
            rebuildLog += "无法启动构建：\(error.localizedDescription)\n"
        }
    }

    private func appendRebuildOutput(_ output: String) {
        rebuildLog += output
        if rebuildLog.count > 80_000 {
            rebuildLog = String(rebuildLog.suffix(80_000))
        }
        rebuildPhase = rebuildOutputParser.phase(for: output, current: rebuildPhase)
    }

    private func launchUpdaterAndRelaunch() {
        guard let simulatorProjectRoot else {
            isRebuilding = false
            rebuildPhase = .failed
            appendRebuildOutput("\n构建成功，但源码目录记录已失效。\n")
            return
        }
        let updaterScript = simulatorProjectRoot
            .appendingPathComponent("scripts/install-built-app-and-relaunch.sh")
        let builtApp = simulatorProjectRoot
            .appendingPathComponent("build/StickS3 固件实验台.app", isDirectory: true)
        let desktopApp = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/StickS3 固件实验台.app", isDirectory: true)

        guard FileManager.default.isExecutableFile(atPath: updaterScript.path),
              FileManager.default.fileExists(atPath: builtApp.path) else {
            isRebuilding = false
            rebuildPhase = .failed
            appendRebuildOutput("\n构建成功，但未找到更新助手或应用产物。\n")
            return
        }

        let updater = Process()
        updater.executableURL = URL(fileURLWithPath: "/bin/zsh")
        updater.arguments = [
            updaterScript.path,
            builtApp.path,
            desktopApp.path,
            String(ProcessInfo.processInfo.processIdentifier),
        ]
        updater.standardOutput = FileHandle.nullDevice
        updater.standardError = FileHandle.nullDevice

        do {
            // The updater waits for this app to exit before replacing it. Stop
            // QEMU synchronously first so it can never survive into the new app.
            stopQEMU()
            try updater.run()
            rebuildPhase = .installing
            rebuildLog += "\n构建成功。模拟器将自动退出、更新桌面应用并重新打开。\n"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                NSApplication.shared.terminate(nil)
            }
        } catch {
            isRebuilding = false
            rebuildPhase = .failed
            appendRebuildOutput("\n无法启动更新助手：\(error.localizedDescription)\n")
        }
    }

    func importTestProject(at url: URL) {
        let project = projectLibrary.inspect(url)
        var existing = testProjects
        if let runtime = project.runtimeID {
            existing.removeAll { $0.runtimeID == runtime && $0.sourcePath != project.sourcePath }
        }
        testProjects = projectLibrary.merging([project], into: existing)
        if project.runtimeID == .codex || project.runtimeID == .agentHub {
            resetCodexBridgeCredential()
        }
        persistProjectLibrary()
        if let runtime = project.runtimeID, let selected = VirtualProject(runtimeID: runtime) {
            selectedProject = selected
        }
        ensureValidFirmwareSelection()
        refreshResourceMetrics()
        projectLibraryMessage = "\(project.displayName)：\(project.compatibility.title)"
    }

    var firmwareCatalog: [SimulatorFirmwareCatalogItem] {
        firmwareCatalogComposer.compose(projects: testProjects)
    }

    var visibleProjects: [VirtualProject] {
        let imported = Set(firmwareCatalog.compactMap { item in
            item.runtimeID
        })
        return VirtualProject.allCases.filter { imported.contains($0.runtimeID) }
    }

    private var selectedSourceProject: SimulatorProjectReference? {
        testProjects.first { $0.runtimeID == selectedProject.runtimeID }
    }

    private func refreshResourceMetrics() {
        guard let project = selectedSourceProject,
              let firmwarePath = project.firmwarePath else {
            resourceMetrics = SimulatorResourceMetrics()
            return
        }
        resourceMetrics = resourceInspector.inspect(
            projectRoot: URL(fileURLWithPath: project.sourcePath, isDirectory: true),
            firmwareRoot: URL(fileURLWithPath: firmwarePath, isDirectory: true)
        )
    }

    var hasImportedFirmware: Bool { !firmwareCatalog.isEmpty }
    var hasSelectableFirmware: Bool { !visibleProjects.isEmpty }
    var needsSimulatorAdapter: Bool { hasImportedFirmware && !hasSelectableFirmware }
    var hasRunnableFirmware: Bool {
        selectedSourceProject?.compatibility == .ready
    }
    var hasActiveQEMUFirmware: Bool { qemuState.isActive && qemuFirmwareName != nil }
    var qemuDisplayReady: Bool {
        qemuBoardCapabilities.contains(.display)
            && qemuFrameRGBA.count == qemuFrameWidth * qemuFrameHeight * 4
    }
    var qemuControlsReady: Bool {
        guard let report = qemuBoardReport,
              report.compatibility != .unsupported else { return false }
        return report.capabilities.contains(.buttons) || report.capabilities.contains(.bmi270)
    }
    var qemuPowerControlsReady: Bool { qemuBoardCapabilities.contains(.power) }
    var qemuAudioControlsReady: Bool { qemuBoardCapabilities.contains(.audio) }
    var qemuDisplaySettingsReady: Bool { qemuBoardCapabilities.contains(.display) }
    var qemuIsAvailable: Bool { StickS3QEMUDiscovery().locate() != nil }

    func canStartQEMU(_ item: SimulatorFirmwareCatalogItem) -> Bool {
        guard qemuIsAvailable,
              let referenceID = item.projectReferenceID,
              let project = testProjects.first(where: { $0.id == referenceID }),
              project.runtimeID == nil,
              project.hardwareProfile?.compatibility != .unsupported else { return false }
        return StickS3FirmwareBuildPlanner().canBuild(project)
    }

    func startQEMU(referenceID: UUID) {
        guard let project = testProjects.first(where: { $0.id == referenceID }) else { return }
        guard let installation = StickS3QEMUDiscovery().locate() else {
            qemuState = .unavailable
            qemuLog = "应用内未找到 ESP32-S3 QEMU 运行时。\n"
            return
        }
        stopQEMU()
        qemuLog = ""
        qemuLogUTF8Count = 0
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Stick S3 Firmware Simulator/QEMU Sessions", isDirectory: true)
            .appendingPathComponent(project.id.uuidString, isDirectory: true)
        buildFirmwareAndLaunch(project: project, installation: installation, support: support)
    }

    private func buildFirmwareAndLaunch(
        project: SimulatorProjectReference,
        installation: StickS3QEMUInstallation,
        support: URL
    ) {
        if StickS3FirmwareToolDiscovery().locate(for: project.projectFormat) == nil {
            qemuState = .failed
            qemuFirmwareName = project.displayName
            switch project.projectFormat {
            case .platformIO, .arduino:
                qemuLog = "尚未检测到 PlatformIO。请在固件管理中打开官方下载页，安装后点击“重新检测”。\nPlatformIO 自己会缓存基础组件；不同项目只会补充各自新增的库。\n"
            case .espIDF:
                qemuLog = "尚未检测到可选的 ESP-IDF 构建环境。请在固件管理中打开 Espressif 官方下载页，安装后点击“重新检测”。\n"
            case .none:
                qemuLog = "该导入内容无法自动构建。\n"
            }
            return
        }
        do {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            let buildCache = support.appendingPathComponent("BuildCache", isDirectory: true)
            try FileManager.default.createDirectory(at: buildCache, withIntermediateDirectories: true)
            let adapterDirectory = Bundle.main.resourceURL?
                .appendingPathComponent("VirtualBoard", isDirectory: true)
            let cacheSignature = try StickS3FirmwareBuildCacheSignature.calculate(
                for: project,
                adapterDirectory: adapterDirectory
            )
            let signatureFile = support.appendingPathComponent("build-cache-signature.txt")
            let cachedSignature = try? String(contentsOf: signatureFile, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let sourceFlash = support.appendingPathComponent("source-flash.bin")
            let workingFlash = support.appendingPathComponent("working-flash.bin")
            if cachedSignature == cacheSignature,
               FileManager.default.fileExists(atPath: sourceFlash.path),
               FileManager.default.fileExists(atPath: workingFlash.path) {
                var cachedArtifacts = project
                cachedArtifacts.sourcePath = buildCache.path
                cachedArtifacts.firmwarePath = buildCache.path
                qemuState = .starting
                qemuFirmwareName = project.displayName
                qemuLog = "源码和模拟适配未变化，正在直接启动：\(project.displayName)\n"
                launchQEMU(
                    project: project,
                    imageProject: cachedArtifacts,
                    installation: installation,
                    support: support,
                    cacheSignature: cacheSignature
                )
                return
            }
            let buildSource = try StickS3FirmwareBuildWorkspace().prepare(
                project: project,
                at: buildCache.appendingPathComponent("Source", isDirectory: true)
            )
            let detectedProfile = StickS3VirtualHardwareDetector().detect(project: project)
            var hardwareProfile = project.hardwareProfile ?? detectedProfile
            // New bridge capabilities can be discovered without discarding a
            // customer's saved/calibrated axis and button mapping.
            hardwareProfile.capabilities.formUnion(detectedProfile.capabilities)
            try StickS3VirtualBoardInjector().inject(
                into: buildSource, hardwareProfile: hardwareProfile)
            let plan = try StickS3FirmwareBuildPlanner().makePlan(for: buildSource, cacheDirectory: buildCache)
            qemuState = .starting
            qemuFirmwareName = project.displayName
            qemuLog = "已创建只读导入项目的私有构建副本。\n正在使用 \(plan.tool.title) 构建 \(project.displayName)…\n"
            runFirmwareBuildStage(
                plan: plan,
                arguments: plan.preflightArguments ?? plan.arguments,
                isPreflight: plan.preflightArguments != nil,
                project: project,
                installation: installation,
                support: support,
                cacheSignature: cacheSignature
            )
        } catch {
            firmwareBuildProcess = nil
            firmwareBuildPipe = nil
            qemuState = .failed
            qemuFirmwareName = project.displayName
            qemuLog += "无法构建固件：\(error.localizedDescription)\n"
        }
    }

    private func runFirmwareBuildStage(
        plan: StickS3FirmwareBuildPlan,
        arguments: [String],
        isPreflight: Bool,
        project: SimulatorProjectReference,
        installation: StickS3QEMUInstallation,
        support: URL,
        cacheSignature: String
    ) {
        let process = Process()
        let output = Pipe()
        process.executableURL = plan.executableURL
        process.arguments = arguments
        process.environment = plan.environment
        process.currentDirectoryURL = plan.workingDirectoryURL
        process.standardOutput = output
        process.standardError = output
        firmwareBuildProcess = process
        firmwareBuildPipe = output
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in self?.appendQEMULog(text) }
        }
        process.terminationHandler = { [weak self] finished in
            output.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor [weak self] in
                guard let self, self.firmwareBuildProcess === finished else { return }
                self.firmwareBuildProcess = nil
                self.firmwareBuildPipe = nil
                guard finished.terminationStatus == 0 else {
                    self.qemuState = .failed
                    self.appendQEMULog("\n固件构建失败，退出码：\(finished.terminationStatus)\n")
                    return
                }
                if isPreflight {
                    self.appendQEMULog("\n依赖准备完成，正在接入 StickS3 屏幕与控制桥接…\n")
                    self.runFirmwareBuildStage(
                        plan: plan,
                        arguments: plan.arguments,
                        isPreflight: false,
                        project: project,
                        installation: installation,
                        support: support,
                        cacheSignature: cacheSignature
                    )
                } else {
                    self.appendQEMULog("\n构建成功，正在合并并校验完整 Flash…\n")
                    self.launchQEMU(project: project, imageProject: plan.artifactProject,
                                    installation: installation, support: support,
                                    cacheSignature: cacheSignature)
                }
            }
        }
        do {
            try process.run()
        } catch {
            firmwareBuildProcess = nil
            firmwareBuildPipe = nil
            qemuState = .failed
            appendQEMULog("无法启动构建工具：\(error.localizedDescription)\n")
        }
    }

    func refreshBuildToolStatus() {
        let discovery = StickS3FirmwareToolDiscovery()
        platformIOIsAvailable = discovery.locate(for: .platformIO) != nil
        espIDFIsAvailable = discovery.locate(for: .espIDF) != nil
    }

    func openPlatformIODownload() {
        NSWorkspace.shared.open(URL(string: "https://docs.platformio.org/en/latest/core/installation/methods/installer-script.html")!)
    }

    func openESPIDFDownload() {
        NSWorkspace.shared.open(URL(string: "https://docs.espressif.com/projects/idf-im-ui/en/latest/")!)
    }

    private func launchQEMU(
        project: SimulatorProjectReference,
        imageProject: SimulatorProjectReference,
        installation: StickS3QEMUInstallation,
        support: URL,
        cacheSignature: String
    ) {
        do {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            let sourceImage = try StickS3QEMUImageResolver().prepare(for: imageProject, cacheDirectory: support)
            let sourceSnapshot = support.appendingPathComponent("source-flash.bin")
            let workingFlash = support.appendingPathComponent("working-flash.bin")
            let sourceChanged = !FileManager.default.fileExists(atPath: sourceSnapshot.path)
                || !FileManager.default.contentsEqual(atPath: sourceImage.path, andPath: sourceSnapshot.path)
            if sourceChanged {
                for destination in [sourceSnapshot, workingFlash] {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.copyItem(at: sourceImage, to: destination)
                }
            } else if !FileManager.default.fileExists(atPath: workingFlash.path) {
                try FileManager.default.copyItem(at: sourceSnapshot, to: workingFlash)
            }
            try (cacheSignature + "\n").write(
                to: support.appendingPathComponent("build-cache-signature.txt"),
                atomically: true,
                encoding: .utf8
            )
            let command = try StickS3QEMUCommandBuilder().makeCommand(
                installation: installation,
                flashImageURL: workingFlash
            )

            let process = Process()
            let console = Pipe()
            let input = Pipe()
            process.executableURL = command.executableURL
            process.arguments = command.arguments
            process.environment = command.environment
            process.standardOutput = console
            process.standardError = console
            process.standardInput = input

            qemuState = .starting
            qemuFirmwareName = project.displayName
            appendQEMULog(sourceChanged
                ? "已生成并校验完整 Flash，正在启动：\(project.displayName)\n"
                : "正在使用已保存的固件状态启动：\(project.displayName)\n")
            qemuProcess = process
            qemuConsolePipe = console
            qemuInputPipe = input
            qemuWorkingFlashURL = workingFlash

            qemuOutputGeneration = qemuOutputDecoder.reset()
            resetQEMUFramePipeline()
            hasReportedQEMUAudio = false
            qemuBoardCapabilities = []
            qemuBoardReport = nil
            qemuFrameRGBA = Data()
            let outputDecoder = qemuOutputDecoder
            let outputGeneration = qemuOutputGeneration
            console.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                outputDecoder.submit(data, generation: outputGeneration) { [weak self] events, generation in
                    self?.handleQEMUEvents(events, generation: generation)
                }
            }
            process.terminationHandler = { [weak self] finished in
                ChildProcessRegistry.shared.unregister(finished)
                console.fileHandleForReading.readabilityHandler = nil
                Task { @MainActor [weak self] in
                    guard let self, self.qemuProcess === finished else { return }
                    self.qemuProcess = nil
                    self.qemuConsolePipe = nil
                    self.qemuInputPipe = nil
                    if self.qemuState != .stopped {
                        self.qemuState = finished.terminationStatus == 0 ? .stopped : .failed
                        self.appendQEMULog("\nQEMU 已退出，状态码：\(finished.terminationStatus)\n")
                    }
                }
            }
            // The in-memory Process reference is not sufficient after a host
            // crash. The persisted session registry enforces one QEMU per project.
            ChildProcessRegistry.shared.terminateSession(project.id.uuidString)
            try process.run()
            ChildProcessRegistry.shared.register(
                process,
                sessionID: project.id.uuidString,
                executableURL: command.executableURL
            )
            appendQEMULog("等待固件进入应用调度器…\n")
        } catch {
            qemuProcess = nil
            qemuConsolePipe = nil
            qemuInputPipe = nil
            qemuState = .failed
            appendQEMULog("启动失败：\(error.localizedDescription)\n")
        }
    }

    func stopQEMU() {
        deviceShakeTask?.cancel()
        deviceShakeTask = nil
        activeShakeGesture = nil
        firmwareBuildPipe?.fileHandleForReading.readabilityHandler = nil
        if let process = firmwareBuildProcess, process.isRunning { process.terminate() }
        firmwareBuildProcess = nil
        firmwareBuildPipe = nil
        qemuConsolePipe?.fileHandleForReading.readabilityHandler = nil
        qemuOutputGeneration = qemuOutputDecoder.reset()
        for task in hostNetworkTasks.values { task.cancel() }
        hostNetworkTasks.removeAll()
        hostNetworkState = .idle
        resetQEMUFramePipeline()
        if let process = qemuProcess, process.isRunning {
            ChildProcessRegistry.shared.terminate(process)
        }
        qemuProcess = nil
        qemuConsolePipe = nil
        qemuInputPipe = nil
        qemuBoardCapabilities = []
        qemuBoardReport = nil
        qemuFrameRGBA = Data()
        if qemuState.isActive { qemuState = .stopped }
    }

    private func refreshQEMUAvailability() {
        if qemuProcess?.isRunning == true { qemuState = .running }
        else { qemuState = qemuIsAvailable ? .stopped : .unavailable }
    }

    private func appendQEMULog(_ output: String) {
        qemuLog += output
        qemuLogUTF8Count += output.utf8.count
        if qemuLogUTF8Count > 80_000 {
            qemuLog = String(decoding: qemuLog.utf8.suffix(60_000), as: UTF8.self)
            qemuLogUTF8Count = qemuLog.utf8.count
        }
        if qemuState == .starting {
            let normalized = output.lowercased()
            if normalized.contains("cpu_start: starting scheduler")
                || normalized.contains("main_task: started on cpu")
                || normalized.contains("calling app_main") {
                qemuState = .running
                eventText = "QEMU FIRMWARE BOOTED"
            }
        }
    }

    private func handleQEMUEvents(_ events: [StickS3VirtualBoardEvent], generation: UInt64) {
        guard generation == qemuOutputGeneration else { return }
        for event in events {
            switch event {
            case .ready(let report):
                qemuBoardReport = report
                qemuBoardCapabilities = report.capabilities
                qemuState = .running
                eventText = "QEMU FIRMWARE BOOTED"
                appendQEMULog("\nStickS3 虚拟硬件已回报：\(report.compatibility.title)。\n")
                syncQEMUDeviceState()
            case .frame(let frame):
                queueQEMUFrame(frame)
            case .audio(let sound):
                if !hasReportedQEMUAudio {
                    hasReportedQEMUAudio = true
                    appendQEMULog("\n虚拟音频桥已接收固件音效。\n")
                }
                if audioPlaybackAllowed { deviceAudio.playFruit(sound: Int(sound)) }
            case .hostNetworkRequest(let request):
                handleHostNetworkRequest(request, generation: generation)
            case .log(let bytes):
                guard let text = String(data: bytes, encoding: .utf8) else { continue }
                appendQEMULog(text)
            }
        }
    }

    private func handleHostNetworkRequest(
        _ request: StickS3HostNetworkRequest, generation: UInt64
    ) {
        hostNetworkTasks[request.requestID]?.cancel()
        let host = URL(string: request.url)?.host ?? "invalid"
        hostNetworkState = .requesting(host: host)
        let proxy = hostNetworkProxy
        hostNetworkTasks[request.requestID] = Task { [weak self] in
            let result = await proxy.perform(request)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, generation == self.qemuOutputGeneration else { return }
                self.hostNetworkTasks[request.requestID] = nil
                self.hostNetworkState = result.errorCode == 0
                    ? .connected(host: result.host, updatedAt: Date())
                    : .failed(host: result.host, reason: self.hostNetworkFailure(result.errorCode))
                let packet = StickS3VirtualBoardPacketEncoder().hostNetworkResponse(
                    requestID: result.requestID, statusCode: result.statusCode,
                    errorCode: result.errorCode, body: result.body)
                self.sendQEMUPacket(packet)
                if result.errorCode == 0 {
                    self.appendQEMULog("\n主机数据通道已连接：\(result.host)。\n")
                } else {
                    self.appendQEMULog("\n主机数据请求失败：\(result.host)（\(self.hostNetworkFailure(result.errorCode))）。\n")
                }
            }
        }
    }

    private func hostNetworkFailure(_ code: Int) -> String {
        switch URLError.Code(rawValue: code) {
        case .badURL: "地址无效"
        case .cannotFindHost: "找不到数据服务"
        case .cannotConnectToHost: "无法连接数据服务"
        case .timedOut: "连接超时"
        case .userAuthenticationRequired: "需要身份验证"
        case .dataLengthExceedsMaximum: "响应超过 65 KB 限制"
        case .unsupportedURL: "仅允许连接本机数据服务"
        default: "网络错误 \(code)"
        }
    }

    private func sendQEMUPacket(_ packet: Data) {
        guard qemuState == .running, !qemuBoardCapabilities.isEmpty else { return }
        do { try qemuInputPipe?.fileHandleForWriting.write(contentsOf: packet) }
        catch { appendQEMULog("\n控制输入发送失败：\(error.localizedDescription)\n") }
    }

    private func sendQEMUMotionIfReady() {
        guard qemuBoardCapabilities.contains(.bmi270) else { return }
        let sensor = StickS3VirtualBoardMotionMap().sensorVector(
            report: qemuBoardReport,
            logicalX: Float(tilt), logicalY: Float(tiltY), logicalZ: Float(tiltZ))
        sendQEMUPacket(StickS3VirtualBoardPacketEncoder().motion(
            x: sensor.x, y: sensor.y, z: sensor.z))
    }

    private func queueQEMUFrame(_ frame: StickS3VirtualBoardFrame) {
        // Sequence numbers advance on every packet. Pixel equality is the real
        // duplicate test and avoids both conversion work and SwiftUI updates.
        guard qemuFrameGate.accept(frame) else { return }
        pendingQEMUFrame = frame
        startNextQEMUFrameConversionIfNeeded()
    }

    private func startNextQEMUFrameConversionIfNeeded() {
        guard qemuFrameConversionTask == nil, let frame = pendingQEMUFrame else { return }
        pendingQEMUFrame = nil
        let generation = qemuFrameGeneration
        qemuFrameConversionTask = Task.detached(priority: .userInitiated) { [weak self] in
            let rgba = Self.rgbaData(fromRGB565LE: frame.rgb565)
            guard !Task.isCancelled else { return }
            await self?.finishQEMUFrameConversion(frame: frame, rgba: rgba, generation: generation)
        }
    }

    private func finishQEMUFrameConversion(
        frame: StickS3VirtualBoardFrame,
        rgba: Data,
        generation: UInt64
    ) {
        qemuFrameConversionTask = nil
        guard generation == qemuFrameGeneration else { return }
        // Always publish the completed frame before converting the newest pending
        // frame. Dropping it whenever another frame is waiting can starve SwiftUI
        // indefinitely during continuous animation: every conversion finishes with
        // a newer frame pending, so the display never receives an image at all.
        qemuFrameWidth = frame.width
        qemuFrameHeight = frame.height
        qemuFrameRGBA = rgba
        // The pending slot is still latest-only, so sustained output remains bounded
        // to one conversion plus one queued frame instead of building a backlog.
        startNextQEMUFrameConversionIfNeeded()
    }

    private func resetQEMUFramePipeline() {
        qemuFrameGeneration &+= 1
        qemuFrameConversionTask?.cancel()
        qemuFrameConversionTask = nil
        pendingQEMUFrame = nil
        qemuFrameGate.reset()
    }

    nonisolated private static func rgbaData(fromRGB565LE pixels: Data) -> Data {
        guard pixels.count >= 2 else { return Data() }
        var rgba = Data(count: (pixels.count / 2) * 4)
        pixels.withUnsafeBytes { source in
            rgba.withUnsafeMutableBytes { destination in
                let sourceBytes = source.bindMemory(to: UInt8.self)
                let destinationBytes = destination.bindMemory(to: UInt8.self)
                var destinationOffset = 0
                for sourceOffset in stride(from: 0, to: pixels.count - 1, by: 2) {
                    let value = UInt16(sourceBytes[sourceOffset])
                        | (UInt16(sourceBytes[sourceOffset + 1]) << 8)
                    destinationBytes[destinationOffset] = UInt8((UInt32(value >> 11) * 255 + 15) / 31)
                    destinationBytes[destinationOffset + 1] = UInt8((UInt32((value >> 5) & 0x3F) * 255 + 31) / 63)
                    destinationBytes[destinationOffset + 2] = UInt8((UInt32(value & 0x1F) * 255 + 15) / 31)
                    destinationBytes[destinationOffset + 3] = 255
                    destinationOffset += 4
                }
            }
        }
        return rgba
    }
    var canReloadSelectedFirmware: Bool {
        guard simulatorProjectRoot != nil,
              let project = selectedSourceProject,
              project.compatibility != .invalid,
              project.compatibility != .missing else { return false }
        return project.runtimeID != nil && project.firmwarePath != nil
    }

    func removeTestProject(id: UUID) {
        guard let project = testProjects.first(where: { $0.id == id }) else { return }
        try? projectLibrary.clearCache(for: project)
        testProjects.removeAll { $0.id == id }
        if project.runtimeID == .codex { resetCodexBridgeCredential() }
        persistProjectLibrary()
        ensureValidFirmwareSelection()
        refreshResourceMetrics()
        projectLibraryMessage = "已从测试列表移除 \(project.displayName)；原项目未更改"
    }

    func saveHardwareCalibration(projectID: UUID, profile: StickS3VirtualHardwareProfile) {
        guard let index = testProjects.firstIndex(where: { $0.id == projectID }) else { return }
        var verified = profile
        verified.compatibility = .verified
        verified.detectionNote = "已由用户完成左右、上下和两颗按键校准。"
        do {
            try projectLibrary.saveHardwareProfile(verified)
            testProjects[index].hardwareProfile = verified
            persistProjectLibrary()
            projectLibraryMessage = "\(testProjects[index].displayName)：硬件校准已按源码指纹保存"
        } catch {
            projectLibraryMessage = "硬件校准保存失败：\(error.localizedDescription)"
        }
    }

    private func persistProjectLibrary() {
        do {
            try projectLibrary.save(testProjects)
        } catch {
            projectLibraryMessage = "测试项目列表保存失败：\(error.localizedDescription)"
        }
    }

    private func ensureValidFirmwareSelection() {
        if visibleProjects.contains(selectedProject) { return }
        if let first = visibleProjects.first {
            selectedProject = first
            eventText = "FIRMWARE \(first.rawValue.uppercased())"
        } else {
            eventText = "NO FIRMWARE"
            deviceAudio.stop()
        }
    }

    func stop() {
        // Window/app shutdown must also own the external emulator lifecycle.
        // Relying on model deinit leaves QEMU orphaned when macOS tears down the
        // process without releasing SwiftUI state objects first.
        stopQEMU()
        deviceShakeTask?.cancel()
        deviceShakeTask = nil
        activeShakeGesture = nil
        timer?.invalidate()
        timer = nil
        if let keyDownMonitor { NSEvent.removeMonitor(keyDownMonitor) }
        if let keyUpMonitor { NSEvent.removeMonitor(keyUpMonitor) }
        keyDownMonitor = nil
        keyUpMonitor = nil
    }

    func start() {
        installKeyboard()
        if timer == nil { restartTimer() }
    }

    func setFPS(_ value: Double) {
        fps = value
        restartTimer()
        syncQEMUDeviceState()
    }

    func setSimulationRunning(_ value: Bool) {
        guard running != value else { return }
        running = value
        if !value {
            deviceAudio.stop()
            measuredSimulatorFPS = 0
        }
        restartTimer()
        eventText = value ? "SIMULATION RESUMED" : "SIMULATION PAUSED"
    }

    func restartSelectedFirmware() {
        deviceAudio.stop()
        let restartTime = CACurrentMediaTime()
        startedAt = restartTime
        lastTick = restartTime

        switch selectedProject {
        case .breakout:
            breakout_destroy(context)
            context = breakout_create(Self.screenWidth, Self.screenHeight)
            lastBreakoutFrameSerial = .max
            let high = UInt32(defaults.integer(forKey: "neonbrick.high"))
            let unlocked = UInt8(max(1, defaults.integer(forKey: "neonbrick.unlock")))
            breakout_load_persistent(context, high, unlocked)
            breakout_set_sound_enabled(context, soundEnabled)
            refreshSnapshot()
            lastSoundSerial = breakout_sound_serial(context)
        case .hourglass:
            hourglass_destroy(hourglassContext)
            hourglassContext = hourglass_create()
            lastHourglassFrameSerial = .max
            refreshHourglassSnapshot(liquid: false)
        case .hourglassLiquid:
            hourglass_liquid_destroy(hourglassLiquidContext)
            hourglassLiquidContext = hourglass_liquid_create()
            lastLiquidFrameSerial = .max
            refreshHourglassSnapshot(liquid: true)
            lastLiquidChimeSerial = hourglassLiquidSnapshot.chime_serial
        case .codex:
            codex_firmware_destroy(codexFirmwareContext)
            codexFirmwareContext = codex_firmware_create()
            lastCodexFrameSerial = .max
            syncFirmwareDisplayForPose()
            syncCodexFirmwareState(nowMs: 0)
            lastCodexStatus = codex.status
            lastCodexWaitingTasks = codex.waitingTasks
        case .agentHub:
            agent_hub_firmware_destroy(agentHubFirmwareContext)
            agentHubFirmwareContext = agent_hub_firmware_create()
            lastAgentHubFrameSerial = .max
            syncFirmwareDisplayForPose()
            syncAgentHubFirmwareState(nowMs: 0)
        }

        eventText = "FIRMWARE RESTARTED"
    }

    func setScreenBrightness(_ value: Double) {
        screenBrightnessPercent = min(100, max(0, value)).rounded()
        eventText = "BRIGHTNESS \(Int(screenBrightnessPercent))%"
    }

    func setDevicePose(_ pose: DevicePose) {
        // 控制台的左/右 90°是姿态测试，不应伴随固件选择音或提示音。
        // 保留 IMU 事件，但停止当前音频并屏蔽紧接着产生的一次音频。
        if pose.isQuarterTurn {
            deviceAudio.stop()
            poseAudioMutedUntil = CACurrentMediaTime() + 0.35
        }
        devicePose = pose
        switch pose {
        case .upright:
            tilt = 0; tiltY = 0; tiltZ = 1
        case .left90:
            tilt = -1; tiltY = 0; tiltZ = 0
        case .right90:
            tilt = 1; tiltY = 0; tiltZ = 0
        case .upsideDown:
            tilt = 0; tiltY = 0; tiltZ = -1
        }
        syncFirmwareDisplayForPose()
        eventText = "POSE \(pose.rawValue)"
    }

    var canPerformDeviceShake: Bool {
        if hasActiveQEMUFirmware {
            return qemuControlsReady && qemuBoardCapabilities.contains(.bmi270)
        }
        // The built-in simulator cores always accept pose input. Their
        // surrounding controls already handle the no-firmware empty state.
        return true
    }

    func performDeviceShake(_ gesture: DeviceShakeGesture) {
        guard canPerformDeviceShake, activeShakeGesture == nil else { return }
        let origin = (x: tilt, y: tiltY, z: tiltZ)
        activeShakeGesture = gesture
        eventText = "\(gesture.rawValue) SHAKE"
        deviceShakeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let offsets: [Double] = [0.78, -0.78, 0.52, -0.36, 0]
            for offset in offsets {
                guard !Task.isCancelled else { break }
                switch gesture {
                case .horizontal:
                    self.tilt = origin.x + offset
                    self.tiltY = origin.y
                    self.tiltZ = origin.z
                case .vertical:
                    self.tilt = origin.x
                    self.tiltY = origin.y + offset
                    self.tiltZ = origin.z
                }
                try? await Task.sleep(for: .milliseconds(120))
            }
            self.tilt = origin.x
            self.tiltY = origin.y
            self.tiltZ = origin.z
            if !Task.isCancelled {
                // Fruit Machine needs its cooldown plus four neutral samples
                // before the next physical gesture is armed.
                try? await Task.sleep(for: .milliseconds(420))
            }
            self.activeShakeGesture = nil
            self.deviceShakeTask = nil
            if !Task.isCancelled {
                self.eventText = "\(gesture.rawValue) SHAKE COMPLETE"
            }
        }
    }

    func setSound(_ value: Bool) {
        soundEnabled = value
        breakout_set_sound_enabled(context, value)
        defaults.set(value, forKey: "neonbrick.sound")
        if !value { deviceAudio.stop() }
        syncQEMUDeviceState()
        eventText = value ? "SOUND ON" : "SOUND OFF"
    }

    func setBatteryPercent(_ value: Double) {
        batteryPercent = min(100, max(0, value)).rounded()
        syncVirtualPowerState()
    }

    func setBatteryCharging(_ value: Bool) {
        batteryCharging = value
        syncVirtualPowerState()
    }

    private func syncVirtualPowerState() {
        syncQEMUDeviceState()
        if selectedProject == .codex || selectedProject == .agentHub {
            let elapsed = UInt32(min(Double(UInt32.max),
                                     (CACurrentMediaTime() - startedAt) * 1000))
            if selectedProject == .codex {
                syncCodexFirmwareState(nowMs: elapsed)
            } else {
                syncAgentHubFirmwareState(nowMs: elapsed)
            }
        }
    }

    private func syncQEMUDeviceState() {
        guard qemuState == .running else { return }
        sendQEMUPacket(StickS3VirtualBoardPacketEncoder().deviceState(
            batteryPercent: Int(batteryPercent.rounded()),
            charging: batteryCharging,
            soundEnabled: soundEnabled,
            framesPerSecond: Int(fps.rounded())
        ))
    }

    func primaryShort() {
        if selectedProject == .agentHub {
            sendAgentHubButton(side: false, clicks: 1)
            return
        }
        if selectedProject == .codex {
            sendCodexEvent("front_short")
            return
        }
        if selectedProject == .hourglass || selectedProject == .hourglassLiquid {
            sendHourglassButton(button: 0, clicks: 1)
            return
        }
        breakout_primary_short(context)
        eventText = "FRONT SHORT"
        refreshSnapshot()
    }

    func primaryLong() {
        if selectedProject == .agentHub {
            eventText = "FRONT LONG UNBOUND"
            return
        }
        if selectedProject == .codex {
            toggleCodexRecording()
            return
        }
        if selectedProject == .hourglass || selectedProject == .hourglassLiquid {
            eventText = "FRONT LONG UNBOUND"
            return
        }
        breakout_primary_long(context)
        eventText = "FRONT LONG"
        refreshSnapshot()
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = nil
        lastTick = CACurrentMediaTime()
        guard running else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / fps, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    private func tick() {
        let current = CACurrentMediaTime()
        fpsMeasurementTicks += 1
        let measurementDuration = current - fpsMeasurementStartedAt
        if measurementDuration >= 1.0 {
            measuredSimulatorFPS = Double(fpsMeasurementTicks) / measurementDuration
            fpsMeasurementTicks = 0
            fpsMeasurementStartedAt = current
        }
        guard hasRunnableFirmware else { return }
        let delta = Float(min(0.05, current - lastTick))
        lastTick = current
        let elapsed = UInt32(min(Double(UInt32.max), (current - startedAt) * 1000))
        refreshLiveBridgeIfNeeded(now: current)
        if selectedProject == .agentHub {
            updateCodexClock(current)
            syncAgentHubFirmwareState(nowMs: elapsed)
            return
        }
        if selectedProject == .codex {
            updateCodexClock(current)
            syncCodexFirmwareState(nowMs: elapsed)
            handleCodexAudioEvents()
            return
        }
        if selectedProject == .hourglass {
            hourglass_update(hourglassContext, elapsed, Float(tilt), Float(tiltZ))
            refreshHourglassSnapshot(liquid: false)
            return
        }
        if selectedProject == .hourglassLiquid {
            hourglass_liquid_update(hourglassLiquidContext, elapsed, Float(tilt), Float(tiltZ))
            refreshHourglassSnapshot(liquid: true)
            if hourglassLiquidSnapshot.chime_serial != lastLiquidChimeSerial {
                lastLiquidChimeSerial = hourglassLiquidSnapshot.chime_serial
                if audioPlaybackAllowed {
                    deviceAudio.playHourglassCompletion()
                }
                eventText = "HOURGLASS COMPLETION CHIME"
            }
            return
        }
        let velocity = Float(tilt * 115.0)
        breakout_update(context, delta, velocity, elapsed)
        refreshSnapshot()

        let soundSerial = breakout_sound_serial(context)
        if soundSerial != lastSoundSerial {
            lastSoundSerial = soundSerial
            if audioPlaybackAllowed {
                deviceAudio.playBreakout(sound: breakout_last_sound(context))
            }
            eventText = soundName(breakout_last_sound(context))
        }
    }

    private func handleCodexAudioEvents() {
        if codex.status != lastCodexStatus {
            if audioPlaybackAllowed {
                deviceAudio.playCodex(status: codex.status)
            }
            lastCodexStatus = codex.status
            eventText = "\(codex.status) SOUND"
        }
        if codex.waitingTasks > lastCodexWaitingTasks {
            if audioPlaybackAllowed {
                deviceAudio.playCodex(status: "WAIT")
            }
            eventText = "WAIT SOUND"
        }
        lastCodexWaitingTasks = codex.waitingTasks
    }

    private func refreshLiveBridgeIfNeeded(now: Double) {
        guard selectedProject.runtimeID.liveDataPolicy == .importedProjectEnvironment,
              codexUsesBridge,
              now - lastBridgePoll >= 2.0 else { return }
        ensureCodexBridgeCredentialLoaded()
        lastBridgePoll = now
        refreshCodexBridge()
    }

    func refreshCodexBridge() {
        guard codexUsesBridge else {
            if selectedProject == .codex { eventText = "MOCK DATA ACTIVE" }
            return
        }
        Task {
            do {
                let json = try await codexClient.getState()
                applyBridgeJSON(json)
                eventText = "BRIDGE CONNECTED"
            } catch {
                eventText = "BRIDGE OFFLINE"
                codex.status = "OFFLINE"
            }
        }
    }

    func refreshCodexQuota() {
        guard codexUsesBridge else { eventText = "BRIDGE NOT ENABLED"; return }
        Task {
            do {
                let response = try await codexClient.refreshQuota()
                if let state = response["state"] as? [String: Any] { applyBridgeJSON(state) }
                eventText = "QUOTA REFRESHED"
            } catch { bridgeFailed("QUOTA REFRESH FAILED") }
        }
    }

    func sendCodexEvent(_ event: String) {
        guard codexUsesBridge else { eventText = event.uppercased(); return }
        Task {
            do {
                let response = try await codexClient.postEvent(event)
                applyBridgeJSON(response)
                eventText = event.uppercased()
            } catch { bridgeFailed("EVENT FAILED") }
        }
    }

    func blueButton(clicks: Int) {
        if hasActiveQEMUFirmware, qemuBoardCapabilities.contains(.buttons) {
            guard supports(button: .front, clicks: clicks) else {
                eventText = "FRONT \(gestureName(clicks)) UNBOUND"
                return
            }
            sendQEMUPacket(StickS3VirtualBoardPacketEncoder().button(.front, clicks: clicks))
            eventText = "FRONT \(gestureName(clicks))"
            return
        }
        guard supports(button: .front, clicks: clicks) else {
            eventText = "FRONT \(gestureName(clicks)) UNBOUND"
            return
        }
        if selectedProject == .breakout {
            if clicks == 1 { primaryShort() } else { primaryLong() }
            return
        }
        if selectedProject == .hourglass || selectedProject == .hourglassLiquid {
            sendHourglassButton(button: 0, clicks: clicks)
            return
        }
        if selectedProject == .agentHub {
            sendAgentHubButton(side: false, clicks: clicks)
            return
        }
        switch clicks {
        case 1: sendCodexEvent("front_short")
        case 2: refreshCodexQuota()
        case 3: sendCodexEvent("front_triple")
        case 4: sendCodexEvent("front_quadruple")
        default: toggleCodexRecording()
        }
    }

    func grayButton(clicks: Int) {
        if hasActiveQEMUFirmware, qemuBoardCapabilities.contains(.buttons) {
            guard supports(button: .side, clicks: clicks) else {
                eventText = "SIDE \(gestureName(clicks)) UNBOUND"
                return
            }
            sendQEMUPacket(StickS3VirtualBoardPacketEncoder().button(.side, clicks: clicks))
            eventText = "SIDE \(gestureName(clicks))"
            return
        }
        guard supports(button: .side, clicks: clicks) else {
            eventText = "SIDE \(gestureName(clicks)) UNBOUND"
            return
        }
        if selectedProject == .breakout {
            setSound(!soundEnabled)
            eventText = "SIDE SINGLE · SOUND \(soundEnabled ? "ON" : "OFF")"
            return
        }
        if selectedProject == .hourglass || selectedProject == .hourglassLiquid {
            sendHourglassButton(button: 1, clicks: clicks)
            return
        }
        if selectedProject == .agentHub {
            sendAgentHubButton(side: true, clicks: clicks)
            return
        }
        switch clicks {
        case 1: sendCodexEvent("side_short")
        case 2: sendCodexEvent("side_double")
        case 3: sendCodexEvent("side_triple")
        case 4: sendCodexEvent("side_quadruple")
        default: sendCodexEvent("side_long")
        }
    }

    func supports(button: PhysicalButton, clicks: Int) -> Bool {
        if hasActiveQEMUFirmware, qemuBoardCapabilities.contains(.buttons) {
            return qemuControlsReady && (1...5).contains(clicks)
        }
        guard hasRunnableFirmware else { return false }
        switch selectedProject {
        case .breakout:
            return button == .front ? (clicks == 1 || clicks == 5) : clicks == 1
        case .hourglass, .hourglassLiquid:
            return button == .front ? (clicks == 1 || clicks == 2)
                                    : (clicks == 1 || clicks == 2 || clicks == 3 || clicks == 5)
        case .codex:
            return button == .front ? (clicks == 1 || clicks == 2 || clicks == 5)
                                    : (clicks == 1 || clicks == 2 || clicks == 3 || clicks == 5)
        case .agentHub:
            return button == .front ? clicks == 1 : (clicks == 1 || clicks == 3)
        }
    }

    func gestureName(_ clicks: Int) -> String {
        switch clicks {
        case 1: return "SINGLE"
        case 2: return "DOUBLE"
        case 3: return "TRIPLE"
        case 4: return "QUADRUPLE"
        default: return "LONG"
        }
    }

    func toggleCodexRecording() {
        guard codexUsesBridge else {
            codex.recording.toggle()
            codex_firmware_set_recording(codexFirmwareContext, codex.recording)
            refreshCodexFramebuffer()
            eventText = codex.recording ? "LISTENING (PREVIEW)" : "RELEASED (PREVIEW)"
            return
        }
        let starting = !codex.recording
        codex.recording = starting
        codex_firmware_set_recording(codexFirmwareContext, starting)
        refreshCodexFramebuffer()
        eventText = starting ? "LISTENING" : "SENDING"
        Task {
            do {
                let response = try await (starting ? codexClient.startRecording()
                                                     : codexClient.stopRecording())
                if let state = response["state"] as? [String: Any] { applyBridgeJSON(state) }
                eventText = starting ? "RECORDING STARTED" : "TRANSCRIPT SENT"
            } catch {
                codex.recording = false
                codex_firmware_set_recording(codexFirmwareContext, false)
                refreshCodexFramebuffer()
                bridgeFailed(starting ? "RECORDING START FAILED" : "RECORDING STOP FAILED")
            }
        }
    }

    private var codexClient: CodexBridgeClient {
        CodexBridgeClient(stateURL: bridgeURL, token: bridgeToken)
    }

    private func ensureCodexBridgeCredentialLoaded() {
        guard !hasLoadedBridgeCredential else { return }
        hasLoadedBridgeCredential = true
        guard selectedProject.runtimeID.liveDataPolicy == .importedProjectEnvironment else {
            bridgeToken = ""
            return
        }
        let projectRoot = selectedSourceProject?.sourcePath
        bridgeToken = BridgeCredentialStore.loadToken(projectRoot: projectRoot)
    }

    private func resetCodexBridgeCredential() {
        bridgeToken = ""
        hasLoadedBridgeCredential = false
    }

    private func syncFirmwareDisplayForPose() {
        guard selectedProject.runtimeID.displayLayout == .poseAdaptive else { return }
        // 自适应适配器统一从这个入口接收姿态；新固件不得在视图中猜测方向。
        let landscape = devicePose.isQuarterTurn
        if selectedProject == .codex, codexFirmwareContext != nil {
            codex_firmware_set_orientation(
                codexFirmwareContext,
                landscape,
                landscape && devicePose == .left90
            )
            refreshCodexFramebuffer()
        } else if selectedProject == .agentHub, agentHubFirmwareContext != nil {
            agent_hub_firmware_set_orientation(
                agentHubFirmwareContext,
                landscape,
                landscape && devicePose == .left90
            )
            refreshAgentHubFramebuffer()
        }
    }

    private func bridgeFailed(_ message: String) {
        eventText = message
        codex.status = "OFFLINE"
    }

    private func applyBridgeJSON(_ root: [String: Any]) {
        let state = (root["state"] as? [String: Any]) ?? root
        let provider = (state["provider"] as? [String: Any])
            ?? (state["codex"] as? [String: Any]) ?? [:]
        codex.status = (provider["status"] as? String) ?? codex.status
        // Bridge 的 null 表示真实数据当前不可用，不能沿用预览默认值。
        codex.quota5hValid = assignNumber(provider["quota_5h_remaining"], to: &codex.quota5h)
        codex.quota7dValid = assignNumber(provider["quota_7d_remaining"], to: &codex.quota7d)
        codex.reset5hValid = assignInt(provider["quota_5h_reset_minutes"], to: &codex.reset5hMinutes)
        codex.reset7dValid = assignInt(provider["quota_7d_reset_minutes"], to: &codex.reset7dMinutes)
        codex.monthCostValid = assignNumber(provider["month_cost_usd"], to: &codex.monthCost)
        codex.monthTokensValid = assignInt(provider["month_tokens"], to: &codex.monthTokens)
        codex.todayUsedPercentValid = assignInt(
            provider["today_used_percent"], to: &codex.todayUsedPercent)
        codex.todayTokensValid = assignInt(provider["today_tokens"], to: &codex.todayTokens)
        _ = assignInt(provider["running_tasks"], to: &codex.runningTasks)
        _ = assignInt(provider["waiting_tasks"], to: &codex.waitingTasks)
        _ = assignInt(provider["finished_tasks"], to: &codex.finishedTasks)
        codex.quotaStale = (provider["quota_stale"] as? Bool) ?? false
        codex.quotaUpdatedAt = (provider["quota_updated_at"] as? String) ?? ""
        codex.project = (provider["project"] as? String) ?? ""
        if let time = state["time"] as? String { codex.time = String(time.prefix(8)) }
        if let date = state["date"] as? String { codex.date = date }
        if let weekday = state["weekday"] as? String { codex.weekday = weekday }
    }

    private func assignNumber(_ value: Any?, to target: inout Double) -> Bool {
        guard let value = value as? NSNumber else { target = 0; return false }
        target = value.doubleValue
        return true
    }

    private func assignInt(_ value: Any?, to target: inout Int) -> Bool {
        guard let value = value as? NSNumber else { target = 0; return false }
        target = value.intValue
        return true
    }

    private func number(_ value: Any?, _ fallback: Double) -> Double {
        if let value = value as? NSNumber { return value.doubleValue }
        return fallback
    }

    private func updateCodexClock(_ now: Double) {
        guard !codexUsesBridge || now - lastBridgePoll > 3 else { return }
        let second = Int(now)
        guard second != lastClockSecond else { return }
        lastClockSecond = second
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        codex.time = formatter.string(from: Date())
        formatter.dateFormat = "MMM d"
        codex.date = formatter.string(from: Date())
        formatter.dateFormat = "EEE."
        codex.weekday = formatter.string(from: Date())
    }

    private func refreshSnapshot() {
        let frameSerial = breakout_frame_serial(context)
        guard frameSerial != lastBreakoutFrameSerial else { return }
        lastBreakoutFrameSerial = frameSerial
        snapshot = breakout_snapshot(context)
        ball = breakout_ball(context)
        paddle = breakout_paddle(context)
        var next: [BrickViewData] = []
        let count = breakout_brick_count(context)
        if count > 0 {
            next.reserveCapacity(Int(count))
            for index in 0..<count {
                var item = BreakoutBrickSnapshot()
                if breakout_brick(context, index, &item) {
                    next.append(BrickViewData(
                        id: Int(index), x: CGFloat(item.x), y: CGFloat(item.y),
                        width: CGFloat(item.width), height: CGFloat(item.height),
                        color: item.color, type: item.type,
                        hits: item.hits_remaining, active: item.active))
                }
            }
        }
        bricks = next
        refreshBreakoutFramebuffer()
        defaults.set(Int(snapshot.high_score), forKey: "neonbrick.high")
        defaults.set(Int(snapshot.unlocked_level), forKey: "neonbrick.unlock")
    }

    private func refreshBreakoutFramebuffer() {
        guard let pixels = breakout_framebuffer(context) else { return }
        let count = Int(Self.screenWidth * Self.screenHeight)
        var rgba = [UInt8](repeating: 0, count: count * 4)
        for index in 0..<count {
            let value = pixels[index]
            let red = UInt8((UInt32(value >> 11) * 255 + 15) / 31)
            let green = UInt8((UInt32((value >> 5) & 0x3f) * 255 + 31) / 63)
            let blue = UInt8((UInt32(value & 0x1f) * 255 + 15) / 31)
            let offset = index * 4
            rgba[offset] = red
            rgba[offset + 1] = green
            rgba[offset + 2] = blue
            rgba[offset + 3] = 255
        }
        breakoutFrameRGBA = Data(rgba)
    }

    private func refreshHourglassSnapshot(liquid: Bool) {
        if liquid {
            let frameSerial = hourglass_liquid_frame_serial(hourglassLiquidContext)
            guard frameSerial != lastLiquidFrameSerial else { return }
            lastLiquidFrameSerial = frameSerial
            hourglassLiquidSnapshot = hourglass_liquid_snapshot(hourglassLiquidContext)
            hourglassLiquidFrameRGBA = rgbaData(from: hourglass_liquid_framebuffer(hourglassLiquidContext))
        } else {
            let frameSerial = hourglass_frame_serial(hourglassContext)
            guard frameSerial != lastHourglassFrameSerial else { return }
            lastHourglassFrameSerial = frameSerial
            hourglassSnapshot = hourglass_snapshot(hourglassContext)
            hourglassFrameRGBA = rgbaData(from: hourglass_framebuffer(hourglassContext))
        }
    }

    private func syncCodexFirmwareState(nowMs: UInt32) {
        let battery = Int32(max(0, min(100, Int(batteryPercent))))
        codex.status.withCString { status in
            codex.time.withCString { time in
                codex.date.withCString { date in
                    codex.weekday.withCString { weekday in
                        codex_firmware_set_state(
                            codexFirmwareContext, status, time, date, weekday,
                            battery, batteryCharging, false,
                            Int32(codex.quota5h), Int32(codex.reset5hMinutes),
                            Int32(codex.quota7d), Int32(codex.reset7dMinutes),
                            codex.monthCost, Int64(codex.monthTokens),
                            Int32(codex.todayUsedPercent), Int64(codex.todayTokens),
                            Int32(codex.runningTasks), Int32(codex.waitingTasks),
                            Int32(codex.finishedTasks),
                            codex.quota5hValid, codex.reset5hValid,
                            codex.quota7dValid, codex.reset7dValid,
                            codex.monthCostValid, codex.monthTokensValid,
                            codex.todayUsedPercentValid, codex.todayTokensValid)
                    }
                }
            }
        }
        codex_firmware_update(codexFirmwareContext, nowMs)
        refreshCodexFramebuffer()
    }

    private func refreshCodexFramebuffer() {
        let frameSerial = codex_firmware_frame_serial(codexFirmwareContext)
        guard frameSerial != lastCodexFrameSerial else { return }
        lastCodexFrameSerial = frameSerial
        codexFrameWidth = Int(codex_firmware_frame_width(codexFirmwareContext))
        codexFrameHeight = Int(codex_firmware_frame_height(codexFirmwareContext))
        codexFrameRGBA = rgbaData(from: codex_firmware_framebuffer(codexFirmwareContext))
    }

    private func syncAgentHubFirmwareState(nowMs: UInt32) {
        let battery = Int32(max(0, min(100, Int(batteryPercent))))
        let usesCodexData = Self.agentHubUsesCodexLiveData(
            providerIndex: agent_hub_firmware_active_provider(agentHubFirmwareContext))
        let statusText = usesCodexData ? codex.status : "OFFLINE"
        statusText.withCString { status in
            codex.time.withCString { time in
                codex.date.withCString { date in
                    codex.weekday.withCString { weekday in
                        agent_hub_firmware_set_state(
                            agentHubFirmwareContext, status, time, date, weekday,
                            battery, batteryCharging, false,
                            usesCodexData ? Int32(codex.quota5h) : 0,
                            usesCodexData ? Int32(codex.reset5hMinutes) : 0,
                            usesCodexData ? Int32(codex.quota7d) : 0,
                            usesCodexData ? Int32(codex.reset7dMinutes) : 0,
                            usesCodexData ? codex.monthCost : 0,
                            usesCodexData ? Int64(codex.monthTokens) : 0,
                            usesCodexData ? Int32(codex.todayUsedPercent) : 0,
                            usesCodexData ? Int64(codex.todayTokens) : 0,
                            usesCodexData ? Int32(codex.runningTasks) : 0,
                            usesCodexData ? Int32(codex.waitingTasks) : 0,
                            usesCodexData ? Int32(codex.finishedTasks) : 0,
                            usesCodexData && codex.quota5hValid,
                            usesCodexData && codex.reset5hValid,
                            usesCodexData && codex.quota7dValid,
                            usesCodexData && codex.reset7dValid,
                            usesCodexData && codex.monthCostValid,
                            usesCodexData && codex.monthTokensValid,
                            usesCodexData && codex.todayUsedPercentValid,
                            usesCodexData && codex.todayTokensValid)
                    }
                }
            }
        }
        agent_hub_firmware_update(agentHubFirmwareContext, nowMs)
        refreshAgentHubFramebuffer()
    }

    private func refreshAgentHubFramebuffer() {
        let frameSerial = agent_hub_firmware_frame_serial(agentHubFirmwareContext)
        guard frameSerial != lastAgentHubFrameSerial else { return }
        lastAgentHubFrameSerial = frameSerial
        agentHubFrameWidth = Int(agent_hub_firmware_frame_width(agentHubFirmwareContext))
        agentHubFrameHeight = Int(agent_hub_firmware_frame_height(agentHubFirmwareContext))
        agentHubFrameRGBA = rgbaData(from: agent_hub_firmware_framebuffer(agentHubFirmwareContext))
    }

    private func sendAgentHubButton(side: Bool, clicks: Int) {
        let wasSelectorActive = agent_hub_firmware_selector_active(agentHubFirmwareContext)
        agent_hub_firmware_button(agentHubFirmwareContext, side, Int32(clicks))
        refreshAgentHubFramebuffer()
        eventText = "\(side ? "SIDE" : "FRONT") \(gestureName(clicks))"
        let selectorActive = agent_hub_firmware_selector_active(agentHubFirmwareContext)
        let enteredProvider = wasSelectorActive && !selectorActive
        let switchedProvider = !selectorActive && side && clicks == 3
        guard codexUsesBridge, enteredProvider || switchedProvider else { return }
        ensureCodexBridgeCredentialLoaded()
        let index = Int(agent_hub_firmware_active_provider(agentHubFirmwareContext))
        guard Self.agentHubProviderIDs.indices.contains(index) else { return }
        let providerID = Self.agentHubProviderIDs[index]
        Task {
            do {
                let state = try await codexClient.selectProvider(providerID)
                if state["active_provider"] as? String == providerID {
                    applyBridgeJSON(state)
                    eventText = "BRIDGE PROVIDER \(providerID.uppercased())"
                } else {
                    eventText = "BRIDGE PROVIDER UNSUPPORTED"
                }
            } catch {
                bridgeFailed("BRIDGE PROVIDER FAILED")
            }
        }
    }

    var adaptiveFrameRGBA: Data {
        selectedProject == .agentHub ? agentHubFrameRGBA : codexFrameRGBA
    }

    var adaptiveFrameWidth: Int {
        selectedProject == .agentHub ? agentHubFrameWidth : codexFrameWidth
    }

    var adaptiveFrameHeight: Int {
        selectedProject == .agentHub ? agentHubFrameHeight : codexFrameHeight
    }

    private func sendHourglassButton(button: Int32, clicks: Int) {
        if selectedProject == .hourglassLiquid {
            hourglass_liquid_button(hourglassLiquidContext, button, Int32(clicks))
            refreshHourglassSnapshot(liquid: true)
        } else {
            hourglass_button(hourglassContext, button, Int32(clicks))
            refreshHourglassSnapshot(liquid: false)
        }
        eventText = "\(button == 0 ? "FRONT" : "SIDE") \(gestureName(clicks))"
    }

    private func rgbaData(from pixels: UnsafePointer<UInt16>?) -> Data {
        guard let pixels else { return Data() }
        let count = Int(Self.screenWidth * Self.screenHeight)
        var rgba = [UInt8](repeating: 0, count: count * 4)
        for index in 0..<count {
            let value = pixels[index]
            let offset = index * 4
            rgba[offset] = UInt8((UInt32(value >> 11) * 255 + 15) / 31)
            rgba[offset + 1] = UInt8((UInt32((value >> 5) & 0x3f) * 255 + 31) / 63)
            rgba[offset + 2] = UInt8((UInt32(value & 0x1f) * 255 + 15) / 31)
            rgba[offset + 3] = 255
        }
        return Data(rgba)
    }

    var currentPortraitFrameRGBA: Data {
        switch selectedProject {
        case .hourglass: return hourglassFrameRGBA
        case .hourglassLiquid: return hourglassLiquidFrameRGBA
        default: return breakoutFrameRGBA
        }
    }

    private func installKeyboard() {
        guard keyDownMonitor == nil else { return }
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 123: self.tilt = -1; return nil
            case 124: self.tilt = 1; return nil
            // macOS 方向键：上=设备前倾，下=设备后倾。
            case 126: self.tiltY = -1; return nil
            case 125: self.tiltY = 1; return nil
            case 49 where !event.isARepeat: self.blueButton(clicks: 1); return nil
            case 37 where !event.isARepeat: self.blueButton(clicks: 5); return nil
            case 1 where !event.isARepeat: self.setSound(!self.soundEnabled); return nil
            default: return event
            }
        }
        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) {
            [weak self] event in
            if event.keyCode == 123 || event.keyCode == 124 { self?.tilt = 0; return nil }
            if event.keyCode == 126 || event.keyCode == 125 { self?.tiltY = 0; return nil }
            return event
        }
    }

    private func soundName(_ value: Int32) -> String {
        switch value {
        case 0: return "PADDLE SOUND"
        case 1: return "BRICK SOUND"
        case 2: return "LIFE LOST SOUND"
        case 3: return "LEVEL CLEAR SOUND"
        case 4: return "GAME OVER SOUND"
        default: return "SOUND"
        }
    }
}
