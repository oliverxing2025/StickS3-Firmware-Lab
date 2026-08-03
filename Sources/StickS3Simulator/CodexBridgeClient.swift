import Foundation

/// 与真机使用同一套 VibeStick HTTP 协议。Token 只保存在内存中。
struct CodexBridgeClient {
    let stateURL: String
    let token: String

    private var baseURL: URL? {
        guard var parts = URLComponents(string: stateURL) else { return nil }
        parts.path = ""
        parts.query = nil
        parts.fragment = nil
        return parts.url
    }

    func getState() async throws -> [String: Any] {
        try await request(path: "/state", method: "GET")
    }

    func postEvent(_ event: String) async throws -> [String: Any] {
        try await request(path: "/event", method: "POST", json: [
            "event": event,
            "source": "sticks3-simulator",
        ])
    }

    func refreshQuota() async throws -> [String: Any] {
        try await request(path: "/quota/refresh", method: "POST", json: [:])
    }

    func startRecording() async throws -> [String: Any] {
        // 桌面模拟器没有 StickS3 的 PDM 麦克风，Bridge 会启用 Mac 麦克风。
        try await request(path: "/recording/start", method: "POST", json: [
            "event": "button_long_start",
            "source": "sticks3-simulator",
        ])
    }

    func stopRecording() async throws -> [String: Any] {
        try await request(path: "/recording/stop", method: "POST", json: [
            "event": "button_long_stop",
            "source": "sticks3-simulator",
            "paste": true,
        ])
    }

    private func request(path: String, method: String,
                         json: [String: Any]? = nil) async throws -> [String: Any] {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("vibestick", forHTTPHeaderField: "X-Vibe-Stick-Firmware-Name")
        let appVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.1.0"
        request.setValue("\(appVersion)-simulator",
                         forHTTPHeaderField: "X-Vibe-Stick-Firmware-Version")
        request.setValue("HTTP", forHTTPHeaderField: "X-Vibe-Stick-Firmware-Transport")
        if !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-Vibe-Stick-Token")
        }
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        return object
    }
}
