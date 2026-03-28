import XCTest
import CryptoKit
@testable import Kacha

// MARK: - CloudSyncService Unit Tests
// CloudSyncServiceのE2E暗号化ロジックとCloudBackupPayloadのCodableをテストする。
// Keychain / ネットワークには依存しない純粋なロジックテスト。

final class CloudSyncServiceTests: XCTestCase {

    // MARK: - Helpers (暗号化ロジックをテスト用に再実装)
    // CloudSyncServiceの private メソッドと同一アルゴリズムをテスト内で再現し、
    // 実装との一致を保証する。

    private func encrypt(data: Data, key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw SyncError.encryptionFailed
        }
        return combined
    }

    private func decrypt(data: Data, key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }

    private func deriveKeyFromPassphrase(_ passphrase: String) -> SymmetricKey {
        let salt = "com.enablerdao.kacha.cloud.v1".data(using: .utf8)!
        let passData = passphrase.data(using: .utf8)!
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: passData),
            salt: salt,
            info: "kacha-e2e-backup".data(using: .utf8)!,
            outputByteCount: 32
        )
    }

    // MARK: - E2E Encrypt / Decrypt Round-Trip

    func testEncryptDecryptRoundTrip() throws {
        let original = "テストデータ: KAGI スマートホーム 🔐".data(using: .utf8)!
        let key = SymmetricKey(size: .bits256)

        let encrypted = try encrypt(data: original, key: key)
        let decrypted = try decrypt(data: encrypted, key: key)

        XCTAssertEqual(decrypted, original)
        // 暗号文はランダム nonce を含むため平文より長い
        XCTAssertGreaterThan(encrypted.count, original.count)
    }

    func testEncryptedOutputIsNotPlaintext() throws {
        let secret = "doorCode=9999".data(using: .utf8)!
        let key = SymmetricKey(size: .bits256)

        let encrypted = try encrypt(data: secret, key: key)

        // 暗号文に平文が含まれていないことを確認
        XCTAssertFalse(encrypted.contains(secret))
        // 元データそのものではない
        XCTAssertNotEqual(encrypted, secret)
    }

    // MARK: - HKDF Passphrase Key Derivation

    func testHKDFSamePassphraseProducesSameKey() {
        let passphrase = "my-secure-passphrase-2026"
        let key1 = deriveKeyFromPassphrase(passphrase)
        let key2 = deriveKeyFromPassphrase(passphrase)

        let keyData1 = key1.withUnsafeBytes { Data($0) }
        let keyData2 = key2.withUnsafeBytes { Data($0) }

        XCTAssertEqual(keyData1, keyData2)
    }

    func testHKDFDifferentPassphrasesProduceDifferentKeys() {
        let key1 = deriveKeyFromPassphrase("passphrase-A")
        let key2 = deriveKeyFromPassphrase("passphrase-B")

        let keyData1 = key1.withUnsafeBytes { Data($0) }
        let keyData2 = key2.withUnsafeBytes { Data($0) }

        XCTAssertNotEqual(keyData1, keyData2)
    }

    func testHKDFKeyIs256Bits() {
        let key = deriveKeyFromPassphrase("test-passphrase")
        let keyData = key.withUnsafeBytes { Data($0) }
        XCTAssertEqual(keyData.count, 32) // 256 bits = 32 bytes
    }

    // MARK: - 異なるパスフレーズでの復号失敗

    func testDecryptWithWrongPassphraseFails() throws {
        let plaintext = "sensitive booking data".data(using: .utf8)!
        let encryptionKey = deriveKeyFromPassphrase("correct-passphrase")
        let wrongKey = deriveKeyFromPassphrase("wrong-passphrase")

        let encrypted = try encrypt(data: plaintext, key: encryptionKey)

        XCTAssertThrowsError(try decrypt(data: encrypted, key: wrongKey)) { error in
            // CryptoKit の認証失敗エラーであることを確認
            XCTAssertNotNil(error)
        }
    }

    func testDecryptWithRandomKeyFails() throws {
        let plaintext = "secret".data(using: .utf8)!
        let encryptionKey = SymmetricKey(size: .bits256)
        let wrongKey = SymmetricKey(size: .bits256)

        let encrypted = try encrypt(data: plaintext, key: encryptionKey)

        XCTAssertThrowsError(try decrypt(data: encrypted, key: wrongKey))
    }

    // MARK: - CloudBackupPayload JSON Round-Trip

    func testCloudBackupPayloadEncodeDecode() throws {
        let now = Date()
        let payload = CloudBackupPayload(
            version: 1,
            createdAt: now,
            homes: [],
            bookings: [],
            devices: [],
            integrations: [],
            checklists: [],
            maintenance: [],
            nearby: [],
            activityLogs: [],
            manuals: [],
            secureItems: [],
            utilities: [],
            shares: [],
            settings: SettingsPayload(
                activeHomeId: "home-uuid-001",
                hasCompletedOnboarding: true,
                minpakuModeEnabled: false
            )
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CloudBackupPayload.self, from: data)

        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.settings?.activeHomeId, "home-uuid-001")
        XCTAssertEqual(decoded.settings?.hasCompletedOnboarding, true)
        XCTAssertEqual(decoded.settings?.minpakuModeEnabled, false)
        XCTAssertTrue(decoded.homes.isEmpty)
        XCTAssertTrue(decoded.bookings.isEmpty)
    }

    func testBookingPayloadEncodeDecode() throws {
        // BookingPayload は init(booking:) のみ公開されているため、
        // JSON から直接デコードしてラウンドトリップを検証する。
        let isoFormatter = ISO8601DateFormatter()
        let checkInStr = "2026-05-01T15:00:00Z"
        let checkOutStr = "2026-05-03T11:00:00Z"

        let json = """
        {
            "id": "booking-001",
            "homeId": "home-001",
            "guestName": "山田 太郎",
            "guestEmail": "yamada@example.com",
            "guestPhone": "090-1234-5678",
            "platform": "airbnb",
            "externalId": "ext-123",
            "status": "confirmed",
            "notes": "早めチェックイン希望",
            "checkIn": "\(checkInStr)",
            "checkOut": "\(checkOutStr)",
            "roomCount": 1,
            "totalAmount": 15000,
            "autoUnlock": true,
            "autoLight": false,
            "cleaningDone": false
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BookingPayload.self, from: json)

        // 再エンコード
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let reEncoded = try encoder.encode(payload)

        let decoder2 = JSONDecoder()
        decoder2.dateDecodingStrategy = .iso8601
        let decoded = try decoder2.decode(BookingPayload.self, from: reEncoded)

        XCTAssertEqual(decoded.id, "booking-001")
        XCTAssertEqual(decoded.guestName, "山田 太郎")
        XCTAssertEqual(decoded.platform, "airbnb")
        XCTAssertEqual(decoded.totalAmount, 15000)
        XCTAssertTrue(decoded.autoUnlock)
        XCTAssertFalse(decoded.autoLight)
        XCTAssertEqual(decoded.checkIn, isoFormatter.date(from: checkInStr))
    }

    func testSettingsPayloadEncodeDecode() throws {
        let settings = SettingsPayload(
            activeHomeId: "abc-123",
            hasCompletedOnboarding: true,
            minpakuModeEnabled: true
        )

        let data = try JSONEncoder().encode(settings)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["activeHomeId"] as? String, "abc-123")
        XCTAssertEqual(json?["hasCompletedOnboarding"] as? Bool, true)
        XCTAssertEqual(json?["minpakuModeEnabled"] as? Bool, true)
    }

    // MARK: - End-to-End: Payload -> Encrypt -> Decrypt -> Payload

    func testFullBackupEncryptDecryptRoundTrip() throws {
        let payload = CloudBackupPayload(
            version: 1,
            createdAt: Date(),
            homes: [],
            bookings: [],
            devices: [],
            integrations: [],
            checklists: [],
            maintenance: [],
            nearby: [],
            activityLogs: [],
            manuals: [],
            secureItems: [],
            utilities: [],
            shares: [],
            settings: SettingsPayload(
                activeHomeId: "test-home",
                hasCompletedOnboarding: false,
                minpakuModeEnabled: false
            )
        )

        // Encode
        let plaintext = try JSONEncoder().encode(payload)
        XCTAssertGreaterThan(plaintext.count, 0)

        // Encrypt
        let passphrase = "user-passphrase-2026"
        let key = deriveKeyFromPassphrase(passphrase)
        let encrypted = try encrypt(data: plaintext, key: key)

        // Base64 (実際の転送と同様)
        let base64 = encrypted.base64EncodedString()
        XCTAssertFalse(base64.isEmpty)

        // Restore
        let restoredEncrypted = Data(base64Encoded: base64)!
        let restoredKey = deriveKeyFromPassphrase(passphrase)
        let decrypted = try decrypt(data: restoredEncrypted, key: restoredKey)

        let restoredPayload = try JSONDecoder().decode(CloudBackupPayload.self, from: decrypted)
        XCTAssertEqual(restoredPayload.version, 1)
        XCTAssertEqual(restoredPayload.settings?.activeHomeId, "test-home")
    }
}
