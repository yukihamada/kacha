import XCTest
import CryptoKit
@testable import Kacha

// MARK: - VaultEncryption Unit Tests
// AES-256-GCM 暗号化/復号ロジックを検証する。
// Keychainを通じた実装を使うため、シミュレーター上での実行が必要。

final class VaultEncryptionTests: XCTestCase {

    // MARK: - Round-Trip

    func testEncryptDecryptRoundTrip() {
        let plaintext = "SwitchBot-Token-ABC123"
        let encrypted = VaultEncryption.encrypt(plaintext)
        let decrypted = VaultEncryption.decrypt(encrypted)
        XCTAssertEqual(decrypted, plaintext)
        print("VaultEncryption round-trip OK: \(plaintext.count) chars")
    }

    func testEmptyStringEncryption() {
        // 空文字列は暗号化せずそのまま返す（実装の後方互換フォールバックと一致）
        let encrypted = VaultEncryption.encrypt("")
        let decrypted = VaultEncryption.decrypt(encrypted)
        XCTAssertEqual(decrypted, "")
        print("VaultEncryption empty string OK")
    }

    func testLongStringEncryption() {
        let longText = String(repeating: "あいうえお", count: 500) // 2500 chars
        let encrypted = VaultEncryption.encrypt(longText)
        let decrypted = VaultEncryption.decrypt(encrypted)
        XCTAssertEqual(decrypted, longText)
        print("VaultEncryption long string OK: \(longText.count) chars")
    }

    func testJapaneseStringEncryption() {
        let japanese = "テスト用シークレットキー🔑"
        let encrypted = VaultEncryption.encrypt(japanese)
        let decrypted = VaultEncryption.decrypt(encrypted)
        XCTAssertEqual(decrypted, japanese)
        print("VaultEncryption Japanese string OK")
    }

    // MARK: - Ciphertext Properties

    func testEncryptedValueIsBase64() {
        let plaintext = "api-key-12345"
        let encrypted = VaultEncryption.encrypt(plaintext)
        // 暗号化に成功していれば平文とは異なるはず
        XCTAssertNotEqual(encrypted, plaintext)
        // Base64文字列として解釈できること
        let decoded = Data(base64Encoded: encrypted)
        XCTAssertNotNil(decoded, "Encrypted value should be valid Base64")
        // nonce(12B) + ciphertext + tag(16B) = 最低28バイト
        XCTAssertGreaterThanOrEqual(decoded?.count ?? 0, 28)
        print("VaultEncryption produces valid Base64 ciphertext")
    }

    func testSamePlaintextProducesDifferentCiphertext() {
        // AES-GCM はランダム nonce を使うため同じ平文でも異なる暗号文になる
        let plaintext = "same-input-every-time"
        let encrypted1 = VaultEncryption.encrypt(plaintext)
        let encrypted2 = VaultEncryption.encrypt(plaintext)
        // どちらも正しく復号できること
        XCTAssertEqual(VaultEncryption.decrypt(encrypted1), plaintext)
        XCTAssertEqual(VaultEncryption.decrypt(encrypted2), plaintext)
        // 暗号文自体は異なること（nonce が異なるため）
        XCTAssertNotEqual(encrypted1, encrypted2,
            "Same plaintext should produce different ciphertext due to random nonce")
        print("VaultEncryption nonce randomness confirmed")
    }

    // MARK: - Fallback Behavior

    func testInvalidCiphertextFallsBackToInput() {
        // 不正な暗号文（Base64だが AES-GCM として無効）は平文として返される
        let garbage = "aGVsbG93b3JsZA==" // "helloworld" in Base64 — not a valid GCM box
        let result = VaultEncryption.decrypt(garbage)
        XCTAssertEqual(result, garbage, "Invalid ciphertext should fall back to the input value")
        print("VaultEncryption invalid ciphertext fallback OK")
    }

    func testPlaintextFallsBackToInput() {
        // 旧データ（平文）は復号失敗してそのまま返される
        let plaintext = "plain-old-data"
        let result = VaultEncryption.decrypt(plaintext)
        XCTAssertEqual(result, plaintext, "Plaintext input should be returned as-is")
        print("VaultEncryption plaintext passthrough OK")
    }

    // MARK: - Consistency

    func testMultipleEncryptDecryptCycles() {
        let original = "cycle-test-value"
        // 複数回の暗号化→復号を繰り返しても常に元の値に戻ること
        for i in 1...5 {
            let encrypted = VaultEncryption.encrypt(original)
            let decrypted = VaultEncryption.decrypt(encrypted)
            XCTAssertEqual(decrypted, original, "Cycle \(i) should reproduce original value")
        }
        print("VaultEncryption 5-cycle consistency OK")
    }

    func testUrlStringEncryption() {
        let url = "https://api.switchbot.io/v1.1/devices?token=abc&ts=123456789"
        let encrypted = VaultEncryption.encrypt(url)
        let decrypted = VaultEncryption.decrypt(encrypted)
        XCTAssertEqual(decrypted, url)
        print("VaultEncryption URL string OK")
    }
}
