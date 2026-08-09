import Foundation

/// Bridge Token 可来自启动环境、已导入工程或用户安装的本机 Bridge 配置。
/// 只读取回环服务所需的现有配置，不读取钥匙串、不显示也不写回凭据。
enum BridgeCredentialStore {
    static func loadToken(
        projectRoot: String?,
        applicationSupportURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        if let token = environment["VIBE_STICK_BRIDGE_TOKEN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            return token
        }
        var candidates: [URL] = []
        if let projectRoot {
            candidates.append(URL(fileURLWithPath: projectRoot).appendingPathComponent(".env"))
        }
        let support = applicationSupportURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        candidates.append(support.appendingPathComponent("VibeStick/.env"))
        for candidate in candidates {
            if let token = token(in: candidate), !token.isEmpty { return token }
        }
        return ""
    }

    private static func token(in url: URL) -> String? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("export ") {
                line.removeFirst("export ".count)
            }
            guard !line.hasPrefix("#"),
                  let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            guard key == "VIBE_STICK_BRIDGE_TOKEN" else { continue }
            var value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)
            if value.count >= 2,
               (value.hasPrefix("\"") && value.hasSuffix("\"")
                || value.hasPrefix("'") && value.hasSuffix("'")) {
                value.removeFirst()
                value.removeLast()
            }
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}
