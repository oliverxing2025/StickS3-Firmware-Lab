import Foundation

public enum StickS3FirmwareBuildTool: String, Codable, Sendable {
    case platformIO
    case arduinoCLI
    case espIDF

    public var title: String {
        switch self {
        case .platformIO: return "PlatformIO"
        case .arduinoCLI: return "Arduino CLI"
        case .espIDF: return "ESP-IDF"
        }
    }
}

public struct StickS3FirmwareToolInstallation: Equatable, Sendable {
    public let tool: StickS3FirmwareBuildTool
    public let executableURL: URL
    public let prefixArguments: [String]
    public let bundled: Bool

    public init(tool: StickS3FirmwareBuildTool, executableURL: URL, prefixArguments: [String] = [], bundled: Bool) {
        self.tool = tool
        self.executableURL = executableURL.standardizedFileURL
        self.prefixArguments = prefixArguments
        self.bundled = bundled
    }
}

public struct StickS3FirmwareToolDiscovery {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    public func locate(
        for format: SimulatorProjectFormat?,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleResourceURL: URL? = Bundle.main.resourceURL,
        applicationSupportURL: URL? = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first?.appendingPathComponent("Stick S3 Firmware Simulator", isDirectory: true),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        standardExecutableURLs: [URL] = [
            URL(fileURLWithPath: "/opt/homebrew/bin/platformio"),
            URL(fileURLWithPath: "/usr/local/bin/platformio"),
        ]
    ) -> StickS3FirmwareToolInstallation? {
        guard let tool = tool(for: format) else { return nil }
        var candidates: [(URL, [String], Bool)] = []
        if let explicit = environment[explicitEnvironmentKey(for: tool)], !explicit.isEmpty {
            candidates.append((URL(fileURLWithPath: explicit), [], false))
        }
        if tool == .platformIO {
            candidates += [
                (homeDirectory.appendingPathComponent(".platformio/penv/bin/platformio"), [], false),
                (homeDirectory.appendingPathComponent(".local/bin/platformio"), [], false),
            ]
            candidates += standardExecutableURLs.map { ($0, [], false) }
        }
        if tool == .espIDF {
            candidates += localESPIDFCandidates(homeDirectory: homeDirectory)
            let eimArguments = ["--do-not-track", "true", "run"]
            candidates += [
                (homeDirectory.appendingPathComponent(".local/bin/eim"), eimArguments, false),
                (URL(fileURLWithPath: "/opt/homebrew/bin/eim"), eimArguments, false),
                (URL(fileURLWithPath: "/usr/local/bin/eim"), eimArguments, false),
                (URL(fileURLWithPath: "/Applications/EIM.app/Contents/MacOS/eim"), eimArguments, false),
                (URL(fileURLWithPath: "/Applications/ESP-IDF Installation Manager.app/Contents/MacOS/eim"), eimArguments, false),
                (homeDirectory.appendingPathComponent("Applications/EIM.app/Contents/MacOS/eim"), eimArguments, false),
            ]
        }
        // Do not depend on a GUI process inheriting a shell PATH. Detect only
        // documented user locations and explicit STICKS3_*_PATH overrides.
        guard let match = candidates.first(where: { fileManager.isExecutableFile(atPath: $0.0.path) }) else { return nil }
        return StickS3FirmwareToolInstallation(tool: tool, executableURL: match.0, prefixArguments: match.1, bundled: match.2)
    }

    private func localESPIDFCandidates(homeDirectory: URL) -> [(URL, [String], Bool)] {
        let root = homeDirectory.appendingPathComponent(".espressif", isDirectory: true)
        let pythonRoot = root.appendingPathComponent("python_env", isDirectory: true)
        let idfRoots = (try? fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        let pythonEnvironments = (try? fileManager.contentsOfDirectory(
            at: pythonRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []

        var matches: [(URL, [String], Bool)] = []
        for versionRoot in idfRoots.sorted(by: { $0.lastPathComponent > $1.lastPathComponent })
            where versionRoot.lastPathComponent.hasPrefix("v") {
            let idfPy = versionRoot.appendingPathComponent("esp-idf/tools/idf.py")
            guard fileManager.fileExists(atPath: idfPy.path) else { continue }
            let components = versionRoot.lastPathComponent.dropFirst().split(separator: ".")
            guard components.count >= 2 else { continue }
            let prefix = "idf\(components[0]).\(components[1])_py"
            for environment in pythonEnvironments.sorted(by: { $0.lastPathComponent > $1.lastPathComponent })
                where environment.lastPathComponent.hasPrefix(prefix) {
                let python = environment.appendingPathComponent("bin/python")
                if fileManager.isExecutableFile(atPath: python.path) {
                    matches.append((python, [idfPy.resolvingSymlinksInPath().path], false))
                }
            }
        }
        return matches
    }

    private func tool(for format: SimulatorProjectFormat?) -> StickS3FirmwareBuildTool? {
        switch format {
        case .platformIO: return .platformIO
        // Arduino sketches use PlatformIO's Arduino framework so the
        // same private-library patch and virtual-board bridge are available.
        case .arduino: return .platformIO
        case .espIDF: return .espIDF
        case .none: return nil
        }
    }

    private func explicitEnvironmentKey(for tool: StickS3FirmwareBuildTool) -> String {
        switch tool {
        case .platformIO: return "STICKS3_PLATFORMIO_PATH"
        case .arduinoCLI: return "STICKS3_ARDUINO_CLI_PATH"
        case .espIDF: return "STICKS3_IDF_PY_PATH"
        }
    }
}

public struct StickS3FirmwareBuildPlan: Equatable, Sendable {
    public let tool: StickS3FirmwareBuildTool
    public let executableURL: URL
    public let arguments: [String]
    public let preflightArguments: [String]?
    public let environment: [String: String]
    public let workingDirectoryURL: URL
    public let artifactProject: SimulatorProjectReference
}

public struct StickS3FirmwareBuildWorkspace {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    /// Copies source into private Application Support storage so third-party build systems
    /// cannot create `.pio`, `build`, generated headers, or lock files in the imported project.
    public func prepare(project: SimulatorProjectReference, at workspaceURL: URL) throws -> SimulatorProjectReference {
        let sourceRoot = URL(fileURLWithPath: project.sourcePath, isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw StickS3FirmwareBuildPlanError.firmwarePathMissing
        }
        if fileManager.fileExists(atPath: workspaceURL.path) { try fileManager.removeItem(at: workspaceURL) }
        try fileManager.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        guard let enumerator = fileManager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { throw StickS3FirmwareBuildPlanError.firmwarePathMissing }
        let skippedDirectories: Set<String> = [".git", ".pio", ".build", "build"]
        for case let source as URL in enumerator {
            let resolvedSource = source.standardizedFileURL.resolvingSymlinksInPath()
            guard resolvedSource.path.hasPrefix(sourceRoot.path + "/") else { continue }
            let relative = String(resolvedSource.path.dropFirst(sourceRoot.path.count + 1))
            guard !relative.isEmpty else { continue }
            let values = try resolvedSource.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true, skippedDirectories.contains(resolvedSource.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            let destination = workspaceURL.appendingPathComponent(relative, isDirectory: values.isDirectory == true)
            if values.isDirectory == true {
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            } else {
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: resolvedSource, to: destination)
            }
        }

        var copy = project
        copy.sourcePath = workspaceURL.path
        if let firmwarePath = project.firmwarePath {
            let firmware = URL(fileURLWithPath: firmwarePath, isDirectory: true)
                .standardizedFileURL.resolvingSymlinksInPath()
            if firmware.path == sourceRoot.path {
                copy.firmwarePath = workspaceURL.path
            } else if firmware.path.hasPrefix(sourceRoot.path + "/") {
                let relative = String(firmware.path.dropFirst(sourceRoot.path.count + 1))
                copy.firmwarePath = workspaceURL.appendingPathComponent(relative, isDirectory: true).path
            }
        }
        return copy
    }
}

public struct StickS3VirtualBoardInjector {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    @discardableResult
    public func inject(
        into project: SimulatorProjectReference,
        resourceDirectory: URL? = Bundle.main.resourceURL?.appendingPathComponent("VirtualBoard", isDirectory: true)
    ) throws -> URL? {
        guard project.projectFormat == .platformIO || project.projectFormat == .arduino
                || project.projectFormat == .espIDF else { return nil }
        guard let firmwarePath = project.firmwarePath else {
            throw StickS3FirmwareBuildPlanError.firmwarePathMissing
        }
        let root = URL(fileURLWithPath: firmwarePath, isDirectory: true)
        if project.projectFormat == .arduino {
            try prepareArduinoSketchAsPlatformIO(at: root)
        }
        guard let resourceDirectory,
              fileManager.fileExists(atPath: resourceDirectory.appendingPathComponent("platformio_pre.py").path) else {
            throw StickS3FirmwareBuildPlanError.virtualBoardResourcesMissing
        }
        let support = root.appendingPathComponent(".sticks3-virtual-board", isDirectory: true)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        if project.projectFormat == .platformIO || project.projectFormat == .arduino {
            let unusedULP = support.appendingPathComponent("unused-riscv-ulp", isDirectory: true)
            try fileManager.createDirectory(at: unusedULP, withIntermediateDirectories: true)
            let manifest = """
            {"name":"toolchain-riscv32-esp","version":"8.4.0+2021r2-patch5",
             "description":"Placeholder because StickS3 Virtual Device does not simulate ULP programs",
             "system":"darwin_arm64"}
            """
            try manifest.write(to: unusedULP.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        }
        var resourceFiles = [
            "StickS3VirtualBoard.h", "StickS3VirtualBoard.cpp",
            "Panel_StickS3Virtual.hpp", "Panel_StickS3Virtual.cpp", "platformio_pre.py",
        ]
        if project.projectFormat == .espIDF {
            resourceFiles += ["espidf_pre.py", "espidf_project_include.cmake"]
        }
        for filename in resourceFiles {
            let source = resourceDirectory.appendingPathComponent(filename)
            let destination = support.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
            try fileManager.copyItem(at: source, to: destination)
        }
        if project.projectFormat == .espIDF {
            let component = root.appendingPathComponent("components/sticks3_virtual_board", isDirectory: true)
            try fileManager.createDirectory(at: component, withIntermediateDirectories: true)
            for filename in ["StickS3VirtualBoard.h", "StickS3VirtualBoard.cpp"] {
                let destination = component.appendingPathComponent(filename)
                if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
                try fileManager.copyItem(at: resourceDirectory.appendingPathComponent(filename), to: destination)
            }
            let cmake = """
            idf_component_register(
              SRCS "StickS3VirtualBoard.cpp"
              INCLUDE_DIRS "."
              PRIV_REQUIRES driver esp_timer freertos
            )
            """
            try cmake.write(to: component.appendingPathComponent("CMakeLists.txt"), atomically: true, encoding: .utf8)
            return support.appendingPathComponent("espidf_project_include.cmake")
        } else {
            try enablePlatformIOPrebuildScript(at: root.appendingPathComponent("platformio.ini"))
            let projectSources = root.appendingPathComponent("src", isDirectory: true)
            try fileManager.createDirectory(at: projectSources, withIntermediateDirectories: true)
            let generatedSource = projectSources.appendingPathComponent("sticks3_virtual_board.generated.cpp")
            if fileManager.fileExists(atPath: generatedSource.path) { try fileManager.removeItem(at: generatedSource) }
            try fileManager.copyItem(
                at: resourceDirectory.appendingPathComponent("StickS3VirtualBoard.cpp"),
                to: generatedSource
            )
            return support.appendingPathComponent("platformio_pre.py")
        }
    }

    private func enablePlatformIOPrebuildScript(at configuration: URL) throws {
        var lines = try String(contentsOf: configuration, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        // QEMU does not expose StickS3 USB or external octal PSRAM. Normalize
        // only the private build copy; the imported project stays untouched.
        lines = lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "-DARDUINO_USB_CDC_ON_BOOT=1"
                || trimmed == "-DARDUINO_USB_MODE=1"
                || trimmed == "-DBOARD_HAS_PSRAM" {
                return nil
            }
            if trimmed.hasPrefix("board_build.arduino.memory_type =") {
                return "board_build.arduino.memory_type = qio_qspi"
            }
            return line
        }
        func addOption(_ name: String, value: String) throws {
            let starts = lines.indices.filter {
                let trimmed = lines[$0].trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("[env:") && trimmed.hasSuffix("]")
            }
            guard !starts.isEmpty else { throw StickS3FirmwareBuildPlanError.unsupportedProject }
            for start in starts.reversed() {
                let nextHeader = (start + 1..<lines.count).first(where: {
                    let trimmed = lines[$0].trimmingCharacters(in: .whitespaces)
                    return trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
                }) ?? lines.count
                if let existing = (start + 1..<nextHeader).first(where: {
                    lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("\(name) =")
                }) {
                    lines.insert("    \(value)", at: existing + 1)
                } else {
                    lines.insert("\(name) = \(value)", at: start + 1)
                }
            }
        }
        try addOption("extra_scripts", value: "pre:.sticks3-virtual-board/platformio_pre.py")
        try addOption(
            "platform_packages",
            value: "toolchain-riscv32-esp@symlink://.sticks3-virtual-board/unused-riscv-ulp"
        )
        try addOption("build_flags", value: "-Wl,--wrap=esp_flash_init_default_chip")
        try (lines.joined(separator: "\n") + "\n").write(to: configuration, atomically: true, encoding: .utf8)
    }

    private func prepareArduinoSketchAsPlatformIO(at root: URL) throws {
        let sources = try fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ).filter { ["ino", "cpp", "c", "h", "hpp"].contains($0.pathExtension.lowercased()) }
        guard sources.contains(where: { $0.pathExtension.lowercased() == "ino" }) else {
            throw StickS3FirmwareBuildPlanError.firmwarePathMissing
        }
        let src = root.appendingPathComponent("src", isDirectory: true)
        try fileManager.createDirectory(at: src, withIntermediateDirectories: true)
        for source in sources {
            let destination = src.appendingPathComponent(source.lastPathComponent)
            if !fileManager.fileExists(atPath: destination.path) {
                try fileManager.copyItem(at: source, to: destination)
            }
        }
        let configuration = root.appendingPathComponent("platformio.ini")
        if !fileManager.fileExists(atPath: configuration.path) {
            let text = """
            [env:sticks3]
            platform = espressif32
            board = esp32-s3-devkitc-1
            framework = arduino
            lib_deps = m5stack/M5Unified
            board_upload.flash_size = 8MB
            board_build.arduino.memory_type = qio_qspi
            monitor_speed = 115200
            """
            try text.write(to: configuration, atomically: true, encoding: .utf8)
        }
    }
}

public enum StickS3FirmwareBuildPlanError: LocalizedError, Equatable {
    case unsupportedProject
    case toolUnavailable(StickS3FirmwareBuildTool)
    case firmwarePathMissing
    case virtualBoardResourcesMissing

    public var errorDescription: String? {
        switch self {
        case .unsupportedProject: return "该导入内容不能从源码自动构建。"
        case .toolUnavailable(let tool): return "尚未检测到 \(tool.title) 构建工具。"
        case .firmwarePathMissing: return "导入项目的固件目录已经失效。"
        case .virtualBoardResourcesMissing: return "应用内缺少 StickS3 屏幕与控制桥接资源。"
        }
    }
}

public struct StickS3FirmwareBuildPlanner {
    private let discovery: StickS3FirmwareToolDiscovery

    public init(discovery: StickS3FirmwareToolDiscovery = StickS3FirmwareToolDiscovery()) {
        self.discovery = discovery
    }

    public func canBuild(_ project: SimulatorProjectReference) -> Bool {
        project.projectFormat != nil && project.firmwarePath != nil
    }

    public func makePlan(for project: SimulatorProjectReference, cacheDirectory: URL) throws -> StickS3FirmwareBuildPlan {
        guard let format = project.projectFormat else {
            throw StickS3FirmwareBuildPlanError.unsupportedProject
        }
        guard let firmwarePath = project.firmwarePath else { throw StickS3FirmwareBuildPlanError.firmwarePathMissing }
        let source = URL(fileURLWithPath: firmwarePath, isDirectory: true)
        let expectedTool: StickS3FirmwareBuildTool = switch format {
        case .platformIO: .platformIO
        case .arduino: .platformIO
        case .espIDF: .espIDF
        }
        guard let installation = discovery.locate(for: format) else {
            throw StickS3FirmwareBuildPlanError.toolUnavailable(expectedTool)
        }
        let buildRoot = cacheDirectory.appendingPathComponent("build", isDirectory: true)
        let inherited = ProcessInfo.processInfo.environment
        let allowedKeys = [
            "HOME", "PATH", "TMPDIR", "LANG", "LC_ALL", "SDKROOT", "DEVELOPER_DIR",
            "IDF_PATH", "IDF_TOOLS_PATH", "IDF_PYTHON_ENV_PATH", "ESP_ROM_ELF_DIR",
        ]
        var environment = Dictionary(uniqueKeysWithValues: allowedKeys.compactMap { key in
            inherited[key].map { (key, $0) }
        })
        if format == .espIDF,
           installation.executableURL.lastPathComponent == "python",
           let idfPyPath = installation.prefixArguments.first,
           idfPyPath.hasSuffix("/tools/idf.py") {
            configureLocalIDFEnvironment(
                &environment,
                pythonURL: installation.executableURL,
                idfPyURL: URL(fileURLWithPath: idfPyPath)
            )
        }
        let arguments: [String]
        var preflightArguments: [String]?
        switch format {
        case .platformIO:
            let pioBuild = cacheDirectory.appendingPathComponent(".pio/build", isDirectory: true)
            let pioCore = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Stick S3 Firmware Simulator/Toolchains/platformio/core", isDirectory: true)
            environment["PLATFORMIO_BUILD_DIR"] = pioBuild.path
            if installation.bundled {
                environment["PLATFORMIO_CORE_DIR"] = pioCore.path
            }
            arguments = installation.prefixArguments + ["run", "--project-dir", source.path]
        case .arduino:
            let pioBuild = cacheDirectory.appendingPathComponent(".pio/build", isDirectory: true)
            let pioCore = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Stick S3 Firmware Simulator/Toolchains/platformio/core", isDirectory: true)
            environment["PLATFORMIO_BUILD_DIR"] = pioBuild.path
            if installation.bundled {
                environment["PLATFORMIO_CORE_DIR"] = pioCore.path
            }
            arguments = installation.prefixArguments + ["run", "--project-dir", source.path]
        case .espIDF:
            let sdkconfig = cacheDirectory.appendingPathComponent("sdkconfig").path
            let projectInclude = source.appendingPathComponent(
                ".sticks3-virtual-board/espidf_project_include.cmake").path
            let commonIDFArguments = [
                "-C", source.path, "-B", buildRoot.path,
                "-DSDKCONFIG=\(sdkconfig)",
                "-DIDF_TARGET=esp32s3",
            ]
            let preflightIDFArguments = commonIDFArguments + ["reconfigure"]
            let idfArguments = commonIDFArguments + [
                "-DCMAKE_PROJECT_INCLUDE=\(projectInclude)",
                "build",
            ]
            if installation.executableURL.lastPathComponent == "eim" {
                preflightArguments = installation.prefixArguments
                    + [shellCommand(executable: "idf.py", arguments: preflightIDFArguments)]
                arguments = installation.prefixArguments + [shellCommand(executable: "idf.py", arguments: idfArguments)]
            } else {
                preflightArguments = installation.prefixArguments + preflightIDFArguments
                arguments = installation.prefixArguments + idfArguments
            }
        }

        var artifactProject = project
        artifactProject.sourcePath = cacheDirectory.path
        artifactProject.firmwarePath = cacheDirectory.path
        return StickS3FirmwareBuildPlan(
            tool: installation.tool,
            executableURL: installation.executableURL,
            arguments: arguments,
            preflightArguments: preflightArguments,
            environment: environment,
            workingDirectoryURL: source,
            artifactProject: artifactProject
        )
    }

    private func shellCommand(executable: String, arguments: [String]) -> String {
        ([executable] + arguments).map(shellQuote).joined(separator: " ")
    }

    private func configureLocalIDFEnvironment(
        _ environment: inout [String: String],
        pythonURL: URL,
        idfPyURL: URL
    ) {
        let idfPath = idfPyURL.deletingLastPathComponent().deletingLastPathComponent()
        let toolsRoot = idfPath.deletingLastPathComponent().deletingLastPathComponent()
        let pythonEnvironment = pythonURL.deletingLastPathComponent().deletingLastPathComponent()
        environment["IDF_PATH"] = idfPath.path
        environment["IDF_TOOLS_PATH"] = toolsRoot.path
        environment["IDF_PYTHON_ENV_PATH"] = pythonEnvironment.path

        var searchPaths = [pythonURL.deletingLastPathComponent().path]
        let toolchainRoot = toolsRoot.appendingPathComponent("tools/xtensa-esp-elf", isDirectory: true)
        if let versions = try? FileManager.default.contentsOfDirectory(
            at: toolchainRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ), let latest = versions.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).first {
            searchPaths.append(latest.appendingPathComponent("xtensa-esp-elf/bin", isDirectory: true).path)
        }
        let romRoot = toolsRoot.appendingPathComponent("tools/esp-rom-elfs", isDirectory: true)
        if let versions = try? FileManager.default.contentsOfDirectory(
            at: romRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ), let latest = versions.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).first {
            environment["ESP_ROM_ELF_DIR"] = latest.path
        }
        searchPaths += ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        environment["PATH"] = searchPaths.joined(separator: ":")
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
