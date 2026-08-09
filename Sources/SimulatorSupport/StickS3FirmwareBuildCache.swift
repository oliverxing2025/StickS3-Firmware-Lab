import CryptoKit
import Foundation

public enum StickS3FirmwareBuildCacheSignature {
    private static let skippedDirectories: Set<String> = [
        ".git", ".pio", ".build", "build", "managed_components",
    ]

    /// Hashes the imported source plus the app's virtual-board adapter. Build outputs and
    /// downloaded components are deliberately excluded so a valid build can be launched
    /// immediately until either the user's source or the adapter itself changes.
    public static func calculate(
        for project: SimulatorProjectReference,
        adapterDirectory: URL?,
        fileManager: FileManager = .default
    ) throws -> String {
        var hasher = SHA256()
        // Bump this whenever private build policy changes in a way that can alter
        // generated firmware without changing the imported source or adapter files.
        hasher.update(data: Data("sticks3-firmware-build-cache-v3\0".utf8))
        hasher.update(data: Data((project.projectFormat?.rawValue ?? "unknown").utf8))
        hasher.update(data: Data([0]))
        if let profile = project.hardwareProfile {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            hasher.update(data: try encoder.encode(profile))
            hasher.update(data: Data([0]))
        }

        let sourceRoot = URL(fileURLWithPath: project.sourcePath, isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        try hashTree(sourceRoot, label: "source", into: &hasher, fileManager: fileManager)
        if let adapterDirectory {
            try hashTree(
                adapterDirectory.standardizedFileURL.resolvingSymlinksInPath(),
                label: "adapter",
                into: &hasher,
                fileManager: fileManager
            )
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func hashTree(
        _ root: URL,
        label: String,
        into hasher: inout SHA256,
        fileManager: FileManager
    ) throws {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw StickS3FirmwareBuildPlanError.firmwarePathMissing
        }
        var files: [(String, URL)] = []
        for case let entry as URL in enumerator {
            let values = try entry.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values.isDirectory == true {
                if skippedDirectories.contains(entry.lastPathComponent) { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true else { continue }
            let relative = String(entry.path.dropFirst(root.path.count + 1))
            files.append((relative, entry))
        }
        for (relative, file) in files.sorted(by: { $0.0 < $1.0 }) {
            hasher.update(data: Data(label.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: Data(relative.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: try Data(contentsOf: file, options: .mappedIfSafe))
            hasher.update(data: Data([0]))
        }
    }
}
