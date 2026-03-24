import Foundation

// MARK: - NukiClient
// Nuki Web API v1 — スマートロック施錠・解錠

@MainActor
class NukiClient: ObservableObject {
    static let shared = NukiClient()

    private let base = "https://api.nuki.io"

    struct SmartLock: Codable, Identifiable {
        let smartlockId: Int
        let name: String
        let state: LockState?
        var id: Int { smartlockId }

        struct LockState: Codable {
            let state: Int      // 1=locked, 3=unlocked
            let batteryCritical: Bool?
            var isLocked: Bool { state == 1 }
        }
    }

    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil, token: String) async throws -> Data {
        var req = URLRequest(url: URL(string: "\(base)\(path)")!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { req.httpBody = try? JSONSerialization.data(withJSONObject: body) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse).map({ $0.statusCode < 300 }) ?? false else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    func fetchSmartLocks(token: String) async throws -> [SmartLock] {
        let data = try await request("/smartlock", token: token)
        return try JSONDecoder().decode([SmartLock].self, from: data)
    }

    func lock(smartlockId: Int, token: String) async throws {
        _ = try await request("/smartlock/\(smartlockId)/action/lock", method: "POST", token: token)
    }

    func unlock(smartlockId: Int, token: String) async throws {
        _ = try await request("/smartlock/\(smartlockId)/action/unlock", method: "POST", token: token)
    }
}
