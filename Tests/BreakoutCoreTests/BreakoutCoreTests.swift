import BreakoutCore
import CodexCore
import Foundation
import HourglassCore
import HourglassLiquidCore
@testable import SimulatorSupport
@testable import StickS3Simulator
import XCTest

final class BreakoutCoreTests: XCTestCase {
    func testHostNetworkProxyRejectsNonLoopbackURLs() async {
        let request = StickS3HostNetworkRequest(
            requestID: 7,
            method: 0,
            timeoutMilliseconds: 1_000,
            url: "https://example.com/private",
            headers: "",
            body: Data()
        )

        let result = await HostNetworkProxy().perform(request)

        XCTAssertEqual(result.requestID, 7)
        XCTAssertEqual(result.errorCode, Int(URLError.unsupportedURL.rawValue))
        XCTAssertEqual(result.statusCode, 0)
        XCTAssertTrue(result.body.isEmpty)
    }

    func testHostServiceDiscoveryPrefersValidatedDynamicEndpointOverOccupiedLegacyPort() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let record: [String: Any] = [
            "schema_version": 1,
            "service_identity": "customer-data-service",
            "protocol_version": "1",
            "instance_id": "test-instance",
            "pid": 123,
            "base_url": "http://127.0.0.1:43123",
            "health_url": "http://127.0.0.1:43123/health",
            "legacy_ports": [8765],
        ]
        try JSONSerialization.data(withJSONObject: record).write(
            to: directory.appendingPathComponent("customer.json"))

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HostDiscoveryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        HostDiscoveryURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.port, 43123)
            let body = try JSONSerialization.data(withJSONObject: [
                "service_identity": "customer-data-service"
            ])
            return (HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!, body)
        }
        defer { HostDiscoveryURLProtocol.requestHandler = nil }

        let original = try XCTUnwrap(URL(string: "http://127.0.0.1:8765/state?full=1"))
        let resolved = await HostServiceDiscovery(directory: directory).resolve(
            original, session: session)

        XCTAssertEqual(try XCTUnwrap(resolved).absoluteString,
                       "http://127.0.0.1:43123/state?full=1")
    }

    func testHostServiceDiscoveryRejectsMismatchedServiceIdentity() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let record: [String: Any] = [
            "schema_version": 1,
            "service_identity": "expected-service",
            "protocol_version": "1",
            "instance_id": "test-instance",
            "pid": 123,
            "base_url": "http://127.0.0.1:43123",
            "health_url": "http://127.0.0.1:43123/health",
            "legacy_ports": [8765],
        ]
        try JSONSerialization.data(withJSONObject: record).write(
            to: directory.appendingPathComponent("customer.json"))

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HostDiscoveryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        HostDiscoveryURLProtocol.requestHandler = { request in
            let identity = request.url?.port == 43123 ? "wrong-service" : "occupied-service"
            let body = try JSONSerialization.data(withJSONObject: ["service_identity": identity])
            return (HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!, body)
        }
        defer { HostDiscoveryURLProtocol.requestHandler = nil }

        let original = try XCTUnwrap(URL(string: "http://127.0.0.1:8765/state"))
        let resolved = await HostServiceDiscovery(directory: directory).resolve(
            original, expectedIdentity: "expected-service", session: session)

        XCTAssertNil(resolved)
    }

    func testQEMURegistryOnlyRecognizesTheExactRecordedExecutable() {
        let executable = "/Applications/StickS3 固件实验台.app/Contents/Resources/Emulation/qemu-system-xtensa"
        XCTAssertTrue(ChildProcessRegistry.isOwnedQEMUCommand(
            executable + " -M esp32s3 -serial stdio", executablePath: executable))
        XCTAssertTrue(ChildProcessRegistry.isOwnedQEMUCommand(executable, executablePath: executable))
        XCTAssertFalse(ChildProcessRegistry.isOwnedQEMUCommand(
            "/tmp/qemu-system-xtensa -M esp32s3", executablePath: executable))
        XCTAssertFalse(ChildProcessRegistry.isOwnedQEMUCommand(
            executable + "-helper", executablePath: executable))
        XCTAssertFalse(ChildProcessRegistry.isOwnedQEMUCommand(
            "/bin/sleep 30", executablePath: "/bin/sleep"))
    }

    func testQEMUFrameGateDropsRepeatedSequencesAndIdenticalPixels() {
        var gate = QEMUFrameGate()
        let first = StickS3VirtualBoardFrame(
            width: 1, height: 1, sequence: 1, rgb565: Data([0, 1]))
        XCTAssertTrue(gate.accept(first))
        XCTAssertFalse(gate.accept(first))
        XCTAssertFalse(gate.accept(.init(
            width: 1, height: 1, sequence: 2, rgb565: Data([0, 1]))))
        XCTAssertTrue(gate.accept(.init(
            width: 1, height: 1, sequence: 3, rgb565: Data([1, 0]))))
        gate.reset()
        XCTAssertTrue(gate.accept(first))
    }

    func testFirmwareBuildCacheSignatureTracksSourceAndAdapterChanges() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sticks3-build-cache-signature-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source", isDirectory: true)
        let adapter = root.appendingPathComponent("adapter", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("src"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: adapter, withIntermediateDirectories: true)
        try Data("v1".utf8).write(to: source.appendingPathComponent("src/main.c"))
        try Data("bridge-v1".utf8).write(to: adapter.appendingPathComponent("bridge.cpp"))
        let project = SimulatorProjectReference(
            displayName: "Cache Test", sourcePath: source.path, firmwarePath: source.path,
            runtimeID: nil, compatibility: .sourceNeedsAdapter, detail: "", projectFormat: .espIDF
        )

        let first = try StickS3FirmwareBuildCacheSignature.calculate(for: project, adapterDirectory: adapter)
        let same = try StickS3FirmwareBuildCacheSignature.calculate(for: project, adapterDirectory: adapter)
        XCTAssertEqual(first, same)

        try Data("v2".utf8).write(to: source.appendingPathComponent("src/main.c"))
        let sourceChanged = try StickS3FirmwareBuildCacheSignature.calculate(for: project, adapterDirectory: adapter)
        XCTAssertNotEqual(first, sourceChanged)

        try Data("bridge-v2".utf8).write(to: adapter.appendingPathComponent("bridge.cpp"))
        let adapterChanged = try StickS3FirmwareBuildCacheSignature.calculate(for: project, adapterDirectory: adapter)
        XCTAssertNotEqual(sourceChanged, adapterChanged)
    }

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
        XCTAssertEqual(
            Array(command.arguments.suffix(6)),
            ["-display", "none", "-monitor", "none", "-serial", "stdio"]
        )
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
        let state = encoder.deviceState(
            batteryPercent: 72, charging: true, soundEnabled: false, framesPerSecond: 60)
        XCTAssertEqual(state.prefix(6), Data([0x53, 0x33, 0x56, 0x44, 0x01, 0x13]))
        XCTAssertEqual(state.suffix(4), Data([72, 1, 0, 60]))
    }

    func testVirtualBoardParsesHostNetworkRequestAndEncodesResponse() throws {
        let url = Data("https://example.test/state".utf8)
        let headers = Data("Accept:application/json\n".utf8)
        let body = Data("{\"ready\":true}".utf8)
        var payload = Data()
        func append32(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { payload.append(contentsOf: $0) }
        }
        func append16(_ value: UInt16) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { payload.append(contentsOf: $0) }
        }
        append32(41)
        payload.append(1)
        append32(2500)
        append16(UInt16(url.count))
        append16(UInt16(headers.count))
        append32(UInt32(body.count))
        payload.append(url); payload.append(headers); payload.append(body)
        var packet = Data([0x53, 0x33, 0x56, 0x44, 1, 0x20])
        var length = UInt32(payload.count).littleEndian
        withUnsafeBytes(of: &length) { packet.append(contentsOf: $0) }
        packet.append(payload)

        var parser = StickS3VirtualBoardStreamParser()
        XCTAssertEqual(parser.append(packet), [.hostNetworkRequest(.init(
            requestID: 41, method: 1, timeoutMilliseconds: 2500,
            url: "https://example.test/state", headers: "Accept:application/json\n",
            body: body))])

        let response = StickS3VirtualBoardPacketEncoder().hostNetworkResponse(
            requestID: 41, statusCode: 200, errorCode: 0, body: body)
        XCTAssertEqual(response.prefix(6), Data([0x53, 0x33, 0x56, 0x44, 1, 0x21]))
        XCTAssertEqual(response.suffix(body.count), body)
    }

    func testVirtualBoardParsesSemanticAudioEvent() {
        let packet = Data([0x53, 0x33, 0x56, 0x44, 0x01, 0x03,
                           0x01, 0x00, 0x00, 0x00, 0x00])
        var parser = StickS3VirtualBoardStreamParser()
        XCTAssertEqual(parser.append(packet), [.audio(0)])
    }

    func testVirtualBoardParsesRLEFramebufferPacket() {
        var parser = StickS3VirtualBoardStreamParser()
        var payload = Data([2, 0, 2, 0, 7, 0, 0, 0])
        // 3 red RGB565 pixels followed by 1 green pixel.
        payload.append(contentsOf: [3, 0, 0x00, 0xF8, 1, 0, 0xE0, 0x07])
        var packet = Data([0x53, 0x33, 0x56, 0x44, 1, 0x04])
        var length = UInt32(payload.count).littleEndian
        withUnsafeBytes(of: &length) { packet.append(contentsOf: $0) }
        packet.append(payload)

        XCTAssertEqual(parser.append(packet), [.frame(.init(
            width: 2, height: 2, sequence: 7,
            rgb565: Data([0x00, 0xF8, 0x00, 0xF8, 0x00, 0xF8, 0xE0, 0x07])))])
    }

    func testVirtualBoardAppliesSparseFramebufferDelta() {
        var parser = StickS3VirtualBoardStreamParser()
        var fullPayload = Data([3, 0, 2, 0, 1, 0, 0, 0])
        fullPayload.append(contentsOf: [
            0, 0, 1, 0, 2, 0,
            3, 0, 4, 0, 5, 0,
        ])
        var fullPacket = Data([0x53, 0x33, 0x56, 0x44, 1, 0x02])
        var fullLength = UInt32(fullPayload.count).littleEndian
        withUnsafeBytes(of: &fullLength) { fullPacket.append(contentsOf: $0) }
        fullPacket.append(fullPayload)
        XCTAssertEqual(parser.append(fullPacket).count, 1)

        // Replace pixels 1...2 while preserving the other four pixels.
        var deltaPayload = Data([3, 0, 2, 0, 2, 0, 0, 0])
        deltaPayload.append(contentsOf: [1, 0, 2, 0, 9, 0, 8, 0])
        var deltaPacket = Data([0x53, 0x33, 0x56, 0x44, 1, 0x05])
        var deltaLength = UInt32(deltaPayload.count).littleEndian
        withUnsafeBytes(of: &deltaLength) { deltaPacket.append(contentsOf: $0) }
        deltaPacket.append(deltaPayload)

        XCTAssertEqual(parser.append(deltaPacket), [.frame(.init(
            width: 3, height: 2, sequence: 2,
            rgb565: Data([0, 0, 9, 0, 8, 0, 3, 0, 4, 0, 5, 0])))])
    }

    func testHardwareProfileMapsStableLogicalAxesWithoutFirmwareNames() {
        let mapping = StickS3VirtualBoardMotionMap()
        let report = StickS3VirtualBoardReport(
            capabilities: [.display, .buttons, .bmi270],
            logicalX: .init(.y, inverted: true), logicalY: .init(.z), logicalZ: .init(.z),
            frontButton: .init(gpio: 11), sideButton: .init(gpio: 12),
            displayRotation: .degrees0, compatibility: .verified)

        let horizontal = mapping.sensorVector(
            report: report, logicalX: 0.75, logicalY: 0, logicalZ: 1)
        XCTAssertEqual(horizontal, StickS3VirtualBoardMotionVector(x: 0, y: -0.75, z: 1))

        let vertical = mapping.sensorVector(
            report: report, logicalX: 0, logicalY: 0.75, logicalZ: 1)
        XCTAssertEqual(vertical, StickS3VirtualBoardMotionVector(x: 0, y: 0, z: 1.75))

        let generic = mapping.sensorVector(
            report: nil, logicalX: 0.2, logicalY: -0.3, logicalZ: 0.9)
        XCTAssertEqual(generic, StickS3VirtualBoardMotionVector(x: 0.2, y: -0.3, z: 0.9))
    }

    func testVirtualBoardParsesHardwareReportFromFirmwareBridge() {
        let payload = Data([0x07, 0xFE, 0x03, 0x03, 11, 12, 1, 1, 0, 0])
        var packet = Data([0x53, 0x33, 0x56, 0x44, 0x01, 0x01])
        var length = UInt32(payload.count).littleEndian
        withUnsafeBytes(of: &length) { packet.append(contentsOf: $0) }
        packet.append(payload)
        var parser = StickS3VirtualBoardStreamParser()
        let events = parser.append(packet)
        guard case .ready(let report) = events.first else { return XCTFail("missing hardware report") }
        XCTAssertEqual(report.compatibility, .verified)
        XCTAssertEqual(report.logicalX, .init(.y, inverted: true))
        XCTAssertEqual(report.frontButton, .init(gpio: 11))
    }

    func testHardwareDetectorUsesSourceSemanticsInsteadOfProjectName() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hardware-detect-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let generated = root.appendingPathComponent("managed_components/vendor", isDirectory: true)
        try FileManager.default.createDirectory(at: generated, withIntermediateDirectories: true)
        try Data(repeating: 0x20, count: 4_100_000).write(to: generated.appendingPathComponent("noise.c"))
        try Data("""
        #define PIN_BUTTON_FRONT 11
        #define PIN_BUTTON_SIDE 12
        #include <esp_lcd_panel_st7789.h>
        #include <bmi270.h>
        int battery_level(void); int battery_charging(void);
        void fruit_audio_play(void); void i2s_channel_enable(void);
        void controls(int motion_y, int motion_z) {
          int x = motion_y > 0 ? EVENT_MOTION_LEFT : EVENT_MOTION_RIGHT;
          int y = motion_z > 0 ? EVENT_MOTION_UP : EVENT_MOTION_DOWN;
          button_gpio_config_t b = {.active_level=0};
        }
        """.utf8).write(to: root.appendingPathComponent("main.c"))
        let project = SimulatorProjectReference(
            displayName: "Customer Project 42", sourcePath: root.path, firmwarePath: root.path,
            runtimeID: nil, compatibility: .sourceNeedsAdapter, detail: "", projectFormat: .espIDF)
        let profile = StickS3VirtualHardwareDetector().detect(project: project)
        XCTAssertEqual(profile.compatibility, .autoDetected)
        XCTAssertEqual(profile.logicalX, .init(.y, inverted: true))
        XCTAssertEqual(profile.logicalY, .init(.z))
        XCTAssertEqual(profile.frontButton, .init(gpio: 11, activeLow: true))
        XCTAssertEqual(profile.sideButton, .init(gpio: 12, activeLow: true))
        XCTAssertTrue(profile.capabilities.contains(.power))
        XCTAssertTrue(profile.capabilities.contains(.audio))
    }

    func testCalibratedProfileIsBoundToExactSourceFingerprint() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hardware-profile-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("main.c")
        try Data("bmi270 accel; button gpio_num_11; esp_lcd st7789;".utf8).write(to: source)
        let fingerprint = try StickS3ProjectSourceFingerprint.calculate(at: root)
        let store = StickS3HardwareProfileStore(storageURL: root.appendingPathComponent("profiles.json"))
        let calibrated = StickS3VirtualHardwareProfile(
            sourceFingerprint: fingerprint, compatibility: .verified,
            capabilities: [.display, .buttons, .bmi270], logicalX: .init(.y, inverted: true))
        try store.save(calibrated)
        XCTAssertEqual(store.load(fingerprint: fingerprint), calibrated)
        try Data("bmi270 accel changed; button gpio_num_11; esp_lcd st7789;".utf8).write(to: source)
        let changed = try StickS3ProjectSourceFingerprint.calculate(at: root)
        XCTAssertNotEqual(changed, fingerprint)
        XCTAssertNil(store.load(fingerprint: changed))
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
        let bridgeCMake = try String(contentsOf:
            privateCopy.appendingPathComponent("components/sticks3_virtual_board/CMakeLists.txt"),
            encoding: .utf8)
        XCTAssertTrue(bridgeCMake.contains("esp_lcd"))
        XCTAssertTrue(bridgeCMake.contains("esp_http_client"))
        XCTAssertFalse(FileManager.default.fileExists(atPath:
            imported.appendingPathComponent("components/sticks3_virtual_board").path))
    }

    func testESPIDFVirtualConfigDisablesPSRAMOnlyInPrivateCache() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("espidf-virtual-config-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let defaults = "CONFIG_SPIRAM=y\nCONFIG_SPIRAM_MODE_OCT=y\n"
        let active = "CONFIG_IDF_TARGET=\"esp32s3\"\nCONFIG_SPIRAM=y\nCONFIG_SPIRAM_USE_MALLOC=y\n"
        try defaults.write(to: source.appendingPathComponent("sdkconfig.defaults"), atomically: true, encoding: .utf8)
        try active.write(to: cache.appendingPathComponent("sdkconfig"), atomically: true, encoding: .utf8)

        let result = try StickS3VirtualSDKConfig.prepare(sourceDirectory: source, cacheDirectory: cache)
        let normalized = try String(contentsOf: result.sdkconfig, encoding: .utf8)
        XCTAssertTrue(normalized.contains("# CONFIG_SPIRAM is not set"))
        XCTAssertFalse(normalized.contains("CONFIG_SPIRAM=y"))
        XCTAssertTrue(normalized.contains("CONFIG_SPIRAM_USE_MALLOC=y"))
        XCTAssertEqual(try String(contentsOf: source.appendingPathComponent("sdkconfig.defaults"), encoding: .utf8), defaults)
        XCTAssertEqual(result.defaults.last?.lastPathComponent, "sdkconfig.virtual.defaults")
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
        XCTAssertTrue(model.canPerformDeviceShake)
        for project in VirtualProject.allCases {
            model.selectedProject = project
            model.restartSelectedFirmware()
            XCTAssertEqual(model.eventText, "FIRMWARE RESTARTED")
        }
        model.stop()
    }

    @MainActor
    func testDeviceShakeGesturesReturnBMI270ToOriginalPose() async {
        let model = SimulatorModel()
        model.setDevicePose(.upright)
        model.performDeviceShake(.horizontal)
        XCTAssertEqual(model.activeShakeGesture, .horizontal)
        try? await Task.sleep(for: .milliseconds(1_100))
        XCTAssertNil(model.activeShakeGesture)
        XCTAssertEqual(model.tilt, 0, accuracy: 0.001)
        XCTAssertEqual(model.tiltY, 0, accuracy: 0.001)
        XCTAssertEqual(model.tiltZ, 1, accuracy: 0.001)

        model.performDeviceShake(.vertical)
        XCTAssertEqual(model.activeShakeGesture, .vertical)
        try? await Task.sleep(for: .milliseconds(1_100))
        XCTAssertNil(model.activeShakeGesture)
        XCTAssertEqual(model.tilt, 0, accuracy: 0.001)
        XCTAssertEqual(model.tiltY, 0, accuracy: 0.001)
        XCTAssertEqual(model.tiltZ, 1, accuracy: 0.001)
        model.stop()
    }

    func testEveryFirmwareCanRestartRepeatedlyWithoutStaleContexts() {
        for iteration in 0..<25 {
            let breakout = breakout_create(135, 240)
            XCTAssertNotNil(breakout)
            breakout_update(breakout, 1.0 / 60.0, 0, UInt32(iteration * 16))
            XCTAssertNotNil(breakout_framebuffer(breakout))
            breakout_destroy(breakout)

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
        XCTAssertEqual(downloadedItem?.requiresEmbeddedReload, false)

        let updatedHourglass = SimulatorProjectReference(
            displayName: "VibeStick-Hourglass",
            sourcePath: "/workspace/VibeStick-Hourglass",
            firmwarePath: "/workspace/VibeStick-Hourglass/firmware/sticks3",
            runtimeID: .hourglass,
            compatibility: .sourceNeedsAdapter,
            detail: "reload required"
        )
        let updatedHourglassItem = composer.compose(projects: [updatedHourglass]).first
        XCTAssertEqual(updatedHourglassItem?.canSimulate, false)
        XCTAssertEqual(updatedHourglassItem?.requiresEmbeddedReload, true)
    }

    func testSimulatorRebuildOutputParserTracksRealBuildStages() {
        let parser = SimulatorRebuildOutputParser()
        XCTAssertEqual(parser.phase(for: "REBUILD-STEP:TESTS", current: .idle), .testing)
        XCTAssertEqual(parser.phase(for: "REBUILD-STEP:BUILD", current: .testing), .preparing)
        XCTAssertEqual(parser.phase(for: "[12/80] Compiling lv_font.c", current: .preparing), .compiling)
        XCTAssertEqual(parser.phase(for: "Linking StickS3Simulator", current: .compiling), .linking)
        XCTAssertEqual(parser.phase(for: "REBUILD-STEP:SIGNING", current: .linking), .signing)
        XCTAssertEqual(parser.phase(for: "error: build stopped", current: .compiling), .failed)
        XCTAssertEqual(parser.fraction(for: "[49/1671] Building C object"), 49.0 / 1671.0)
        XCTAssertEqual(parser.fraction(for: "[1/10]\n[8/10] Linking"), 0.8)
        XCTAssertNil(parser.fraction(for: "Waiting for firmware scheduler"))
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
        XCTAssertTrue(updated.detail.contains("重新载入固件"))
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

private final class HostDiscoveryURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler:
        ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
