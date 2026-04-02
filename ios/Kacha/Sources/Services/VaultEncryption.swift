import Foundation
import Security
import CryptoKit

/// AES-256-GCM 暗号化/復号サービス。
/// デバイス固有の256bit鍵を Keychain に保存し、SecureItem.encryptedValue を暗号化する。
/// 後方互換: decrypt失敗時は入力値をそのまま返す（平文で保存された旧データに対応）。
enum VaultEncryption {

    // MARK: - Constants

    private static let keychainService = "com.enablerdao.kacha.vault"
    private static let keychainAccount = "vault.key"

    // MARK: - Public API

    /// 平文を AES-256-GCM で暗号化し、Base64エンコードして返す。
    /// フォーマット: nonce(12B) || ciphertext || tag(16B) をBase64化
    static func encrypt(_ plaintext: String) -> String {
        guard let key = loadOrCreateKey(),
              let data = plaintext.data(using: .utf8) else {
            // Key creation should never fail — if it does, prefix with marker
            return "⚠PLAIN:" + plaintext
        }
        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            guard let combined = sealedBox.combined else { return "⚠PLAIN:" + plaintext }
            return combined.base64EncodedString()
        } catch {
            return "⚠PLAIN:" + plaintext
        }
    }

    /// Base64エンコードされた暗号文を復号して平文を返す。
    /// 失敗時（旧データ・平文・鍵なし）は入力値をそのまま返す。
    static func decrypt(_ ciphertext: String) -> String {
        guard !ciphertext.isEmpty,
              let key = loadOrCreateKey(),
              let combined = Data(base64Encoded: ciphertext) else {
            return ciphertext
        }
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: combined)
            let decrypted = try AES.GCM.open(sealedBox, using: key)
            return String(data: decrypted, encoding: .utf8) ?? ciphertext
        } catch {
            // 旧データ（平文）または破損データ: そのまま返す
            return ciphertext
        }
    }

    // MARK: - Key Management

    /// Keychain から鍵を取得、なければ新規生成して保存する。
    private static func loadOrCreateKey() -> SymmetricKey? {
        if let existing = loadKeyFromKeychain() {
            return existing
        }
        let newKey = SymmetricKey(size: .bits256)
        saveKeyToKeychain(newKey)
        return newKey
    }

    private static func loadKeyFromKeychain() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return SymmetricKey(data: data)
    }

    private static func saveKeyToKeychain(_ key: SymmetricKey) {
        let keyData = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        // 既存を削除してから追加
        SecItemDelete(query as CFDictionary)

        var item = query
        item[kSecValueData as String] = keyData
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}
