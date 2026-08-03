import Foundation

public enum StickS3QEMUState: String, Codable, Sendable {
    case unavailable
    case stopped
    case starting
    case running
    case failed

    public var isActive: Bool { self == .starting || self == .running }
}

public struct StickS3QEMUInstallation: Equatable, Sendable {
    public let executableURL: URL

    public init(executableURL: URL) {
        self.executableURL = executableURL.standardizedFileURL
    }
}

public struct StickS3QEMUDiscovery {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleResourceURL: URL? = Bundle.main.resourceURL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> StickS3QEMUInstallation? {
        var candidates: [URL] = []
        if let explicit = environment["STICKS3_QEMU_PATH"], !explicit.isEmpty {
            candidates.append(URL(fileURLWithPath: explicit))
        }
        if let bundleResourceURL {
            candidates.append(bundleResourceURL.appendingPathComponent("Emulation/bin/qemu-system-xtensa"))
            candidates.append(bundleResourceURL.appendingPathComponent("Emulation/qemu-system-xtensa"))
        }

        // Development fallback only. Public builds package QEMU inside the app.
        let toolRoot = homeDirectory.appendingPathComponent(".espressif/tools/qemu-xtensa", isDirectory: true)
        if let versions = try? fileManager.contentsOfDirectory(
            at: toolRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for version in versions.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                candidates.append(version.appendingPathComponent("qemu/bin/qemu-system-xtensa"))
                candidates.append(version.appendingPathComponent("bin/qemu-system-xtensa"))
            }
        }

        if let path = environment["PATH"] {
            for directory in path.split(separator: ":") {
                candidates.append(URL(fileURLWithPath: String(directory), isDirectory: true)
                    .appendingPathComponent("qemu-system-xtensa"))
            }
        }

        return candidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) })
            .map(StickS3QEMUInstallation.init)
    }
}

public enum StickS3FlashImageError: LocalizedError, Equatable {
    case missing
    case tooSmall(Int)
    case unsupportedSize(Int)
    case invalidBootloader
    case partitionTableMissing
    case noBuildArtifacts
    case invalidBuildManifest
    case segmentOutsideFlash(String)
    case overlappingSegments

    public var errorDescription: String? {
        switch self {
        case .missing: return "未找到固件镜像。"
        case .tooSmall: return "所选 .bin 不是完整 Flash 镜像；仅应用镜像不能直接启动。"
        case .unsupportedSize(let bytes): return "Flash 镜像大小不受支持（\(bytes) 字节）。"
        case .invalidBootloader: return "Flash 起始位置没有有效的 ESP32-S3 启动镜像。"
        case .partitionTableMissing: return "Flash 镜像中未找到 ESP 分区表。"
        case .noBuildArtifacts: return "尚未找到可合并的启动程序、分区表和应用构建产物。"
        case .invalidBuildManifest: return "构建清单格式无效，无法确定固件写入偏移。"
        case .segmentOutsideFlash(let name): return "构建产物超出 Flash 范围：\(name)"
        case .overlappingSegments: return "构建产物的 Flash 地址互相重叠。"
        }
    }
}

public struct StickS3FlashImageValidator: Sendable {
    public static let supportedSizes = [2, 4, 8, 16, 32].map { $0 * 1024 * 1024 }

    public init() {}

    @discardableResult
    public func validate(_ imageURL: URL) throws -> Int {
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            throw StickS3FlashImageError.missing
        }
        let handle = try FileHandle(forReadingFrom: imageURL)
        defer { try? handle.close() }
        let size = Int(try handle.seekToEnd())
        guard size >= Self.supportedSizes[0] else { throw StickS3FlashImageError.tooSmall(size) }
        guard Self.supportedSizes.contains(size) else { throw StickS3FlashImageError.unsupportedSize(size) }

        try handle.seek(toOffset: 0)
        guard try handle.read(upToCount: 1)?.first == 0xE9 else {
            throw StickS3FlashImageError.invalidBootloader
        }

        // ESP-IDF defaults to 0x8000. Searching aligned locations also accepts projects
        // that intentionally move the partition table without accepting an app-only image.
        var foundPartitionTable = false
        for offset in stride(from: 0x8000, through: min(size - 2, 0x100000), by: 0x1000) {
            try handle.seek(toOffset: UInt64(offset))
            if try handle.read(upToCount: 2) == Data([0xAA, 0x50]) {
                foundPartitionTable = true
                break
            }
        }
        guard foundPartitionTable else { throw StickS3FlashImageError.partitionTableMissing }
        return size
    }
}

public struct StickS3FlashSegment: Equatable, Sendable {
    public let offset: Int
    public let fileURL: URL

    public init(offset: Int, fileURL: URL) {
        self.offset = offset
        self.fileURL = fileURL
    }
}

public struct StickS3FlashImageAssembler: Sendable {
    public init() {}

    public func assemble(segments: [StickS3FlashSegment], flashSize: Int, outputURL: URL) throws {
        guard StickS3FlashImageValidator.supportedSizes.contains(flashSize) else {
            throw StickS3FlashImageError.unsupportedSize(flashSize)
        }
        let prepared = try segments.map { segment -> (StickS3FlashSegment, Data) in
            let data = try Data(contentsOf: segment.fileURL, options: [.mappedIfSafe])
            guard segment.offset >= 0, segment.offset + data.count <= flashSize else {
                throw StickS3FlashImageError.segmentOutsideFlash(segment.fileURL.lastPathComponent)
            }
            return (segment, data)
        }.sorted { $0.0.offset < $1.0.offset }
        guard !prepared.isEmpty else { throw StickS3FlashImageError.noBuildArtifacts }
        for pair in zip(prepared, prepared.dropFirst()) {
            guard pair.0.0.offset + pair.0.1.count <= pair.1.0.offset else {
                throw StickS3FlashImageError.overlappingSegments
            }
        }

        var image = Data(repeating: 0xFF, count: flashSize)
        for (segment, data) in prepared {
            image.replaceSubrange(segment.offset..<(segment.offset + data.count), with: data)
        }
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try image.write(to: outputURL, options: .atomic)
        try StickS3FlashImageValidator().validate(outputURL)
    }
}

public enum StickS3QEMUCommandError: LocalizedError, Equatable {
    case executableMissing

    public var errorDescription: String? { "未找到可执行的 ESP32-S3 QEMU。" }
}

public struct StickS3QEMUCommand: Equatable, Sendable {
    public let executableURL: URL
    public let arguments: [String]
    public let environment: [String: String]
}

public struct StickS3QEMUCommandBuilder {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func makeCommand(
        installation: StickS3QEMUInstallation,
        flashImageURL: URL,
        inheritedEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> StickS3QEMUCommand {
        guard fileManager.isExecutableFile(atPath: installation.executableURL.path) else {
            throw StickS3QEMUCommandError.executableMissing
        }
        _ = try StickS3FlashImageValidator().validate(flashImageURL)
        let allowedEnvironmentKeys = ["HOME", "TMPDIR", "LANG", "LC_ALL"]
        var environment = Dictionary(uniqueKeysWithValues: allowedEnvironmentKeys.compactMap { key in
            inheritedEnvironment[key].map { (key, $0) }
        })
        let virtualRoot = installation.executableURL
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("root", isDirectory: true)
        if fileManager.fileExists(atPath: virtualRoot.path) {
            environment["DYLD_ROOT_PATH"] = virtualRoot.path
        }
        let runtimeDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("StickS3Simulator", isDirectory: true)
        try fileManager.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
        let efuseURL = runtimeDirectory.appendingPathComponent("qemu-esp32s3-efuse.bin")
        if !fileManager.fileExists(atPath: efuseURL.path) {
            var efuse = Data(repeating: 0, count: 1024)
            efuse[0x26] = 0x0C // Espressif's default ESP32-S3 QEMU revision bits.
            try efuse.write(to: efuseURL, options: .atomic)
        }
        return StickS3QEMUCommand(
            executableURL: installation.executableURL,
            arguments: [
                "-M", "esp32s3",
                "-m", "32M",
                "-drive", "file=\(flashImageURL.path),if=mtd,format=raw",
                "-drive", "file=\(efuseURL.path),if=none,format=raw,id=efuse",
                "-global", "driver=nvram.esp32s3.efuse,property=drive,value=efuse",
                "-global", "driver=timer.esp32s3.timg,property=wdt_disable,value=true",
                "-nographic",
            ],
            environment: environment
        )
    }
}

public struct StickS3QEMUImageResolver {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func canPrepare(for project: SimulatorProjectReference) -> Bool {
        return buildSegments(for: project) != nil
    }

    /// Assembles an internal Flash image from an adapted source build.
    public func prepare(for project: SimulatorProjectReference, cacheDirectory: URL) throws -> URL {
        guard let build = buildSegments(for: project) else {
            throw StickS3FlashImageError.noBuildArtifacts
        }
        let output = cacheDirectory.appendingPathComponent("prepared-flash.bin")
        try StickS3FlashImageAssembler().assemble(
            segments: build.segments,
            flashSize: build.flashSize,
            outputURL: output
        )
        return output
    }

    private func buildSegments(for project: SimulatorProjectReference) -> (segments: [StickS3FlashSegment], flashSize: Int)? {
        let roots = [URL(fileURLWithPath: project.sourcePath), project.firmwarePath.map(URL.init(fileURLWithPath:))]
            .compactMap { $0 }
        for root in roots {
            let buildRoot = root.appendingPathComponent("build", isDirectory: true)
            if let manifest = segmentsFromESPManifest(buildRoot.appendingPathComponent("flasher_args.json"), buildRoot: buildRoot) {
                return manifest
            }
            let pioRoot = root.appendingPathComponent(".pio/build", isDirectory: true)
            if let environments = try? fileManager.contentsOfDirectory(at: pioRoot, includingPropertiesForKeys: [.isDirectoryKey]) {
                for environment in environments.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    if let standard = standardSegments(in: environment) { return standard }
                }
            }
            if let standard = standardSegments(in: buildRoot) { return standard }
        }
        return nil
    }

    private func segmentsFromESPManifest(_ manifestURL: URL, buildRoot: URL) -> (segments: [StickS3FlashSegment], flashSize: Int)? {
        guard let data = try? Data(contentsOf: manifestURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var segments: [StickS3FlashSegment] = []
        if let files = json["flash_files"] as? [String: String] {
            for (offsetText, path) in files {
                guard let offset = parseOffset(offsetText) else { continue }
                segments.append(StickS3FlashSegment(offset: offset, fileURL: buildRoot.appendingPathComponent(path)))
            }
        }
        collectManifestSegments(json, buildRoot: buildRoot, into: &segments)
        segments = Array(Dictionary(grouping: segments, by: { "\($0.offset):\($0.fileURL.path)" }).compactMap(\.value.first))
        guard segments.count >= 3,
              segments.allSatisfy({ fileManager.fileExists(atPath: $0.fileURL.path) }) else { return nil }
        let sizeText = (json["flash_settings"] as? [String: Any])?["flash_size"] as? String
        return (segments, parseFlashSize(sizeText) ?? 8 * 1024 * 1024)
    }

    private func collectManifestSegments(_ value: Any, buildRoot: URL, into result: inout [StickS3FlashSegment]) {
        if let object = value as? [String: Any] {
            if let offsetValue = object["offset"], let file = object["file"] as? String,
               let offset = parseOffset(String(describing: offsetValue)) {
                result.append(StickS3FlashSegment(offset: offset, fileURL: buildRoot.appendingPathComponent(file)))
            }
            for child in object.values { collectManifestSegments(child, buildRoot: buildRoot, into: &result) }
        } else if let array = value as? [Any] {
            for child in array { collectManifestSegments(child, buildRoot: buildRoot, into: &result) }
        }
    }

    private func standardSegments(in directory: URL) -> (segments: [StickS3FlashSegment], flashSize: Int)? {
        guard fileManager.fileExists(atPath: directory.path) else { return nil }
        let entries = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
        func exactOrSuffix(_ exact: String, _ suffix: String) -> URL? {
            entries.first { $0.lastPathComponent == exact } ?? entries.first { $0.lastPathComponent.hasSuffix(suffix) }
        }
        guard let bootloader = exactOrSuffix("bootloader.bin", ".bootloader.bin"),
              let partitions = exactOrSuffix("partitions.bin", ".partitions.bin"),
              let app = entries.first(where: { $0.lastPathComponent == "firmware.bin" })
                ?? entries.first(where: { $0.lastPathComponent.hasSuffix(".ino.bin") }) else { return nil }
        var segments = [
            StickS3FlashSegment(offset: 0x0000, fileURL: bootloader),
            StickS3FlashSegment(offset: 0x8000, fileURL: partitions),
            StickS3FlashSegment(offset: 0x10000, fileURL: app),
        ]
        if let bootApp = exactOrSuffix("boot_app0.bin", ".boot_app0.bin") {
            segments.append(StickS3FlashSegment(offset: 0xE000, fileURL: bootApp))
        }
        return (segments, 8 * 1024 * 1024)
    }

    private func parseOffset(_ value: String) -> Int? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("0x") ? Int(normalized.dropFirst(2), radix: 16) : Int(normalized)
    }

    private func parseFlashSize(_ value: String?) -> Int? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalized.hasSuffix("MB"), let amount = Int(normalized.dropLast(2)) { return amount * 1024 * 1024 }
        return Int(normalized)
    }
}
