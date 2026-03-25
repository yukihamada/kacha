import Foundation
import CryptoKit

// MARK: - E2E Encrypted Share Client
// サーバーには暗号化blobのみ保存。復号キーはURLフラグメントに入り、サーバーに送られない。

struct ShareClient {
    static let baseURL = "https://kacha.pasha.run"

    // MARK: - Create Share (encrypt + upload)

    static func createShare(
        data: HomeShareData,
        validFrom: Date?,
        expiresAt: Date?,
        ownerToken: String
    ) async throws -> (token: String, encryptionKey: String) {
        // 1. Generate random 256-bit key
        let symmetricKey = SymmetricKey(size: .bits256)
        let keyData = symmetricKey.withUnsafeBytes { Data($0) }
        let keyBase64 = keyData.base64EncodedString()

        // 2. Encrypt HomeShareData with AES-256-GCM
        let plaintext = try JSONEncoder().encode(data)
        let sealedBox = try AES.GCM.seal(plaintext, using: symmetricKey)
        guard let combined = sealedBox.combined else { throw ShareError.uploadFailed }
        let encryptedBase64 = combined.base64EncodedString()

        // 3. Upload to server
        guard let url = URL(string: "\(baseURL)/api/v1/shares") else { throw ShareError.uploadFailed }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let iso = ISO8601DateFormatter()
        var body: [String: Any] = [
            "encrypted_data": encryptedBase64,
            "owner_token": ownerToken,
        ]
        if let from = validFrom { body["valid_from"] = iso.string(from: from) }
        if let until = expiresAt { body["expires_at"] = iso.string(from: until) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
            throw ShareError.uploadFailed
        }

        struct Response: Codable { let token: String }
        let result = try JSONDecoder().decode(Response.self, from: responseData)

        return (token: result.token, encryptionKey: keyBase64)
    }

    // MARK: - Fetch & Decrypt Share

    static func fetchShare(token: String, encryptionKey: String) async throws -> HomeShareData {
        guard let url = URL(string: "\(baseURL)/api/v1/shares/\(token)") else { throw ShareError.networkError }
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let http = response as? HTTPURLResponse else {
            throw ShareError.networkError
        }
        switch http.statusCode {
        case 200: break
        case 403: throw ShareError.notYetValid
        case 410: throw ShareError.expired
        case 404: throw ShareError.notFound
        default:  throw ShareError.networkError
        }

        struct Response: Codable { let encrypted_data: String }
        let result = try JSONDecoder().decode(Response.self, from: data)

        // Decrypt
        guard let combinedData = Data(base64Encoded: result.encrypted_data),
              let keyData = Data(base64Encoded: encryptionKey) else {
            throw ShareError.decryptionFailed
        }

        let symmetricKey = SymmetricKey(data: keyData)
        let sealedBox = try AES.GCM.SealedBox(combined: combinedData)
        let plaintext = try AES.GCM.open(sealedBox, using: symmetricKey)
        return try JSONDecoder().decode(HomeShareData.self, from: plaintext)
    }

    // MARK: - Revoke Share

    static func revokeShare(token: String, ownerToken: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/v1/shares/\(token)") else { throw ShareError.revokeFailed }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["owner_token": ownerToken])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ShareError.revokeFailed
        }
    }
}

enum ShareError: Error, LocalizedError {
    case uploadFailed, networkError, notYetValid, expired, notFound, decryptionFailed, revokeFailed

    var errorDescription: String? {
        switch self {
        case .uploadFailed:     return "シェアの作成に失敗しました"
        case .networkError:     return "ネットワークエラー"
        case .notYetValid:      return "このリンクはまだ有効期間前です"
        case .expired:          return "このリンクは期限切れです"
        case .notFound:         return "シェアが見つかりません"
        case .decryptionFailed: return "データの復号に失敗しました"
        case .revokeFailed:     return "取り消しに失敗しました"
        }
    }
}
