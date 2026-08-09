// swift-tools-version: 6.2
import PackageDescription
import Foundation

let environment = ProcessInfo.processInfo.environment
let selectedRuntime = environment["SIMULATOR_FIRMWARE_RUNTIME"]
let selectedFirmwareRoot = environment["SIMULATOR_FIRMWARE_ROOT"].map {
    URL(fileURLWithPath: $0).standardizedFileURL.path
}

func sourceDefinition(_ name: String, _ relativePath: String, runtime: String) -> CSetting? {
    guard selectedRuntime == runtime, let root = selectedFirmwareRoot else { return nil }
    let path = URL(fileURLWithPath: relativePath, relativeTo: URL(fileURLWithPath: root, isDirectory: true))
        .standardizedFileURL.path
    return .define(name, to: "\"\(path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\"")
}

func definitions(runtime: String, files: [(String, String)]) -> [CSetting] {
    files.compactMap { sourceDefinition($0.0, $0.1, runtime: runtime) }
}

func cxxDefinitions(runtime: String, files: [(String, String)]) -> [CXXSetting] {
    guard selectedRuntime == runtime, let root = selectedFirmwareRoot else { return [] }
    return files.map { name, relativePath in
        let path = URL(fileURLWithPath: relativePath, relativeTo: URL(fileURLWithPath: root, isDirectory: true))
            .standardizedFileURL.path
        let escaped = path.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return .define(name, to: "\"\(escaped)\"")
    }
}

let package = Package(
    name: "StickS3FirmwareLab",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "StickS3Simulator", targets: ["StickS3Simulator"]),
        .executable(name: "FirmwareFingerprintTool", targets: ["FirmwareFingerprintTool"]),
    ],
    targets: [
        .target(
            name: "SimulatorSupport",
            path: "Sources/SimulatorSupport"
        ),
        .executableTarget(
            name: "FirmwareFingerprintTool",
            dependencies: ["SimulatorSupport"],
            path: "Sources/FirmwareFingerprintTool"
        ),
        .target(
            name: "BreakoutCore",
            path: "Sources/BreakoutCore",
            publicHeadersPath: "include",
            cxxSettings: [.unsafeFlags(["-std=c++17"])] + cxxDefinitions(runtime: "breakout", files: [
                ("BREAKOUT_FIRMWARE_GAME_SOURCE", "src/BreakoutGame.cpp"),
                ("BREAKOUT_FIRMWARE_RENDERER_SOURCE", "src/GameRenderer.cpp"),
                ("BREAKOUT_FIRMWARE_GAME_HEADER", "include/BreakoutGame.h"),
                ("BREAKOUT_FIRMWARE_CONFIG_HEADER", "include/GameConfig.h"),
                ("BREAKOUT_FIRMWARE_RENDERER_HEADER", "include/GameRenderer.h"),
            ])
        ),
        .target(
            name: "LVGLHost",
            path: "Sources/LVGLHost",
            publicHeadersPath: "include",
            cSettings: [.define("LV_CONF_INCLUDE_SIMPLE")]
        ),
        .target(
            name: "HourglassCore",
            dependencies: ["LVGLHost"],
            path: "Sources/HourglassCore",
            publicHeadersPath: "include",
            cSettings: definitions(runtime: "hourglass", files: [
                ("HOURGLASS_FIRMWARE_MAIN", "src/main.c"),
                ("HOURGLASS_FIRMWARE_PHYSICS", "src/hourglass_physics.c"),
                ("HOURGLASS_FIRMWARE_PHYSICS_HEADER", "include/hourglass_physics.h"),
            ])
        ),
        .target(
            name: "HourglassLiquidCore",
            dependencies: ["LVGLHost"],
            path: "Sources/HourglassLiquidCore",
            publicHeadersPath: "include",
            cSettings: definitions(runtime: "hourglassLiquid", files: [
                ("LIQUID_FIRMWARE_MAIN", "src/main.c"),
                ("LIQUID_FIRMWARE_PHYSICS", "src/hourglass_physics.c"),
                ("LIQUID_FIRMWARE_PHYSICS_HEADER", "include/hourglass_physics.h"),
            ])
        ),
        .target(
            name: "CodexCore",
            dependencies: ["LVGLHost"],
            path: "Sources/CodexCore",
            publicHeadersPath: "include",
            cSettings: definitions(runtime: "codex", files: [
                ("CODEX_FIRMWARE_MAIN", "src/main.c"),
                ("CODEX_FIRMWARE_ASSETS", "generated/vibe_stick_ui_assets.c"),
                ("CODEX_FIRMWARE_ASSETS_HEADER", "generated/vibe_stick_ui_assets.h"),
            ])
        ),
        .executableTarget(
            name: "StickS3Simulator",
            dependencies: ["SimulatorSupport", "BreakoutCore", "HourglassCore", "HourglassLiquidCore", "CodexCore"],
            path: "Sources/StickS3Simulator",
            exclude: ["Resources"],
            swiftSettings: [.unsafeFlags(["-strict-concurrency=minimal"])]
        ),
        .testTarget(
            name: "BreakoutCoreTests",
            dependencies: ["SimulatorSupport", "BreakoutCore", "HourglassCore", "HourglassLiquidCore", "CodexCore", "StickS3Simulator"],
            path: "Tests/BreakoutCoreTests"
        ),
    ],
    cxxLanguageStandard: .cxx17
)
