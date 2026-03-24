import Foundation

@MainActor
class HueClient: ObservableObject {
    static let shared = HueClient()

    @Published var lights: [HueLight] = []
    @Published var bridgeIP: String = ""
    @Published var isLoading = false
    @Published var lastError: String?

    struct HueLight: Codable, Identifiable {
        let id: String
        var name: String
        var on: Bool
        var bri: Int      // 1-254
        var ct: Int?      // Mired: 153 (cool 6500K) - 500 (warm 2000K)
        var hue: Int?
        var sat: Int?

        var brightnessPercent: Int {
            Int(Double(bri) / 254.0 * 100)
        }

        var colorTempKelvin: Int? {
            guard let ct = ct, ct > 0 else { return nil }
            return 1_000_000 / ct
        }
    }

    func discoverBridge() async -> String? {
        guard let url = URL(string: "https://discovery.meethue.com") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let ip = array.first?["internalipaddress"] as? String else { return nil }
        return ip
    }

    func register(bridgeIP: String) async throws -> String {
        let url = URL(string: "http://\(bridgeIP)/api")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["devicetype": "kacha#iphone"])
        let (data, _) = try await URLSession.shared.data(for: request)
        struct RegResponse: Codable {
            struct Success: Codable { let username: String }
            struct HueError: Codable { let type: Int; let description: String }
            let success: Success?
            let error: HueError?
        }
        let responses = try JSONDecoder().decode([RegResponse].self, from: data)
        if let username = responses.first?.success?.username {
            return username
        }
        if let errDesc = responses.first?.error?.description {
            throw NSError(domain: "HueClient", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: errDesc])
        }
        throw URLError(.userAuthenticationRequired)
    }

    func fetchLights(bridgeIP: String, username: String) async throws -> [HueLight] {
        isLoading = true
        defer { isLoading = false }

        let url = URL(string: "http://\(bridgeIP)/api/\(username)/lights")!
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
            return []
        }
        let result = dict.compactMap { (id, value) -> HueLight? in
            guard let state = value["state"] as? [String: Any],
                  let name = value["name"] as? String else { return nil }
            return HueLight(
                id: id,
                name: name,
                on: state["on"] as? Bool ?? false,
                bri: state["bri"] as? Int ?? 127,
                ct: state["ct"] as? Int,
                hue: state["hue"] as? Int,
                sat: state["sat"] as? Int
            )
        }.sorted { (Int($0.id) ?? 0) < (Int($1.id) ?? 0) }
        self.lights = result
        return result
    }

    func setState(
        lightId: String,
        on: Bool? = nil,
        bri: Int? = nil,
        ct: Int? = nil,
        bridgeIP: String,
        username: String
    ) async throws {
        let url = URL(string: "http://\(bridgeIP)/api/\(username)/lights/\(lightId)/state")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [:]
        if let on = on { body["on"] = on }
        if let bri = bri { body["bri"] = min(254, max(1, bri)) }
        if let ct = ct { body["ct"] = min(500, max(153, ct)) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await URLSession.shared.data(for: request)
    }

    // MARK: - Preset Scenes

    /// ウェルカムシーン: 温かい白色、明るめ
    func welcomeScene(bridgeIP: String, username: String) async throws {
        for light in lights {
            try await setState(lightId: light.id, on: true, bri: 220, ct: 370,
                               bridgeIP: bridgeIP, username: username)
        }
    }

    /// 就寝シーン: 暗めの暖色
    func nightScene(bridgeIP: String, username: String) async throws {
        for light in lights {
            try await setState(lightId: light.id, on: true, bri: 60, ct: 450,
                               bridgeIP: bridgeIP, username: username)
        }
    }

    /// 全消灯
    func allOff(bridgeIP: String, username: String) async throws {
        for light in lights {
            try await setState(lightId: light.id, on: false,
                               bridgeIP: bridgeIP, username: username)
        }
    }

    /// 輝度をパーセント(0-100)でセット
    func setBrightnessPercent(_ percent: Int, lightId: String, bridgeIP: String, username: String) async throws {
        let bri = max(1, min(254, Int(Double(percent) / 100.0 * 254)))
        try await setState(lightId: lightId, bri: bri, bridgeIP: bridgeIP, username: username)
    }
}
