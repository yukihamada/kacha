import Foundation

/// ChatWeb Vault Sync — KAGI AppのSecureItemをChatWebサーバーと同期
/// APIキーカテゴリのアイテムを暗号化したままサーバーに送信
/// ChatWebがClaude CLIセッション時にこれらのキーを取得して使用
enum ChatWebVaultSync {

    static let serverURL = "https://kagi-server.fly.dev/api/v1/vault"

    // MARK: - Public API

    /// 指定したSecureItemをChatWebサーバーに同期
    static func syncItem(_ item: SecureItemData, sessionToken: String) async throws {
        let url = URL(string: "\(serverURL)/store")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "session_token": sessionToken,
            "key_name": item.keyName,
            "encrypted_value": item.encryptedValue,
            "category": item.category
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SyncError.serverError
        }
    }

    /// 全APIキーアイテムをChatWebに同期
    static func syncAllAPIKeys(items: [SecureItemData], sessionToken: String) async throws -> Int {
        var synced = 0
        for item in items where item.category == "apikey" {
            try await syncItem(item, sessionToken: sessionToken)
            synced += 1
        }
        return synced
    }

    /// ChatWebサーバーからキー一覧を取得
    static func listKeys(sessionToken: String) async throws -> [VaultKeyInfo] {
        let url = URL(string: "\(serverURL)/list")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["session_token": sessionToken])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SyncError.serverError
        }
        let result = try JSONDecoder().decode(VaultListResponse.self, from: data)
        return result.items
    }

    /// ChatWebサーバーからキーを削除
    static func deleteKey(name: String, sessionToken: String) async throws {
        let url = URL(string: "\(serverURL)/delete")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "session_token": sessionToken,
            "key_name": name
        ])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SyncError.serverError
        }
    }

    enum SyncError: Error, LocalizedError {
        case serverError
        var errorDescription: String? { "ChatWebサーバーとの同期に失敗しました" }
    }
}

// MARK: - Data Transfer Objects

struct SecureItemData {
    let keyName: String
    let encryptedValue: String
    let category: String
}

struct VaultKeyInfo: Codable {
    let key_name: String
    let encrypted_value: String
    let category: String
    let updated_at: String
}

struct VaultListResponse: Codable {
    let items: [VaultKeyInfo]
}
