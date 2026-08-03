import Foundation

/// 开源版不假定本机已经存在任何私有凭据。
/// Bridge Token 只能由启动环境显式提供，不读取钥匙串，不写入配置。
enum BridgeCredentialStore {
    static func loadToken(projectRoot: String?) -> String {
        if let token = ProcessInfo.processInfo.environment["VIBE_STICK_BRIDGE_TOKEN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            return token
        }
        guard let projectRoot,
              let contents = try? String(
                contentsOfFile: URL(fileURLWithPath: projectRoot)
                    .appendingPathComponent(".env").path,
                encoding: .utf8
              ) else { return "" }
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
        return ""
    }
}
