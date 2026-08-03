import BreakoutCore
import CodexCore
import FruitCore
import Foundation
import HourglassCore
import HourglassLiquidCore
import SimulatorSupport
@testable import StickS3Simulator
import XCTest

final class BreakoutCoreTests: XCTestCase {
    func testResourceInspectorUsesRealPartitionAndAppImageSizes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("resource-metrics-\(UUID().uuidString)", isDirectory: true)
        let firmware = root.appendingPathComponent("firmware/sticks3", isDirectory: true)
        let build = firmware.appendingPathComponent("build", isDirectory: true)
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let partitions = """
        # Name, Type, SubType, Offset, Size, Flags
        nvs, data, nvs, 0x9000, 0x6000,
        ota_0, app, ota_0, 0x20000, 0x300000,
        ota_1, app, ota_1, 0x320000, 0x300000,
        """
        try Data(partitions.utf8).write(to: firmware.appendingPathComponent("partitions.csv"))
        try Data(repeating: 0x5A, count: 1_048_576)
            .write(to: build.appendingPathComponent("test-app.bin"))
        let flasher = """
        {"app":{"offset":"0x20000","file":"test-app.bin","encrypted":"false"}}
        """
        try Data(flasher.utf8).write(to: build.appendingPathComponent("flasher_args.json"))

        let metrics = SimulatorResourceInspector().inspect(projectRoot: root, firmwareRoot: firmware)
        XCTAssertEqual(metrics.appImageBytes, 1_048_576)
        XCTAssertEqual(metrics.appPartitionBytes, 3_145_728)
        XCTAssertEqual(metrics.appPartitions, [
            SimulatorAppPartition(name: "ota_0", subtype: "ota_0", sizeBytes: 3_145_728),
            SimulatorAppPartition(name: "ota_1", subtype: "ota_1", sizeBytes: 3_145_728),
        ])
        XCTAssertEqual(metrics.remainingAppBytes, 2_097_152)
        XCTAssertEqual(metrics.appUsageRatio ?? 0, 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(metrics.appFitsPartition, true)
    }

    @MainActor
    func testSimulatorCommonControlsAndRestartLifecycle() {
        let defaults = UserDefaults.standard
        let savedFirmware = defaults.object(forKey: "simulator.firmware")
        defer {
            if let savedFirmware {
                defaults.set(savedFirmware, forKey: "simulator.firmware")
            } else {
                defaults.removeObject(forKey: "simulator.firmware")
            }
        }
        let model = SimulatorModel()
        model.setSimulationRunning(false)
        XCTAssertFalse(model.running)
        model.setSimulationRunning(true)
        XCTAssertTrue(model.running)
        model.setScreenBrightness(37.4)
        XCTAssertEqual(model.screenBrightnessPercent, 37)
        model.setDevicePose(.left90)
        XCTAssertEqual(model.devicePose, .left90)
        XCTAssertEqual(model.tilt, -1)
        XCTAssertEqual(model.tiltY, 0)
        XCTAssertEqual(model.tiltZ, 0)
        model.setDevicePose(.upright)
        XCTAssertEqual(model.tilt, 0)
        XCTAssertEqual(model.tiltY, 0)
        XCTAssertEqual(model.tiltZ, 1)
        for project in VirtualProject.allCases {
            model.selectedProject = project
            model.restartSelectedFirmware()
            XCTAssertEqual(model.eventText, "FIRMWARE RESTARTED")
        }
        model.stop()
    }

    func testEveryFirmwareCanRestartRepeatedlyWithoutStaleContexts() {
        for iteration in 0..<25 {
            let breakout = breakout_create(135, 240)
            XCTAssertNotNil(breakout)
            breakout_update(breakout, 1.0 / 60.0, 0, UInt32(iteration * 16))
            XCTAssertNotNil(breakout_framebuffer(breakout))
            breakout_destroy(breakout)

            let fruit = fruit_create()
            XCTAssertNotNil(fruit)
            fruit_update(fruit, UInt32(iteration * 20))
            XCTAssertNotNil(fruit_framebuffer(fruit))
            fruit_destroy(fruit)

            let hourglass = hourglass_create()
            XCTAssertNotNil(hourglass)
            hourglass_update(hourglass, UInt32(iteration * 33), 0, 1)
            XCTAssertNotNil(hourglass_framebuffer(hourglass))
            hourglass_destroy(hourglass)

            let liquid = hourglass_liquid_create()
            XCTAssertNotNil(liquid)
            hourglass_liquid_update(liquid, UInt32(iteration * 33), 0, 1)
            XCTAssertNotNil(hourglass_liquid_framebuffer(liquid))
            hourglass_liquid_destroy(liquid)

            let codex = codex_firmware_create()
            XCTAssertNotNil(codex)
            codex_firmware_update(codex, UInt32(iteration * 36))
            XCTAssertNotNil(codex_firmware_framebuffer(codex))
            codex_firmware_destroy(codex)
        }
    }

    func testFirmwareCatalogContainsOnlyExplicitlyImportedProjects() {
        let composer = SimulatorFirmwareCatalogComposer()
        let readyCodex = SimulatorProjectReference(
            displayName: "VibeStick-Codex",
            sourcePath: "/workspace/VibeStick-Codex",
            firmwarePath: "/workspace/VibeStick-Codex/firmware/sticks3",
            runtimeID: .codex,
            compatibility: .ready,
            detail: "ready"
        )
        let downloaded = SimulatorProjectReference(
            displayName: "Downloaded Demo",
            sourcePath: "/downloads/demo",
            firmwarePath: "/downloads/demo/firmware/sticks3",
            runtimeID: nil,
            compatibility: .sourceNeedsAdapter,
            detail: "adapter needed"
        )

        XCTAssertTrue(composer.compose(projects: []).isEmpty)
        let catalog = composer.compose(projects: [readyCodex, downloaded])
        XCTAssertEqual(catalog.count, 2)
        XCTAssertEqual(catalog.first(where: { $0.runtimeID == .codex })?.sourcePath,
                       readyCodex.sourcePath)
        XCTAssertEqual(catalog.first(where: { $0.runtimeID == .codex })?.canSimulate, true)
        XCTAssertEqual(catalog.first(where: { $0.displayName == "Downloaded Demo" })?.canSimulate, false)
        XCTAssertEqual(catalog.filter { $0.displayName == "VibeStick-Codex" }.count, 1)
        let downloadedItem = catalog.first(where: { $0.displayName == "Downloaded Demo" })
        XCTAssertEqual(downloadedItem?.source, .linked)
        XCTAssertEqual(downloadedItem?.compatibility, .sourceNeedsAdapter)
    }

    func testSimulatorRebuildOutputParserTracksRealBuildStages() {
        let parser = SimulatorRebuildOutputParser()
        XCTAssertEqual(parser.phase(for: "REBUILD-STEP:TESTS", current: .idle), .testing)
        XCTAssertEqual(parser.phase(for: "REBUILD-STEP:BUILD", current: .testing), .preparing)
        XCTAssertEqual(parser.phase(for: "[12/80] Compiling lv_font.c", current: .preparing), .compiling)
        XCTAssertEqual(parser.phase(for: "Linking StickS3Simulator", current: .compiling), .linking)
        XCTAssertEqual(parser.phase(for: "REBUILD-STEP:SIGNING", current: .linking), .signing)
        XCTAssertEqual(parser.phase(for: "error: build stopped", current: .compiling), .failed)
    }

    func testSimulatorProjectInspectorFindsKnownReadOnlyProject() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sticks3-inspector-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("VibeStick-Codex", isDirectory: true)
        let firmware = project.appendingPathComponent("firmware/sticks3", isDirectory: true)
        try FileManager.default.createDirectory(
            at: firmware.appendingPathComponent("src", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data().write(to: firmware.appendingPathComponent("CMakeLists.txt"))
        try Data().write(to: firmware.appendingPathComponent("src/main.c"))

        let inspector = SimulatorProjectInspector(readyProjectRoots: [.codex: project.path])
        let reference = inspector.inspect(project)
        XCTAssertEqual(reference.compatibility, .ready)
        XCTAssertEqual(reference.runtimeID, .codex)
        XCTAssertEqual(reference.sourcePath, project.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firmware.appendingPathComponent("src/main.c").path))

        let otherBuild = SimulatorProjectInspector().inspect(project)
        XCTAssertEqual(otherBuild.compatibility, .sourceNeedsAdapter)
        XCTAssertEqual(otherBuild.runtimeID, .codex)

        let packagedBuild = SimulatorProjectInspector(packagedRuntimeIDs: [.codex]).inspect(project)
        XCTAssertEqual(packagedBuild.compatibility, .ready)
        XCTAssertEqual(packagedBuild.runtimeID, .codex)
    }

    func testImportedProjectMustMatchEmbeddedSourceFingerprint() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sticks3-fingerprint-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("VibeStick-Codex", isDirectory: true)
        let firmware = project.appendingPathComponent("firmware/sticks3", isDirectory: true)
        try FileManager.default.createDirectory(at: firmware, withIntermediateDirectories: true)
        try Data().write(to: firmware.appendingPathComponent("CMakeLists.txt"))
        for relativePath in SimulatorSourceFingerprint.relativeFiles(for: .codex) {
            let file = firmware.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("\(relativePath)-v1".utf8).write(to: file)
        }
        let fingerprint = try SimulatorSourceFingerprint.calculate(runtime: .codex, firmwareRoot: firmware)
        let matching = SimulatorProjectInspector(packagedFingerprints: [.codex: fingerprint]).inspect(project)
        XCTAssertEqual(matching.compatibility, .ready)
        XCTAssertEqual(matching.sourceFingerprint, fingerprint)

        try Data("main-v2".utf8).write(to: firmware.appendingPathComponent("src/main.c"))
        let updated = SimulatorProjectInspector(packagedFingerprints: [.codex: fingerprint]).inspect(project)
        XCTAssertEqual(updated.compatibility, .sourceNeedsAdapter)
        XCTAssertNotEqual(updated.sourceFingerprint, fingerprint)
    }

    func testSimulatorProjectInspectorDoesNotPretendBinCanRun() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sticks3-bin-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let binary = root.appendingPathComponent("downloaded-full.bin")
        try Data([0xe9, 0x00, 0x00, 0x00]).write(to: binary)

        let reference = SimulatorProjectInspector().inspect(binary)
        XCTAssertEqual(reference.compatibility, .binaryOnly)
        XCTAssertFalse(reference.compatibility.canSimulate)
        XCTAssertNil(reference.runtimeID)
    }

    func testSimulatorProjectLibraryPersistsAndDeduplicatesPaths() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sticks3-library-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appendingPathComponent("projects.json")
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        let library = SimulatorProjectLibrary(storageURL: storage, cacheRootURL: cache)
        let first = SimulatorProjectReference(
            displayName: "Sample",
            sourcePath: "/tmp/sample-project",
            firmwarePath: "/tmp/sample-project/firmware/sticks3",
            runtimeID: nil,
            compatibility: .sourceNeedsAdapter,
            detail: "first"
        )
        var updated = first
        updated.id = UUID()
        updated.detail = "updated"

        let merged = library.merging([first, updated], into: [])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.detail, "updated")
        XCTAssertEqual(merged.first?.id, first.id)
        try library.save(merged)
        let loaded = library.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, merged.first?.id)
        XCTAssertEqual(loaded.first?.sourcePath, merged.first?.sourcePath)
        XCTAssertEqual(loaded.first?.detail, "updated")
        XCTAssertEqual(loaded.first?.compatibility, .sourceNeedsAdapter)
    }

    func testCodexFirmwareLandscapePixelBaseline() {
        let context = codex_firmware_create()
        XCTAssertNotNil(context)
        defer { codex_firmware_destroy(context) }
        codex_firmware_set_state(
            context, "RUNNING", "12:34", "AUG 1", "SAT.",
            86, true, true, 72, 194, 46, 3420,
            38.4, 12_800_000, 23, 456_000, 2, 1, 8,
            true, true, true, true, true, true, true, true)
        codex_firmware_update(context, 0)
        guard let pixels = codex_firmware_framebuffer(context) else {
            return XCTFail("Codex 真机 LVGL 未返回帧缓冲")
        }
        // 真机首帧保持小人动画第 0 帧，不在显示刷新时额外跳帧。
        XCTAssertEqual(checksum(pixels), 10_070_479_879_698_489_007)
        let snapshot = codex_firmware_snapshot(context)
        XCTAssertEqual(snapshot.quota_5h, 72)
        XCTAssertEqual(snapshot.running_tasks, 2)
        XCTAssertEqual(snapshot.battery, 86)
        XCTAssertEqual(snapshot.today_used_percent, 23)
        XCTAssertEqual(snapshot.today_tokens, 456_000)
        codex_firmware_set_recording(context, true)
        XCTAssertTrue(codex_firmware_snapshot(context).recording)
    }

    func testAllFirmwareAdaptersDeclarePhysicalPoseAndDisplayLayout() {
        for runtime in SimulatorRuntimeID.allCases {
            XCTAssertEqual(runtime.posedDevicePixelSize(isQuarterTurn: false).width, 135)
            XCTAssertEqual(runtime.posedDevicePixelSize(isQuarterTurn: false).height, 240)
            XCTAssertEqual(runtime.posedDevicePixelSize(isQuarterTurn: true).width, 240)
            XCTAssertEqual(runtime.posedDevicePixelSize(isQuarterTurn: true).height, 135)
        }
        XCTAssertEqual(SimulatorRuntimeID.codex.displayLayout, .poseAdaptive)
        XCTAssertEqual(SimulatorRuntimeID.codex.liveDataPolicy, .importedProjectEnvironment)
        XCTAssertTrue(SimulatorRuntimeID.allCases
            .filter { $0 != .codex }
            .allSatisfy { $0.displayLayout == .fixedPortrait })
        XCTAssertTrue(SimulatorRuntimeID.allCases
            .filter { $0 != .codex }
            .allSatisfy { $0.liveDataPolicy == .none })
    }

    func testCodexFirmwareSwitchesBetweenPortraitAndLandscapeFrames() {
        let context = codex_firmware_create()
        XCTAssertNotNil(context)
        defer { codex_firmware_destroy(context) }
        XCTAssertEqual(codex_firmware_frame_width(context), 240)
        XCTAssertEqual(codex_firmware_frame_height(context), 135)

        codex_firmware_set_orientation(context, false, false)
        XCTAssertEqual(codex_firmware_frame_width(context), 135)
        XCTAssertEqual(codex_firmware_frame_height(context), 240)

        codex_firmware_set_orientation(context, true, false)
        XCTAssertEqual(codex_firmware_frame_width(context), 240)
        XCTAssertEqual(codex_firmware_frame_height(context), 135)
    }

    func testCodexPersonAnimationUsesFirmwareTimingInsteadOfDisplayFPS() {
        let context = codex_firmware_create()
        XCTAssertNotNil(context)
        defer { codex_firmware_destroy(context) }
        codex_firmware_set_state(
            context, "RUNNING", "12:34", "AUG 1", "SAT.",
            86, true, true, 72, 194, 46, 3420,
            38.4, 12_800_000, 23, 456_000, 2, 1, 8,
            true, true, true, true, true, true, true, true)

        codex_firmware_update(context, 0)
        XCTAssertEqual(codex_firmware_snapshot(context).status_person_frame, 0)
        codex_firmware_update(context, 16) // 60 FPS 的一帧不应推进小人。
        XCTAssertEqual(codex_firmware_snapshot(context).status_person_frame, 0)
        codex_firmware_update(context, 119)
        XCTAssertEqual(codex_firmware_snapshot(context).status_person_frame, 0)
        codex_firmware_update(context, 120)
        XCTAssertEqual(codex_firmware_snapshot(context).status_person_frame, 1)
    }

    private func checksum(_ pixels: UnsafePointer<UInt16>) -> UInt64 {
        var value: UInt64 = 14_695_981_039_346_656_037
        for index in 0..<(135 * 240) {
            value ^= UInt64(pixels[index])
            value &*= 1_099_511_628_211
        }
        return value
    }

    func testHourglassFirmwarePixelBaselinesAndControls() {
        let classic = hourglass_create()
        let liquid = hourglass_liquid_create()
        XCTAssertNotNil(classic); XCTAssertNotNil(liquid)
        defer { hourglass_destroy(classic); hourglass_liquid_destroy(liquid) }
        guard let classicPixels = hourglass_framebuffer(classic),
              let liquidPixels = hourglass_liquid_framebuffer(liquid) else {
            return XCTFail("沙漏真实 LVGL 未返回帧缓冲")
        }
        XCTAssertEqual(checksum(classicPixels), 8_872_473_467_084_417_844)
        XCTAssertEqual(checksum(liquidPixels), 16_215_082_296_444_206_994)
        XCTAssertEqual(hourglass_snapshot(classic).duration_minutes, 5)
        XCTAssertEqual(hourglass_liquid_snapshot(liquid).duration_minutes, 5)
        hourglass_button(classic, 1, 1)
        hourglass_liquid_button(liquid, 1, 1)
        XCTAssertEqual(hourglass_snapshot(classic).duration_minutes, 10)
        XCTAssertEqual(hourglass_liquid_snapshot(liquid).duration_minutes, 10)
        hourglass_button(classic, 0, 1)
        hourglass_liquid_button(liquid, 0, 1)
        XCTAssertTrue(hourglass_snapshot(classic).running)
        XCTAssertTrue(hourglass_liquid_snapshot(liquid).running)
    }

    func testFruitFirmwareCoreAndPixelBaseline() {
        let context = fruit_create()
        XCTAssertNotNil(context)
        defer { fruit_destroy(context) }
        guard let pixels = fruit_framebuffer(context) else {
            return XCTFail("水果机真机渲染代码未返回帧缓冲")
        }
        var checksum: UInt64 = 14_695_981_039_346_656_037
        for index in 0..<(135 * 240) {
            checksum ^= UInt64(pixels[index])
            checksum &*= 1_099_511_628_211
        }
        // 水果机真实 main.c READY 帧；颜色、图块或坐标漂移都会失败。
        XCTAssertEqual(checksum, 13_888_363_629_808_309_653)

        let initial = fruit_snapshot(context)
        XCTAssertEqual(initial.credit, 0)
        fruit_button(context, 1, 1)
        XCTAssertEqual(fruit_snapshot(context).credit, 5)
        fruit_motion(context, -1, 0)
        XCTAssertNotEqual(fruit_snapshot(context).selected_control,
                          initial.selected_control)
    }

    func testFruitSelectedGoStartsAfterARealBet() {
        let context = fruit_create()
        XCTAssertNotNil(context)
        defer { fruit_destroy(context) }

        // GO 无下注时按真机规则保持 IDLE，屏幕提示 ADD BET。
        XCTAssertEqual(fruit_snapshot(context).selected_control, 13)
        fruit_button(context, 0, 1)
        XCTAssertEqual(fruit_snapshot(context).state, 0)

        // 用侧键双击向前选到一个水果，蓝键下注后再回到 GO。
        var guardCount = 0
        while fruit_snapshot(context).selected_control >= 8 && guardCount < 14 {
            fruit_button(context, 1, 2)
            guardCount += 1
        }
        XCTAssertLessThan(fruit_snapshot(context).selected_control, 8)
        fruit_button(context, 0, 1)
        guardCount = 0
        while fruit_snapshot(context).selected_control != 13 && guardCount < 14 {
            fruit_button(context, 1, 2)
            guardCount += 1
        }
        XCTAssertEqual(fruit_snapshot(context).selected_control, 13)
        fruit_button(context, 0, 1)
        XCTAssertNotEqual(fruit_snapshot(context).state, 0)
    }

    func testFruitPowerControlsUpdateFirmwareState() {
        let context = fruit_create()
        XCTAssertNotNil(context)
        defer { fruit_destroy(context) }
        fruit_set_power(context, 37, false, false)
        let snapshot = fruit_snapshot(context)
        XCTAssertEqual(snapshot.battery, 37)
        XCTAssertFalse(snapshot.battery_charging)
        XCTAssertFalse(snapshot.usb_powered)
    }

    func testRealFirmwareRendererProducesStableRGB565Frame() {
        let context = breakout_create(135, 240)
        XCTAssertNotNil(context)
        defer { breakout_destroy(context) }
        guard let pixels = breakout_framebuffer(context) else {
            return XCTFail("真机渲染器未返回帧缓冲")
        }
        var checksum: UInt64 = 14_695_981_039_346_656_037
        for index in 0..<(135 * 240) {
            checksum ^= UInt64(pixels[index])
            checksum &*= 1_099_511_628_211
        }
        // 真机 GameRenderer 的 TITLE 帧像素基准；任意字体、坐标或颜色漂移都会失败。
        XCTAssertEqual(checksum, 5_019_604_954_891_630_778)
        XCTAssertGreaterThan(breakout_frame_serial(context), 0)
    }

    func testRealFirmwareCoreRunsOnMac() {
        let context = breakout_create(135, 240)
        XCTAssertNotNil(context)
        defer { breakout_destroy(context) }

        var initial = breakout_snapshot(context)
        XCTAssertEqual(initial.state, 0)
        XCTAssertEqual(initial.width, 135)
        XCTAssertEqual(initial.height, 240)

        breakout_primary_short(context)
        initial = breakout_snapshot(context)
        XCTAssertEqual(initial.state, 1)
        XCTAssertGreaterThan(breakout_brick_count(context), 20)

        breakout_primary_short(context)
        for frame in 0..<600 {
            let direction: Float = frame % 180 < 90 ? 80 : -80
            breakout_update(context, 1.0 / 60.0, direction, UInt32(frame * 16))
        }
        let after = breakout_snapshot(context)
        XCTAssertGreaterThanOrEqual(after.score, 0)
        XCTAssertGreaterThanOrEqual(after.lives, 1)
        let ball = breakout_ball(context)
        XCTAssertTrue(ball.x.isFinite)
        XCTAssertTrue(ball.y.isFinite)
    }
}
