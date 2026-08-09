import Foundation

struct HostServiceDiscoveryRecord: Codable, Sendable {
    let schemaVersion: Int
    let serviceIdentity: String
    let protocolVersion: String
    let instanceID: String
    let pid: Int32
    let baseURL: String
    let healthURL: String
    let legacyPorts: [Int]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case serviceIdentity = "service_identity"
        case protocolVersion = "protocol_version"
        case instanceID = "instance_id"
        case pid
        case baseURL = "base_url"
        case healthURL = "health_url"
        case legacyPorts = "legacy_ports"
    }
}

struct HostServiceDiscovery: Sendable {
    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("StickS3 Firmware Lab/Host Services", isDirectory: true)
    }

    func resolve(_ original: URL, expectedIdentity: String? = nil,
                 session: URLSession) async -> URL? {
        guard HostNetworkProxy.loopbackHosts.contains(original.host?.lowercased() ?? "") else {
            return nil
        }
        let port = original.port ?? (original.scheme?.lowercased() == "https" ? 443 : 80)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []
        let decoder = JSONDecoder()
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let record = try? decoder.decode(HostServiceDiscoveryRecord.self, from: data),
                  record.schemaVersion == 1, record.legacyPorts.contains(port),
                  expectedIdentity == nil || record.serviceIdentity == expectedIdentity,
                  let base = URL(string: record.baseURL),
                  HostNetworkProxy.loopbackHosts.contains(base.host?.lowercased() ?? ""),
                  await validatedBase(for: base, expectedIdentity: record.serviceIdentity,
                                      session: session) != nil else { continue }
            var target = URLComponents(url: original, resolvingAgainstBaseURL: false)
            let replacement = URLComponents(url: base, resolvingAgainstBaseURL: false)
            target?.scheme = replacement?.scheme
            target?.host = replacement?.host
            target?.port = replacement?.port
            if let resolved = target?.url { return resolved }
        }
        if await validatedBase(for: original, expectedIdentity: expectedIdentity,
                               session: session) != nil {
            return original
        }
        return nil
    }

    private func validatedBase(for base: URL, expectedIdentity: String?,
                               session: URLSession) async -> String? {
        guard let health = URL(string: "/health", relativeTo: base)?.absoluteURL else { return nil }
        var request = URLRequest(url: health)
        request.timeoutInterval = 1.5
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let identity = (json["service_identity"] as? String)
                ?? (json["bridge_name"] as? String),
              expectedIdentity == nil || identity == expectedIdentity else { return nil }
        return identity
    }
}
