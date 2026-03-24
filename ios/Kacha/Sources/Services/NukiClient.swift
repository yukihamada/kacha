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

    // MARK: - Activity Log

    struct LogEntry: Codable, Identifiable {
        let id: String
        let smartlockId: Int
        let action: Int          // 1=unlock, 2=lock, 3=unlatch, 5=lock'n'go
        let trigger: Int         // 0=system, 1=manual, 2=button, 3=auto, 5=app, 6=keypad
        let state: Int
        let autoUnlock: Bool?
        let date: String         // ISO 8601
        let name: String?        // user name

        var isLock: Bool { action == 2 }
        var isUnlock: Bool { action == 1 || action == 3 || action == 5 }
        var actionLabel: String {
            if isLock { return "施錠" }
            if isUnlock { return "解錠" }
            return "操作(\(action))"
        }
        var triggerLabel: String {
            switch trigger {
            case 0: return "システム"
            case 1: return "手動"
            case 2: return "ボタン"
            case 3: return "オートロック"
            case 5: return "アプリ"
            case 6: return "キーパッド"
            default: return "不明(\(trigger))"
            }
        }
        var actor: String { name ?? triggerLabel }
        var timestamp: Date? {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: date) ?? ISO8601DateFormatter().date(from: date)
        }
    }

    func fetchLogs(smartlockId: Int, token: String, limit: Int = 20) async throws -> [LogEntry] {
        let data = try await request("/smartlock/\(smartlockId)/log?limit=\(limit)", token: token)
        return try JSONDecoder().decode([LogEntry].self, from: data)
    }
}
