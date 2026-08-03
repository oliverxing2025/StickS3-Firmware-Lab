import Foundation

public struct SimulatorAppPartition: Equatable, Sendable {
    public var name: String
    public var subtype: String
    public var sizeBytes: Int64

    public init(name: String, subtype: String, sizeBytes: Int64) {
        self.name = name
        self.subtype = subtype
        self.sizeBytes = sizeBytes
    }
}

public struct SimulatorResourceMetrics: Equatable, Sendable {
    public var appImageBytes: Int64?
    public var appImageName: String?
    /// nil 表示未找到可验证的分区表；空数组表示分区表中没有 app 分区。
    public var appPartitions: [SimulatorAppPartition]?

    public init(appImageBytes: Int64? = nil,
                appImageName: String? = nil,
                appPartitions: [SimulatorAppPartition]? = nil) {
        self.appImageBytes = appImageBytes
        self.appImageName = appImageName
        self.appPartitions = appPartitions
    }

    public var appPartitionBytes: Int64? {
        appPartitions?.map(\.sizeBytes).max()
    }

    public var remainingAppBytes: Int64? {
        guard let appImageBytes, let appPartitionBytes else { return nil }
        return appPartitionBytes - appImageBytes
    }

    public var appUsageRatio: Double? {
        guard let appImageBytes, let appPartitionBytes, appPartitionBytes > 0 else { return nil }
        return Double(appImageBytes) / Double(appPartitionBytes)
    }

    public var appFitsPartition: Bool? {
        guard let remainingAppBytes else { return nil }
        return remainingAppBytes >= 0
    }
}

public struct SimulatorResourceInspector {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func inspect(projectRoot: URL, firmwareRoot: URL) -> SimulatorResourceMetrics {
        let partitions = appPartitions(firmwareRoot: firmwareRoot)
        let imageURL = appImage(projectRoot: projectRoot, firmwareRoot: firmwareRoot)
        let imageBytes = imageURL.flatMap { url in
            (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
        }
        return SimulatorResourceMetrics(
            appImageBytes: imageBytes,
            appImageName: imageURL?.lastPathComponent,
            appPartitions: partitions
        )
    }

    private func appPartitions(firmwareRoot: URL) -> [SimulatorAppPartition]? {
        // 构建产物中的分区表是本次构建的真实结果，优先于源码目录中的候选配置。
        let candidates = [
            firmwareRoot.appendingPathComponent("build/partition_table/partition-table.csv"),
            firmwareRoot.appendingPathComponent("partitions.csv"),
        ]
        guard let contents = candidates.lazy.compactMap({
            try? String(contentsOf: $0, encoding: .utf8)
        }).first else { return nil }

        return contents.split(whereSeparator: \.isNewline).compactMap { line -> SimulatorAppPartition? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
            let columns = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard columns.count >= 5, columns[1] == "app" else { return nil }
            guard let size = parseInteger(columns[4]) else { return nil }
            return SimulatorAppPartition(name: columns[0], subtype: columns[2], sizeBytes: size)
        }
    }

    private func parseInteger(_ value: String) -> Int64? {
        let normalized = value.lowercased()
        if normalized.hasPrefix("0x") {
            return Int64(normalized.dropFirst(2), radix: 16)
        }
        return Int64(normalized)
    }

    private func appImage(projectRoot: URL, firmwareRoot: URL) -> URL? {
        let buildRoot = firmwareRoot.appendingPathComponent("build", isDirectory: true)
        if let described = describedAppImage(in: buildRoot), fileManager.fileExists(atPath: described.path) {
            return described
        }

        let searchRoots = [
            firmwareRoot.appendingPathComponent("releases", isDirectory: true),
            projectRoot.appendingPathComponent("dist", isDirectory: true),
        ]
        var candidates: [URL] = []
        for root in searchRoots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "bin" {
                let name = url.lastPathComponent.lowercased()
                guard !name.contains("full"), !name.contains("merged"),
                      !name.contains("bootloader"), !name.contains("partition"),
                      !name.contains("ota_data") else { continue }
                candidates.append(url)
            }
        }
        return candidates.sorted { lhs, rhs in
            let lhsApp = lhs.lastPathComponent.lowercased().contains("app")
            let rhsApp = rhs.lastPathComponent.lowercased().contains("app")
            if lhsApp != rhsApp { return lhsApp }
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }.first
    }

    private func describedAppImage(in buildRoot: URL) -> URL? {
        let flasherURL = buildRoot.appendingPathComponent("flasher_args.json")
        if let data = try? Data(contentsOf: flasherURL),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let app = object["app"] as? [String: Any],
           let file = app["file"] as? String {
            return buildRoot.appendingPathComponent(file)
        }

        let descriptionURL = buildRoot.appendingPathComponent("project_description.json")
        if let data = try? Data(contentsOf: descriptionURL),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let file = object["app_bin"] as? String {
            return buildRoot.appendingPathComponent(file)
        }
        return nil
    }
}
