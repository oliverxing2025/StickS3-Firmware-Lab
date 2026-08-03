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
    private func writeValidFullFlash(to url: URL, size: Int = 2 * 1024 * 1024) throws {
        var image = Data(repeating: 0xFF, count: size)
        image[0] = 0xE9
        image[0x8000] = 0xAA
        image[0x8001] = 0x50
        try image.write(to: url)
    }

    func testFirmwareToolDiscoveryDoesNotSilentlyDependOnShellPath() throws {
        let emptySupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("firmware-tool-discovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: emptySupport, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptySupport) }
        let shellBin = emptySupport.appendingPathComponent("shell-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: shellBin, withIntermediateDirectories: true)
        let shellPlatformIO = shellBin.appendingPathComponent("pio")
        try Data("#!/bin/sh\n".utf8).write(to: shellPlatformIO)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shellPlatformIO.path)

        let installation = StickS3FirmwareToolDiscovery().locate(
            for: .platformIO,
            environment: ["PATH": shellBin.path],
            bundleResourceURL: nil,
            applicationSupportURL: emptySupport,
            standardExecutableURLs: []
        )
        XCTAssertNil(installation)

        let explicit = StickS3FirmwareToolDiscovery().locate(
            for: .platformIO,
            environment: ["PATH": "", "STICKS3_PLATFORMIO_PATH": shellPlatformIO.path],
            bundleResourceURL: nil,
            applicationSupportURL: emptySupport,
            standardExecutableURLs: []
        )
        XCTAssertEqual(explicit?.executableURL, shellPlatformIO.standardizedFileURL)

        let standardHome = emptySupport.appendingPathComponent("standard-home", isDirectory: true)
        let standardPlatformIO = standardHome.appendingPathComponent(".platformio/penv/bin/platformio")
        try FileManager.default.createDirectory(
            at: standardPlatformIO.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: standardPlatformIO)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: standardPlatformIO.path)
        let standard = StickS3FirmwareToolDiscovery().locate(
            for: .platformIO,
            environment: ["PATH": ""],
            bundleResourceURL: nil,
            applicationSupportURL: emptySupport,
            homeDirectory: standardHome,
            standardExecutableURLs: []
        )
        XCTAssertEqual(standard?.executableURL, standardPlatformIO.standardizedFileURL)
        XCTAssertEqual(standard?.bundled, false)

        let localIDFPy = standardHome.appendingPathComponent(".espressif/v5.5.3/esp-idf/tools/idf.py")
        let localPython = standardHome.appendingPathComponent(
            ".espressif/python_env/idf5.5_py3.13_env/bin/python")
        try FileManager.default.createDirectory(
            at: localIDFPy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: localPython.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: localIDFPy)
        try Data("#!/bin/sh\n".utf8).write(to: localPython)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: localPython.path)
        let localIDF = StickS3FirmwareToolDiscovery().locate(
            for: .espIDF,
            environment: ["PATH": ""],
            bundleResourceURL: nil,
            applicationSupportURL: emptySupport,
            homeDirectory: standardHome,
            standardExecutableURLs: []
        )
        XCTAssertEqual(localIDF?.executableURL, localPython.standardizedFileURL)
        XCTAssertEqual(localIDF?.prefixArguments, [localIDFPy.resolvingSymlinksInPath().path])
    }

    func testQEMUDiscoveryAndCommandUseDirectArgumentsWithoutShell() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("qemu-command-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let executable = root.appendingPathComponent("qemu-system-xtensa")
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let flash = root.appendingPathComponent("firmware with spaces.bin")
        try writeValidFullFlash(to: flash)

        let installation = StickS3QEMUDiscovery().locate(
            environment: ["STICKS3_QEMU_PATH": executable.path, "PATH": ""],
            bundleResourceURL: nil,
            homeDirectory: root
        )
        XCTAssertEqual(installation?.executableURL, executable.standardizedFileURL)
        let command = try StickS3QEMUCommandBuilder().makeCommand(
            installation: try XCTUnwrap(installation),
            flashImageURL: flash,
            inheritedEnvironment: [
                "HOME": root.path,
                "LANG": "zh_CN.UTF-8",
                "VIBE_STICK_BRIDGE_TOKEN": "must-not-reach-qemu",
            ]
        )
        XCTAssertEqual(command.executableURL, executable.standardizedFileURL)
        XCTAssertTrue(command.arguments.contains("-M"))
        XCTAssertTrue(command.arguments.contains("esp32s3"))
        XCTAssertTrue(command.arguments.contains("file=\(flash.path),if=mtd,format=raw"))
        XCTAssertTrue(command.arguments.contains("-nographic"))
        XCTAssertTrue(command.arguments.contains(where: { $0.contains("qemu-esp32s3-efuse.bin") }))
        XCTAssertFalse(command.arguments.contains("-nic"))
        XCTAssertFalse(command.arguments.contains("/bin/sh"))
        XCTAssertEqual(command.environment["HOME"], root.path)
        XCTAssertEqual(command.environment["LANG"], "zh_CN.UTF-8")
        XCTAssertNil(command.environment["VIBE_STICK_BRIDGE_TOKEN"])
    }

    func testVirtualBoardProtocolSeparatesLogsAndPartialFramebufferPackets() throws {
        var payload = Data([0x02, 0x00, 0x01, 0x00]) // 2 x 1
        payload.append(contentsOf: [0x07, 0x00, 0x00, 0x00]) // sequence 7
        payload.append(contentsOf: [0x00, 0xF8, 0xE0, 0x07]) // red, green RGB565 LE
        var packet = Data([0x53, 0x33, 0x56, 0x44, 0x01, 0x02])
        var length = UInt32(payload.count).littleEndian
        withUnsafeBytes(of: &length) { packet.append(contentsOf: $0) }
        packet.append(payload)

        var parser = StickS3VirtualBoardStreamParser()
        let first = parser.append(Data("boot log\n".utf8) + packet.prefix(7))
        XCTAssertEqual(first, [.log(Data("boot log\n".utf8))])
        let second = parser.append(packet.dropFirst(7))
        XCTAssertEqual(second, [.frame(StickS3VirtualBoardFrame(
            width: 2, height: 1, sequence: 7,
            rgb565: Data([0x00, 0xF8, 0xE0, 0x07])))])
    }

    func testVirtualBoardControlPacketsCoverButtonsAndBMI270() {
        let encoder = StickS3VirtualBoardPacketEncoder()
        let button = encoder.button(.front, clicks: 2)
        XCTAssertEqual(button.prefix(6), Data([0x53, 0x33, 0x56, 0x44, 0x01, 0x11]))
        XCTAssertEqual(button.suffix(2), Data([0x00, 0x02]))
        let motion = encoder.motion(x: -1, y: 0.25, z: 1)
        XCTAssertEqual(motion.prefix(6), Data([0x53, 0x33, 0x56, 0x44, 0x01, 0x12]))
        XCTAssertEqual(motion.count, 10 + 12)
    }

    func testFirmwareBuildWorkspaceKeepsGeneratedDirectoriesOutOfImportedProject() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("build-workspace-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let firmware = source.appendingPathComponent("firmware/sticks3", isDirectory: true)
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: firmware, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("build"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("source".utf8).write(to: firmware.appendingPathComponent("main.cpp"))
        try Data("old build".utf8).write(to: source.appendingPathComponent("build/firmware.bin"))
        let project = SimulatorProjectReference(
            displayName: "Source", sourcePath: source.path, firmwarePath: firmware.path,
            runtimeID: nil, compatibility: .sourceNeedsAdapter, detail: "", projectFormat: .espIDF)
        let copy = try StickS3FirmwareBuildWorkspace().prepare(project: project, at: workspace)
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("firmware/sticks3/main.cpp").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("build").path))
        XCTAssertEqual(copy.firmwarePath, workspace.appendingPathComponent("firmware/sticks3").path)
        try Data("changed".utf8).write(to: workspace.appendingPathComponent("firmware/sticks3/main.cpp"))
        XCTAssertEqual(try String(contentsOf: firmware.appendingPathComponent("main.cpp"), encoding: .utf8), "source")
    }

    func testPlatformIOVirtualBoardInjectionOnlyChangesPrivateCopy() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("virtual-board-injection-\(UUID().uuidString)", isDirectory: true)
        let imported = root.appendingPathComponent("imported", isDirectory: true)
        let privateCopy = root.appendingPathComponent("private", isDirectory: true)
        let resources = root.appendingPathComponent("resources", isDirectory: true)
        try FileManager.default.createDirectory(at: imported.appendingPathComponent("src"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("""
        [env:test]
        platform = espressif32
        board_build.arduino.memory_type = qio_opi
        build_flags =
            -DARDUINO_USB_CDC_ON_BOOT=1
            -DARDUINO_USB_MODE=1
            -DBOARD_HAS_PSRAM
        """.utf8)
            .write(to: imported.appendingPathComponent("platformio.ini"))
        for filename in [
            "StickS3VirtualBoard.h", "StickS3VirtualBoard.cpp",
            "Panel_StickS3Virtual.hpp", "Panel_StickS3Virtual.cpp", "platformio_pre.py",
        ] {
            try Data(filename.utf8).write(to: resources.appendingPathComponent(filename))
        }
        let project = SimulatorProjectReference(
            displayName: "PIO", sourcePath: imported.path, firmwarePath: imported.path,
            runtimeID: nil, compatibility: .sourceNeedsAdapter, detail: "", projectFormat: .platformIO)
        let copy = try StickS3FirmwareBuildWorkspace().prepare(project: project, at: privateCopy)
        let script = try XCTUnwrap(StickS3VirtualBoardInjector().inject(
            into: copy, resourceDirectory: resources))
        XCTAssertTrue(FileManager.default.fileExists(atPath: script.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath:
            privateCopy.appendingPathComponent("src/sticks3_virtual_board.generated.cpp").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath:
            imported.appendingPathComponent(".sticks3-virtual-board").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath:
            imported.appendingPathComponent("src/sticks3_virtual_board.generated.cpp").path))
        let privateConfiguration = try String(
            contentsOf: privateCopy.appendingPathComponent("platformio.ini"), encoding: .utf8)
        XCTAssertTrue(privateConfiguration.contains("board_build.arduino.memory_type = qio_qspi"))
        XCTAssertTrue(privateConfiguration.contains("-Wl,--wrap=esp_flash_init_default_chip"))
        XCTAssertFalse(privateConfiguration.contains("ARDUINO_USB_CDC_ON_BOOT"))
        XCTAssertFalse(privateConfiguration.contains("BOARD_HAS_PSRAM"))
    }

    func testArduinoSketchBecomesPrivatePlatformIOVirtualBoardProject() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("arduino-virtual-board-\(UUID().uuidString)", isDirectory: true)
        let imported = root.appendingPathComponent("imported", isDirectory: true)
        let privateCopy = root.appendingPathComponent("private", isDirectory: true)
        let resources = root.appendingPathComponent("resources", isDirectory: true)
        try FileManager.default.createDirectory(at: imported, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("void setup() {}\nvoid loop() {}\n".utf8).write(to: imported.appendingPathComponent("Demo.ino"))
        for filename in [
            "StickS3VirtualBoard.h", "StickS3VirtualBoard.cpp",
            "Panel_StickS3Virtual.hpp", "Panel_StickS3Virtual.cpp", "platformio_pre.py",
        ] {
            try Data(filename.utf8).write(to: resources.appendingPathComponent(filename))
        }
        let project = SimulatorProjectReference(
            displayName: "Arduino", sourcePath: imported.path, firmwarePath: imported.path,
            runtimeID: nil, compatibility: .sourceNeedsAdapter, detail: "", projectFormat: .arduino)
        let copy = try StickS3FirmwareBuildWorkspace().prepare(project: project, at: privateCopy)
        _ = try StickS3VirtualBoardInjector().inject(into: copy, resourceDirectory: resources)
        let configuration = try String(contentsOf: privateCopy.appendingPathComponent("platformio.ini"), encoding: .utf8)
        XCTAssertTrue(configuration.contains("extra_scripts = pre:.sticks3-virtual-board/platformio_pre.py"))
        XCTAssertTrue(configuration.contains("toolchain-riscv32-esp@symlink://"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: privateCopy.appendingPathComponent("src/Demo.ino").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: imported.appendingPathComponent("platformio.ini").path))
    }

    func testESPIDFInjectionCreatesPrivateBridgeComponent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("espidf-virtual-board-\(UUID().uuidString)", isDirectory: true)
        let imported = root.appendingPathComponent("imported", isDirectory: true)
        let privateCopy = root.appendingPathComponent("private", isDirectory: true)
        let resources = root.appendingPathComponent("resources", isDirectory: true)
        try FileManager.default.createDirectory(at: imported, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("project(Demo)\n".utf8).write(to: imported.appendingPathComponent("CMakeLists.txt"))
        for filename in [
            "StickS3VirtualBoard.h", "StickS3VirtualBoard.cpp",
            "Panel_StickS3Virtual.hpp", "Panel_StickS3Virtual.cpp", "platformio_pre.py",
            "espidf_pre.py", "espidf_project_include.cmake",
        ] {
            try Data(filename.utf8).write(to: resources.appendingPathComponent(filename))
        }
        let project = SimulatorProjectReference(
            displayName: "IDF", sourcePath: imported.path, firmwarePath: imported.path,
            runtimeID: nil, compatibility: .sourceNeedsAdapter, detail: "", projectFormat: .espIDF)
        let copy = try StickS3FirmwareBuildWorkspace().prepare(project: project, at: privateCopy)
        let include = try XCTUnwrap(StickS3VirtualBoardInjector().inject(into: copy, resourceDirectory: resources))
        XCTAssertEqual(include.lastPathComponent, "espidf_project_include.cmake")
        XCTAssertTrue(FileManager.default.fileExists(atPath:
            privateCopy.appendingPathComponent("components/sticks3_virtual_board/CMakeLists.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath:
            imported.appendingPathComponent("components/sticks3_virtual_board").path))
    }

    func testQEMUImageResolverAssemblesPlatformIOArtifactsWithoutChangingProject() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("qemu-pio-\(UUID().uuidString)", isDirectory: true)
        let build = root.appendingPathComponent(".pio/build/m5stack-sticks3", isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var bootloader = Data(repeating: 0x00, count: 4096)
        bootloader[0] = 0xE9
        try bootloader.write(to: build.appendingPathComponent("bootloader.bin"))
        var partitions = Data(repeating: 0xFF, count: 0x1000)
        partitions[0] = 0xAA
        partitions[1] = 0x50
        try partitions.write(to: build.appendingPathComponent("partitions.bin"))
        try Data(repeating: 0x5A, count: 64 * 1024).write(to: build.appendingPathComponent("firmware.bin"))
        let project = SimulatorProjectReference(
            displayName: "PlatformIO App",
            sourcePath: root.path,
            firmwarePath: root.path,
            runtimeID: nil,
            compatibility: .sourceNeedsAdapter,
            detail: "",
            projectFormat: .platformIO
        )

        XCTAssertTrue(StickS3QEMUImageResolver().canPrepare(for: project))
        let prepared = try StickS3QEMUImageResolver().prepare(for: project, cacheDirectory: cache)
        XCTAssertEqual(try StickS3FlashImageValidator().validate(prepared), 8 * 1024 * 1024)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("qemu_flash.bin").path))
        let image = try Data(contentsOf: prepared)
        XCTAssertEqual(image[0], 0xE9)
        XCTAssertEqual(image[0x8000], 0xAA)
        XCTAssertEqual(image[0x10000], 0x5A)
    }

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
        XCTAssertEqual(reference.compatibility, .invalid)
        XCTAssertFalse(reference.compatibility.canSimulate)
        XCTAssertNil(reference.runtimeID)
        XCTAssertNil(reference.projectFormat)
        XCTAssertTrue(reference.detail.contains("只导入 StickS3 源码工程目录"))
    }

    func testSimulatorProjectInspectorRecognizesStickS3PlatformIOProject() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sticks3-platformio-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("""
        [env:m5stack-sticks3]
        platform = espressif32
        framework = arduino
        build_flags = -DBOARD_M5STICK_S3
        lib_deps = m5stack/M5Unified
        """.utf8).write(to: root.appendingPathComponent("platformio.ini"))
        try Data("#include <M5Unified.h>\nvoid setup() {}\nvoid loop() {}\n".utf8)
            .write(to: source.appendingPathComponent("main.cpp"))

        let reference = SimulatorProjectInspector().inspect(root)
        XCTAssertEqual(reference.compatibility, .sourceNeedsAdapter)
        XCTAssertEqual(reference.projectFormat, .platformIO)
        XCTAssertEqual(reference.firmwarePath, root.path)
        XCTAssertNil(reference.runtimeID)
        XCTAssertFalse(reference.compatibility.canSimulate)
        XCTAssertTrue(reference.detail.contains("PlatformIO/Arduino StickS3"))
    }

    func testSimulatorProjectInspectorFindsSingleNestedPlatformIOProject() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sticks3-project-kit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("little-buddy", isDirectory: true)
        let source = project.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("""
        [env:m5stack-sticks3]
        platform = espressif32
        board = esp32-s3-devkitc-1
        framework = arduino
        build_flags = -DBOARD_M5STICK_S3
        lib_deps = m5stack/M5Unified
        """.utf8).write(to: project.appendingPathComponent("platformio.ini"))
        try Data("#include <M5Unified.h>\nvoid setup() {}\nvoid loop() {}\n".utf8)
            .write(to: source.appendingPathComponent("main.cpp"))

        let reference = SimulatorProjectInspector().inspect(root)
        XCTAssertEqual(reference.compatibility, .sourceNeedsAdapter)
        XCTAssertEqual(reference.projectFormat, .platformIO)
        XCTAssertTrue(reference.sourcePath.hasSuffix("/little-buddy"))
        XCTAssertEqual(reference.firmwarePath, reference.sourcePath)
        XCTAssertEqual(reference.displayName, "little-buddy")
    }

    func testSimulatorProjectInspectorRecognizesStickS3ArduinoSketch() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sticks3-arduino-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("#include <M5Unified.h>\nvoid setup() {}\nvoid loop() {}\n".utf8)
            .write(to: root.appendingPathComponent("Demo.ino"))

        let reference = SimulatorProjectInspector().inspect(root)
        XCTAssertEqual(reference.compatibility, .sourceNeedsAdapter)
        XCTAssertEqual(reference.projectFormat, .arduino)
        XCTAssertEqual(reference.firmwarePath, root.path)
        XCTAssertNil(reference.runtimeID)
    }

    func testSimulatorProjectInspectorRecognizesConventionalESPIDFMainComponent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("standard-idf-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let main = root.appendingPathComponent("main", isDirectory: true)
        try FileManager.default.createDirectory(at: main, withIntermediateDirectories: true)
        try "cmake_minimum_required(VERSION 3.16)\ninclude($ENV{IDF_PATH}/tools/cmake/project.cmake)\nproject(review)\n"
            .write(to: root.appendingPathComponent("CMakeLists.txt"), atomically: true, encoding: .utf8)
        try "extern \"C\" void app_main(void) {}\n"
            .write(to: main.appendingPathComponent("main.cpp"), atomically: true, encoding: .utf8)

        let reference = SimulatorProjectInspector().inspect(root)

        XCTAssertEqual(reference.compatibility, .sourceNeedsAdapter)
        XCTAssertEqual(reference.projectFormat, .espIDF)
        XCTAssertEqual(reference.firmwarePath, root.path)
        XCTAssertTrue(reference.detail.contains("点击“开始模拟”"))
        XCTAssertTrue(reference.detail.contains("原项目不会被修改"))
    }

    func testSimulatorProjectInspectorRejectsUnrelatedPlatformIOProject() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("generic-platformio-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("[env:generic]\nplatform = espressif32\nframework = arduino\n".utf8)
            .write(to: root.appendingPathComponent("platformio.ini"))
        try Data("void setup() {}\nvoid loop() {}\n".utf8)
            .write(to: source.appendingPathComponent("main.cpp"))

        let reference = SimulatorProjectInspector().inspect(root)
        XCTAssertEqual(reference.compatibility, .invalid)
        XCTAssertEqual(reference.projectFormat, .platformIO)
        XCTAssertTrue(reference.detail.contains("未确认"))
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
