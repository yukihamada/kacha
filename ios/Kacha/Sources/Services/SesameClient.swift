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
        guard let statusURL = URL(string: "\(base)/\(uuid)") else { throw SesameError.apiError(0) }
        var req = URLRequest(url: statusURL)
        req.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.timeoutInterval = 10
        let (data, _) = try await URLSession.shared.data(for: req)
        let status = try JSONDecoder().decode(SesameStatus.self, from: data)
        await MainActor.run { self.statuses[uuid] = status }
        return status
    }

    func sendCommand(_ command: Command, uuid: String, apiKey: String, historyTag: String = "KAGI") async throws {
        guard !uuid.isEmpty, !apiKey.isEmpty else { throw SesameError.missingConfig }
        guard let cmdURL = URL(string: "\(base)/\(uuid)") else { throw SesameError.apiError(0) }
        var req = URLRequest(url: cmdURL)
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

    // MARK: - History

    struct HistoryEntry: Codable, Identifiable {
        let type: Int           // 1=BLE lock, 2=BLE unlock, 7=Web lock, 8=Web unlock
        let timeStamp: Double   // unix ms
        let historyTag: String?
        let recordID: Int

        var id: Int { recordID }

        var isLock: Bool { type == 1 || type == 7 }
        var isUnlock: Bool { type == 2 || type == 8 }
        var actionLabel: String {
            if isLock { return "施錠" }
            if isUnlock { return "解錠" }
            return "操作(\(type))"
        }
        var actor: String { historyTag ?? "不明" }
        var date: Date { Date(timeIntervalSince1970: timeStamp / 1000) }
    }

    func fetchHistory(uuid: String, apiKey: String, page: Int = 0, count: Int = 20) async throws -> [HistoryEntry] {
        guard !uuid.isEmpty, !apiKey.isEmpty else { throw SesameError.missingConfig }
        guard let histURL = URL(string: "\(base)/\(uuid)/history?page=\(page)&lg=\(count)") else { throw SesameError.apiError(0) }
        var req = URLRequest(url: histURL)
        req.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SesameError.apiError((resp as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode([HistoryEntry].self, from: data)
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
