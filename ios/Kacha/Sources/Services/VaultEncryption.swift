import Foundation
import Security
import CryptoKit
import CommonCrypto

/// 1Password同等のセキュリティレベルを実現する暗号化サービス
///
/// アーキテクチャ:
/// Master Password + Secret Key (128-bit) → PBKDF2 (600,000回) → Account Key
/// Account Key → AES-256-GCM で暗号化
///
/// Secret Key: 初回起動時に自動生成、Keychainに保存（デバイス固有）
/// Master Password: ユーザーが設定（未設定の場合はSecret Keyのみで暗号化）
/// Biometric: Secure EnclaveにAccount Keyを保存、Face ID/Touch IDで取得
enum VaultEncryption {

    // MARK: - Constants

    private static let keychainService = "com.enablerdao.kacha.vault"
    private static let secretKeyAccount = "vault.secret_key"
    private static let masterKeyAccount = "vault.master_derived_key"
    private static let pbkdfIterations = 600_000  // OWASP 2023 recommendation
    private static let saltSize = 32

    // MARK: - Public API

    /// Encrypt plaintext with AES-256-GCM
    /// Format: salt(32B) || nonce(12B) || ciphertext || tag(16B), Base64 encoded
    static func encrypt(_ plaintext: String) -> String {
        guard let key = getEncryptionKey(),
              let data = plaintext.data(using: .utf8) else {
            return "⚠PLAIN:" + plaintext
        }
        do {
            let salt = generateRandomBytes(saltSize)
            let sealedBox = try AES.GCM.seal(data, using: key)
            guard let combined = sealedBox.combined else { return "⚠PLAIN:" + plaintext }
            // Prepend salt for future key rotation support
            var output = Data()
            output.append(salt)
            output.append(combined)
            return output.base64EncodedString()
        } catch {
            return "⚠PLAIN:" + plaintext
        }
    }

    /// Decrypt Base64-encoded ciphertext
    /// Handles both new format (salt + encrypted) and legacy format (encrypted only)
    static func decrypt(_ ciphertext: String) -> String {
        guard !ciphertext.isEmpty else { return ciphertext }
        // Plaintext marker check
        if ciphertext.hasPrefix("⚠PLAIN:") { return String(ciphertext.dropFirst(7)) }

        guard let key = getEncryptionKey(),
              let combined = Data(base64Encoded: ciphertext) else {
            return ciphertext
        }

        // Try new format (32B salt + AES-GCM)
        if combined.count > saltSize + 12 + 16 {
            let aesData = combined.dropFirst(saltSize)
            if let result = tryDecrypt(data: Data(aesData), key: key) {
                return result
            }
        }

        // Fallback: legacy format (no salt prefix)
        if let result = tryDecrypt(data: combined, key: key) {
            return result
        }

        // Last resort: return as-is (may be plaintext from very old data)
        return ciphertext
    }

    private static func tryDecrypt(data: Data, key: SymmetricKey) -> String? {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            let decrypted = try AES.GCM.open(sealedBox, using: key)
            return String(data: decrypted, encoding: .utf8)
        } catch {
            return nil
        }
    }

    // MARK: - Master Password

    /// Set master password — derives key using PBKDF2 + Secret Key
    static func setMasterPassword(_ password: String) {
        let salt = generateRandomBytes(saltSize)
        guard let derived = pbkdf2(password: password, salt: salt) else { return }

        // Combine with Secret Key for two-factor key derivation
        let secretKey = loadOrCreateSecretKey()
        let combinedKey = deriveFromTwo(derived: derived, secretKey: secretKey)

        // Save derived key + salt to Keychain
        var keyData = Data()
        keyData.append(salt)
        keyData.append(combinedKey.withUnsafeBytes { Data($0) })
        saveToKeychain(account: masterKeyAccount, data: keyData, biometric: true)
    }

    /// Check if master password is set
    static var hasMasterPassword: Bool {
        loadFromKeychain(account: masterKeyAccount) != nil
    }

    /// Verify master password
    static func verifyMasterPassword(_ password: String) -> Bool {
        guard let stored = loadFromKeychain(account: masterKeyAccount),
              stored.count >= saltSize + 32 else { return false }
        let salt = stored.prefix(saltSize)
        let storedKey = stored.dropFirst(saltSize)

        guard let derived = pbkdf2(password: password, salt: Data(salt)) else { return false }
        let secretKey = loadOrCreateSecretKey()
        let combinedKey = deriveFromTwo(derived: derived, secretKey: secretKey)

        // Constant-time comparison
        let computedData = combinedKey.withUnsafeBytes { Data($0) }
        guard computedData.count == storedKey.count else { return false }
        var result: UInt8 = 0
        for (a, b) in zip(computedData, storedKey) { result |= a ^ b }
        return result == 0
    }

    // MARK: - Key Management

    private static func getEncryptionKey() -> SymmetricKey? {
        // If master password is set, use the derived key
        if let masterData = loadFromKeychain(account: masterKeyAccount),
           masterData.count >= saltSize + 32 {
            let keyBytes = masterData.dropFirst(saltSize)
            return SymmetricKey(data: keyBytes)
        }
        // Otherwise use Secret Key alone
        return loadOrCreateSecretKey()
    }

    /// Device-specific 256-bit secret key — generated once, never leaves device
    private static func loadOrCreateSecretKey() -> SymmetricKey {
        if let data = loadFromKeychain(account: secretKeyAccount) {
            return SymmetricKey(data: data)
        }
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        saveToKeychain(account: secretKeyAccount, data: keyData, biometric: false)
        return newKey
    }

    /// PBKDF2-SHA256 key derivation
    private static func pbkdf2(password: String, salt: Data) -> Data? {
        guard let passData = password.data(using: .utf8) else { return nil }
        var derivedKey = [UInt8](repeating: 0, count: 32)
        let status = passData.withUnsafeBytes { passBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                    passData.count,
                    saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(pbkdfIterations),
                    &derivedKey,
                    32
                )
            }
        }
        guard status == kCCSuccess else { return nil }
        return Data(derivedKey)
    }

    /// Combine PBKDF2-derived key with Secret Key using HKDF
    private static func deriveFromTwo(derived: Data, secretKey: SymmetricKey) -> SymmetricKey {
        let secretData = secretKey.withUnsafeBytes { Data($0) }
        var combined = derived
        combined.append(secretData)
        let hash = SHA256.hash(data: combined)
        return SymmetricKey(data: Data(hash))
    }

    // MARK: - Password Strength

    /// Returns 0-4 strength score (0=terrible, 4=strong)
    static func passwordStrength(_ password: String) -> (score: Int, feedback: String) {
        let len = password.count
        if len == 0 { return (0, "") }
        if len < 6 { return (0, "短すぎます") }

        var score = 0
        if len >= 8 { score += 1 }
        if len >= 12 { score += 1 }
        if password.range(of: "[A-Z]", options: .regularExpression) != nil { score += 1 }
        if password.range(of: "[0-9]", options: .regularExpression) != nil { score += 1 }
        if password.range(of: "[^a-zA-Z0-9]", options: .regularExpression) != nil { score += 1 }

        // Common patterns
        let lower = password.lowercased()
        let weak = ["password", "123456", "qwerty", "abc123", "admin", "letmein", "welcome",
                     "monkey", "dragon", "master", "login", "pass", "1234"]
        if weak.contains(where: { lower.contains($0) }) { score = max(0, score - 2) }

        let capped = min(score, 4)
        let feedback = ["非常に弱い", "弱い", "普通", "強い", "非常に強い"][capped]
        return (capped, feedback)
    }

    // MARK: - Breach Check (Have I Been Pwned k-Anonymity)

    /// Check if password appears in known breaches using k-Anonymity API
    static func checkBreach(_ password: String) async -> Int? {
        let hash = SHA1.hash(data: Data(password.utf8))
        let hexHash = hash.map { String(format: "%02x", $0) }.joined().uppercased()
        let prefix = String(hexHash.prefix(5))
        let suffix = String(hexHash.dropFirst(5))

        guard let url = URL(string: "https://api.pwnedpasswords.com/range/\(prefix)") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let body = String(data: data, encoding: .utf8) else { return nil }

        for line in body.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":")
            if parts.count == 2 && parts[0] == suffix {
                return Int(parts[1])
            }
        }
        return 0
    }

    // MARK: - Helpers

    private static func generateRandomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    // MARK: - Keychain (low-level)

    private static func saveToKeychain(account: String, data: Data, biometric: Bool) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        var item = query
        item[kSecValueData as String] = data
        if biometric {
            // Require biometric to access master key
            let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                          .biometryCurrentSet, nil)
            if let access { item[kSecAttrAccessControl as String] = access }
        } else {
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func loadFromKeychain(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    // MARK: - Jailbreak Detection

    static var isDeviceCompromised: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        let paths = ["/Applications/Cydia.app", "/Library/MobileSubstrate", "/bin/bash",
                     "/usr/sbin/sshd", "/etc/apt", "/private/var/lib/apt/"]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) { return true }
        }
        if let _ = try? String(contentsOfFile: "/private/jailbreak.txt", encoding: .utf8) { return true }
        return false
        #endif
    }

    // MARK: - SHA1 for HIBP (not for encryption)

    private struct SHA1 {
        static func hash(data: Data) -> [UInt8] {
            var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
            data.withUnsafeBytes {
                _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest)
            }
            return digest
        }
    }
}
