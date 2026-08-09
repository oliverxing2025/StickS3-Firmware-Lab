import Foundation
import SimulatorSupport

enum HostNetworkState: Equatable {
    case idle
    case requesting(host: String)
    case connected(host: String, updatedAt: Date)
    case failed(host: String, reason: String)
}

struct HostNetworkResult: Sendable {
    let requestID: UInt32
    let statusCode: Int
    let errorCode: Int
    let body: Data
    let host: String
}

struct HostNetworkProxy: Sendable {
    static let maximumResponseBytes = 65_000
    static let loopbackHosts: Set<String> = ["127.0.0.1", "localhost", "::1"]

    func perform(_ request: StickS3HostNetworkRequest) async -> HostNetworkResult {
        guard let url = URL(string: request.url),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(), Self.loopbackHosts.contains(host) else {
            return .init(requestID: request.requestID, statusCode: 0,
                         errorCode: Int(URLError.unsupportedURL.rawValue), body: Data(),
                         host: urlHost(request.url))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        guard let resolvedURL = await HostServiceDiscovery().resolve(url, session: session) else {
            return .init(requestID: request.requestID, statusCode: 0,
                         errorCode: Int(URLError.cannotConnectToHost.rawValue),
                         body: Data(), host: host)
        }
        var outgoing = URLRequest(url: resolvedURL)
        outgoing.httpMethod = methodName(request.method)
        outgoing.timeoutInterval = TimeInterval(max(250, min(60_000, request.timeoutMilliseconds))) / 1000
        for line in request.headers.split(whereSeparator: \.isNewline) {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let name = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty,
                  !["host", "connection", "content-length"].contains(name.lowercased()) else { continue }
            outgoing.setValue(value, forHTTPHeaderField: name)
        }
        if !request.body.isEmpty { outgoing.httpBody = request.body }
        do {
            let (body, response) = try await session.data(for: outgoing)
            guard body.count <= Self.maximumResponseBytes else {
                return .init(requestID: request.requestID, statusCode: 0,
                             errorCode: Int(URLError.dataLengthExceedsMaximum.rawValue),
                             body: Data(), host: host)
            }
            return .init(requestID: request.requestID,
                         statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                         errorCode: 0, body: body, host: host)
        } catch let error as URLError {
            return .init(requestID: request.requestID, statusCode: 0,
                         errorCode: Int(error.code.rawValue), body: Data(), host: host)
        } catch {
            return .init(requestID: request.requestID, statusCode: 0,
                         errorCode: -1, body: Data(), host: host)
        }
    }

    private func methodName(_ method: UInt8) -> String {
        switch method {
        case 1: "POST"
        case 2: "PUT"
        case 3: "DELETE"
        case 4: "PATCH"
        default: "GET"
        }
    }

    private func urlHost(_ value: String) -> String {
        URL(string: value)?.host ?? "invalid"
    }
}
