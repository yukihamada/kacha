import Foundation

// MARK: - NatureRemoClient
// Nature Remo Cloud API v1 — IRリモコン信号送信・デバイス取得

@MainActor
class NatureRemoClient: ObservableObject {
    static let shared = NatureRemoClient()

    private let base = "https://api.nature.global/1"

    struct RemoDevice: Codable, Identifiable {
        let id: String
        let name: String
        let firmwareVersion: String?
    }

    struct Appliance: Codable, Identifiable {
        let id: String
        let device: RemoDevice
        let model: ApplianceModel?
        let nickname: String
        let type: String        // AC, TV, LIGHT, IR, etc.
        let image: String

        struct ApplianceModel: Codable { let name: String? }
    }

    struct Signal: Codable, Identifiable {
        let id: String
        let name: String
        let image: String
    }

    private func request(_ path: String, method: String = "GET", body: [String: String]? = nil, token: String) async throws -> Data {
        var req = URLRequest(url: URL(string: "\(base)\(path)")!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    func fetchDevices(token: String) async throws -> [RemoDevice] {
        let data = try await request("/devices", token: token)
        return try JSONDecoder().decode([RemoDevice].self, from: data)
    }

    func fetchAppliances(token: String) async throws -> [Appliance] {
        let data = try await request("/appliances", token: token)
        return try JSONDecoder().decode([Appliance].self, from: data)
    }

    func fetchSignals(applianceId: String, token: String) async throws -> [Signal] {
        let data = try await request("/appliances/\(applianceId)/signals", token: token)
        return try JSONDecoder().decode([Signal].self, from: data)
    }

    func sendSignal(signalId: String, token: String) async throws {
        _ = try await request("/signals/\(signalId)/send", method: "POST", token: token)
    }
}
