import CryptoKit
import Foundation

public enum SimulatorSourceFingerprintError: Error, LocalizedError {
    case missingFile(String)

    public var errorDescription: String? {
        switch self {
        case .missingFile(let path): return "缺少模拟适配所需源码：\(path)"
        }
    }
}

public enum SimulatorSourceFingerprint {
    public static func relativeFiles(for runtime: SimulatorRuntimeID) -> [String] {
        switch runtime {
        case .codex:
            return ["generated/vibe_stick_ui_assets.c", "generated/vibe_stick_ui_assets.h", "src/main.c"]
        case .hourglass, .hourglassLiquid:
            return ["include/hourglass_physics.h", "src/hourglass_physics.c", "src/main.c"]
        case .breakout:
            return [
                "include/BreakoutGame.h", "include/GameConfig.h", "include/GameRenderer.h",
                "src/BreakoutGame.cpp", "src/GameRenderer.cpp",
            ]
        }
    }

    public static func calculate(runtime: SimulatorRuntimeID, firmwareRoot: URL) throws -> String {
        var hasher = SHA256()
        for relativePath in relativeFiles(for: runtime).sorted() {
            let url = firmwareRoot.appendingPathComponent(relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw SimulatorSourceFingerprintError.missingFile(relativePath)
            }
            hasher.update(data: Data(relativePath.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: try Data(contentsOf: url, options: .mappedIfSafe))
            hasher.update(data: Data([0]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
