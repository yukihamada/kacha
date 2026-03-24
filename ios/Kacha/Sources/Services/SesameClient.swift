import Foundation

// MARK: - Sesame (CANDY HOUSE) Cloud API
// API Key & Device UUID取得:
//   1. Sesameアプリ → デバイス選択 → 歯車アイコン → UUID をコピー
//   2. https://partners.candyhouse.co/ でAPIキーを発行
// ドキュメント: https://partners.candyhouse.co/

final class SesameClient: ObservableObject {
    static let shared = SesameClient()
    private let base = "https://app.candyhouse.co/api/sesame2"

    @Published var statuses: [String: SesameStatus] = [:]   // uuid → status
    @Published var isLoading = false
    @Published var lastError: String?

    // Command codes
    enum Command: Int {
        case lock   = 82
        case unlock = 83
        case toggle = 88
    }

    func fetchStatus(uuid: String, apiKey: String) async throws -> SesameStatus {
        guard !uuid.isEmpty, !apiKey.isEmpty else { throw SesameError.missingConfig }
        var req = URLRequest(url: URL(string: "\(base)/\(uuid)")!)
        req.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.timeoutInterval = 10
        let (data, _) = try await URLSession.shared.data(for: req)
        let status = try JSONDecoder().decode(SesameStatus.self, from: data)
        await MainActor.run { self.statuses[uuid] = status }
        return status
    }

    func sendCommand(_ command: Command, uuid: String, apiKey: String, historyTag: String = "カチャ") async throws {
        guard !uuid.isEmpty, !apiKey.isEmpty else { throw SesameError.missingConfig }
        var req = URLRequest(url: URL(string: "\(base)/\(uuid)")!)
        req.httpMethod = "POST"
        req.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "cmd": command.rawValue,
            "history": historyTag
        ])
        req.timeoutInterval = 10
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SesameError.apiError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    func lock(uuid: String, apiKey: String) async throws {
        try await sendCommand(.lock, uuid: uuid, apiKey: apiKey)
        await MainActor.run {
            var s = statuses[uuid] ?? SesameStatus()
            s.isInLockRange = true; s.isInUnlockRange = false
            statuses[uuid] = s
        }
    }

    func unlock(uuid: String, apiKey: String) async throws {
        try await sendCommand(.unlock, uuid: uuid, apiKey: apiKey)
        await MainActor.run {
            var s = statuses[uuid] ?? SesameStatus()
            s.isInLockRange = false; s.isInUnlockRange = true
            statuses[uuid] = s
        }
    }

    func fetchAll(uuids: [String], apiKey: String) async {
        await MainActor.run { isLoading = true; lastError = nil }
        for uuid in uuids.filter({ !$0.isEmpty }) {
            do { _ = try await fetchStatus(uuid: uuid, apiKey: apiKey) }
            catch { await MainActor.run { lastError = error.localizedDescription } }
        }
        await MainActor.run { isLoading = false }
    }
}

struct SesameStatus: Codable {
    var batteryPercentage: Int?
    var isInLockRange: Bool?
    var isInUnlockRange: Bool?
    var target: Bool?
    var position: Int?

    var isLocked: Bool { isInLockRange ?? true }
    var batteryLevel: Int { batteryPercentage ?? 0 }
}

enum SesameError: Error, LocalizedError {
    case missingConfig
    case apiError(Int)
    var errorDescription: String? {
        switch self {
        case .missingConfig: return "APIキーまたはデバイスUUIDが未設定です"
        case .apiError(let code): return "Sesame APIエラー: HTTP \(code)"
        }
    }
}
