import AppKit
import BreakoutCore
import CodexCore
import Foundation
import FruitCore
import HourglassCore
import HourglassLiquidCore
import SimulatorSupport

enum VirtualProject: String, CaseIterable, Identifiable {
    case breakout = "Neon Brick Pulse"
    case fruit = "水果机"
    case hourglass = "沙漏"
    case hourglassLiquid = "液态沙漏"
    case codex = "VibeStick-Codex"
    var id: String { rawValue }

    var runtimeID: SimulatorRuntimeID {
        switch self {
        case .breakout: return .breakout
        case .fruit: return .fruit
        case .hourglass: return .hourglass
        case .hourglassLiquid: return .hourglassLiquid
        case .codex: return .codex
        }
    }

    var firmwareName: String {
        switch self {
        case .breakout: return "VibeStick-Neon-Brick-Pulse"
        case .fruit: return "VibeStick-Fruit-Machine"
        case .hourglass: return "VibeStick-Hourglass"
        case .hourglassLiquid: return "VibeStick-Hourglass-Liquid"
        case .codex: return "VibeStick-Codex"
        }
    }

    var orientationHint: String {
        switch self {
        case .breakout, .fruit, .hourglass, .hourglassLiquid: return "135 × 240 竖屏固件"
        case .codex: return "135 × 240 正放 · 240 × 135 横放自适应固件"
        }
    }

    var fidelityStatus: String {
        switch self {
        case .breakout: return "同源渲染 · 真实逻辑 · 像素基准已验证"
        case .fruit: return "同源 main.c · 真实逻辑 · RGB565 原始帧"
        case .hourglass: return "同源 LVGL · 真实粒子物理 · RGB565 原始帧"
        case .hourglassLiquid: return "同源 LVGL · 真实液态沙粒 · RGB565 原始帧"
        case .codex: return "同源 main.c · 真实 LVGL · 像素基准已验证"
        }
    }

    init?(runtimeID: SimulatorRuntimeID) {
        switch runtimeID {
        case .breakout: self = .breakout
        case .fruit: self = .fruit
        case .hourglass: self = .hourglass
        case .hourglassLiquid: self = .hourglassLiquid
        case .codex: self = .codex
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

    @Published var snapshot = BreakoutSnapshot()
    @Published var ball = BreakoutBallSnapshot()
    @Published var paddle = BreakoutPaddleSnapshot()
    @Published var bricks: [BrickViewData] = []
    @Published var breakoutFrameRGBA = Data()
    @Published var fruitFrameRGBA = Data()
    @Published var fruitSnapshot = FruitSnapshot()
    @Published var hourglassFrameRGBA = Data()
    @Published var hourglassLiquidFrameRGBA = Data()
    @Published var hourglassSnapshot = HourglassSnapshot()
    @Published var hourglassLiquidSnapshot = HourglassLiquidSnapshot()
    @Published var codexFrameRGBA = Data()
    @Published var tilt: Double = 0
    @Published var tiltY: Double = 0
    @Published var tiltZ: Double = 1
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
    @Published private(set) var testProjects: [SimulatorProjectReference] = []
    @Published var projectLibraryMessage = ""
    @Published private(set) var isRebuilding = false
    @Published private(set) var rebuildPhase: SimulatorRebuildPhase = .idle
    @Published private(set) var rebuildLog = ""
    @Published private(set) var lastSuccessfulRebuild: Date?
    @Published private(set) var resourceMetrics = SimulatorResourceMetrics()
    @Published private(set) var measuredSimulatorFPS = 0.0

    private var context: UnsafeMutableRawPointer?
    private var fruitContext: UnsafeMutableRawPointer?
    private var hourglassContext: UnsafeMutableRawPointer?
    private var hourglassLiquidContext: UnsafeMutableRawPointer?
    private var codexFirmwareContext: UnsafeMutableRawPointer?
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()
    private var startedAt = CACurrentMediaTime()
    private var lastSoundSerial: UInt32 = 0
    private var lastFruitSoundSerial: UInt32 = 0
    private var lastLiquidChimeSerial: UInt32 = 0
    private var lastBreakoutFrameSerial = UInt32.max
    private var lastFruitFrameSerial = UInt32.max
    private var lastHourglassFrameSerial = UInt32.max
    private var lastLiquidFrameSerial = UInt32.max
    private var lastCodexFrameSerial = UInt32.max
    private var fruitMotionArmed = true
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
        fruitContext = fruit_create()
        hourglassContext = hourglass_create()
        hourglassLiquidContext = hourglass_liquid_create()
        codexFirmwareContext = codex_firmware_create()
        syncFirmwareDisplayForPose()
        let high = UInt32(defaults.integer(forKey: "neonbrick.high"))
        let unlocked = UInt8(max(1, defaults.integer(forKey: "neonbrick.unlock")))
        soundEnabled = defaults.object(forKey: "neonbrick.sound") == nil
            ? true : defaults.bool(forKey: "neonbrick.sound")
        breakout_load_persistent(context, high, unlocked)
        breakout_set_sound_enabled(context, soundEnabled)
        refreshSnapshot()
        refreshFruitSnapshot()
        refreshHourglassSnapshot(liquid: false)
        refreshHourglassSnapshot(liquid: true)
        syncCodexFirmwareState(nowMs: 0)
        refreshResourceMetrics()
    }

    isolated deinit {
        timer?.invalidate()
        if let keyDownMonitor { NSEvent.removeMonitor(keyDownMonitor) }
        if let keyUpMonitor { NSEvent.removeMonitor(keyUpMonitor) }
        breakout_destroy(context)
        fruit_destroy(fruitContext)
        hourglass_destroy(hourglassContext)
        hourglass_liquid_destroy(hourglassLiquidContext)
        codex_firmware_destroy(codexFirmwareContext)
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
            .appendingPathComponent("build/Stick S3 虚拟设备.app", isDirectory: true)
        let desktopApp = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/Stick S3 虚拟设备.app", isDirectory: true)

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
        if project.runtimeID == .codex { resetCodexBridgeCredential() }
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

    var hasImportedFirmware: Bool { !visibleProjects.isEmpty }
    var hasRunnableFirmware: Bool {
        selectedSourceProject?.compatibility == .ready
    }
    var canReloadSelectedFirmware: Bool {
        guard simulatorProjectRoot != nil,
              let project = selectedSourceProject,
              project.compatibility != .binaryOnly,
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
        case .fruit:
            fruit_destroy(fruitContext)
            fruitContext = fruit_create()
            lastFruitFrameSerial = .max
            fruit_set_sound(fruitContext, soundEnabled)
            let battery = Int32(max(0, min(100, Int(batteryPercent))))
            fruit_set_power(fruitContext, battery, batteryCharging, false)
            refreshFruitSnapshot()
            lastFruitSoundSerial = fruitSnapshot.sound_serial
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

    func setSound(_ value: Bool) {
        soundEnabled = value
        breakout_set_sound_enabled(context, value)
        fruit_set_sound(fruitContext, value)
        defaults.set(value, forKey: "neonbrick.sound")
        if !value { deviceAudio.stop() }
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
        let battery = Int32(max(0, min(100, Int(batteryPercent))))
        fruit_set_power(fruitContext, battery, batteryCharging, false)
        if selectedProject == .fruit {
            refreshFruitSnapshot()
        } else if selectedProject == .codex {
            let elapsed = UInt32(min(Double(UInt32.max),
                                     (CACurrentMediaTime() - startedAt) * 1000))
            syncCodexFirmwareState(nowMs: elapsed)
        }
    }

    func primaryShort() {
        if selectedProject == .codex {
            sendCodexEvent("front_short")
            return
        }
        if selectedProject == .fruit {
            fruit_button(fruitContext, 0, 1)
            eventText = "FRONT SINGLE"
            refreshFruitSnapshot()
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
        if selectedProject == .codex {
            toggleCodexRecording()
            return
        }
        if selectedProject == .fruit {
            fruit_button(fruitContext, 0, 5)
            eventText = "FRONT LONG"
            refreshFruitSnapshot()
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
        if selectedProject == .codex {
            updateCodexClock(current)
            syncCodexFirmwareState(nowMs: elapsed)
            handleCodexAudioEvents()
            if codexUsesBridge && current - lastBridgePoll >= 2.0 {
                ensureCodexBridgeCredentialLoaded()
                lastBridgePoll = current
                refreshCodexBridge()
            }
            return
        }
        if selectedProject == .fruit {
            fruit_update(fruitContext, elapsed)
            updateFruitMotion()
            refreshFruitSnapshot()
            if fruitSnapshot.sound_serial != lastFruitSoundSerial {
                lastFruitSoundSerial = fruitSnapshot.sound_serial
                if audioPlaybackAllowed {
                    deviceAudio.playFruit(sound: fruitSnapshot.last_sound)
                }
                eventText = "FRUIT SOUND \(fruitSnapshot.last_sound)"
            }
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
        guard supports(button: .front, clicks: clicks) else {
            eventText = "FRONT \(gestureName(clicks)) UNBOUND"
            return
        }
        if selectedProject == .breakout {
            if clicks == 1 { primaryShort() } else { primaryLong() }
            return
        }
        if selectedProject == .fruit {
            fruit_button(fruitContext, 0, Int32(clicks))
            eventText = "FRONT \(gestureName(clicks))"
            refreshFruitSnapshot()
            return
        }
        if selectedProject == .hourglass || selectedProject == .hourglassLiquid {
            sendHourglassButton(button: 0, clicks: clicks)
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
        guard supports(button: .side, clicks: clicks) else {
            eventText = "SIDE \(gestureName(clicks)) UNBOUND"
            return
        }
        if selectedProject == .breakout {
            setSound(!soundEnabled)
            eventText = "SIDE SINGLE · SOUND \(soundEnabled ? "ON" : "OFF")"
            return
        }
        if selectedProject == .fruit {
            fruit_button(fruitContext, 1, Int32(clicks))
            eventText = "SIDE \(gestureName(clicks))"
            refreshFruitSnapshot()
            return
        }
        if selectedProject == .hourglass || selectedProject == .hourglassLiquid {
            sendHourglassButton(button: 1, clicks: clicks)
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
        guard hasRunnableFirmware else { return false }
        switch selectedProject {
        case .breakout:
            return button == .front ? (clicks == 1 || clicks == 5) : clicks == 1
        case .fruit:
            return button == .front ? (clicks == 1 || clicks == 2 || clicks == 5)
                                    : (clicks == 1 || clicks == 2 || clicks == 4 || clicks == 5)
        case .hourglass, .hourglassLiquid:
            return button == .front ? (clicks == 1 || clicks == 2)
                                    : (clicks == 1 || clicks == 2 || clicks == 3 || clicks == 5)
        case .codex:
            return button == .front ? (clicks == 1 || clicks == 2 || clicks == 5)
                                    : (clicks == 1 || clicks == 2 || clicks == 3 || clicks == 5)
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
        let projectRoot = testProjects.first(where: { $0.runtimeID == .codex })?.sourcePath
        bridgeToken = BridgeCredentialStore.loadToken(projectRoot: projectRoot)
    }

    private func resetCodexBridgeCredential() {
        bridgeToken = ""
        hasLoadedBridgeCredential = false
    }

    private func syncFirmwareDisplayForPose() {
        guard selectedProject.runtimeID.displayLayout == .poseAdaptive else { return }
        // 自适应适配器统一从这个入口接收姿态；新固件不得在视图中猜测方向。
        guard selectedProject == .codex, codexFirmwareContext != nil else { return }
        let landscape = devicePose.isQuarterTurn
        codex_firmware_set_orientation(
            codexFirmwareContext,
            landscape,
            landscape && devicePose == .left90
        )
        refreshCodexFramebuffer()
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

    private func refreshFruitSnapshot() {
        let frameSerial = fruit_frame_serial(fruitContext)
        guard frameSerial != lastFruitFrameSerial else { return }
        lastFruitFrameSerial = frameSerial
        fruitSnapshot = fruit_snapshot(fruitContext)
        fruitFrameRGBA = rgbaData(from: fruit_framebuffer(fruitContext))
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

    private func updateFruitMotion() {
        let x = tilt
        let y = tiltY
        if fruitMotionArmed {
            if abs(x) >= 0.55 {
                fruit_motion(fruitContext, x < 0 ? -1 : 1, 0)
                fruitMotionArmed = false
            } else if abs(y) >= 0.55 {
                fruit_motion(fruitContext, 0, y < 0 ? -1 : 1)
                fruitMotionArmed = false
            }
        } else if abs(x) < 0.25 && abs(y) < 0.25 {
            fruitMotionArmed = true
        }
    }

    var currentPortraitFrameRGBA: Data {
        switch selectedProject {
        case .fruit: return fruitFrameRGBA
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
