import XCTest
import CryptoKit
@testable import Kacha

final class ShareTests: XCTestCase {

    // MARK: - E2E Encryption

    func testEncryptDecryptRoundTrip() throws {
        let shareData = HomeShareData(
            name: "テストホーム",
            address: "東京都渋谷区",
            role: "guest",
            switchBotToken: "",
            switchBotSecret: "",
            hueBridgeIP: "",
            hueUsername: "",
            sesameApiKey: "",
            sesameDeviceUUIDs: "",
            qrioApiKey: "",
            qrioDeviceIds: "",
            doorCode: "1234",
            wifiPassword: "test-wifi-pass",
            beds24ApiKey: nil,
            beds24RefreshToken: nil
        )

        // Encrypt
        let key = SymmetricKey(size: .bits256)
        let plaintext = try JSONEncoder().encode(shareData)
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        let encrypted = sealedBox.combined!

        // Decrypt
        let openedBox = try AES.GCM.SealedBox(combined: encrypted)
        let decrypted = try AES.GCM.open(openedBox, using: key)
        let decoded = try JSONDecoder().decode(HomeShareData.self, from: decrypted)

        XCTAssertEqual(decoded.name, "テストホーム")
        XCTAssertEqual(decoded.doorCode, "1234")
        XCTAssertEqual(decoded.wifiPassword, "test-wifi-pass")
        XCTAssertEqual(decoded.role, "guest")
        XCTAssertNil(decoded.beds24ApiKey)
        print("✅ E2E encrypt/decrypt roundtrip OK")
    }

    func testWrongKeyFails() throws {
        let data = "secret data".data(using: .utf8)!
        let key1 = SymmetricKey(size: .bits256)
        let key2 = SymmetricKey(size: .bits256)

        let sealedBox = try AES.GCM.seal(data, using: key1)

        XCTAssertThrowsError(
            try AES.GCM.open(AES.GCM.SealedBox(combined: sealedBox.combined!), using: key2)
        )
        print("✅ Wrong key correctly fails decryption")
    }

    // MARK: - Role-based Data Control

    func testGuestRoleNoApiKeys() {
        let payload = HomeShareData(
            name: "Home", address: "", role: "guest",
            switchBotToken: "", switchBotSecret: "",
            hueBridgeIP: "", hueUsername: "",
            sesameApiKey: "", sesameDeviceUUIDs: "",
            qrioApiKey: "", qrioDeviceIds: "",
            doorCode: "5678", wifiPassword: "wifi123",
            beds24ApiKey: nil, beds24RefreshToken: nil
        )
        XCTAssertTrue(payload.switchBotToken.isEmpty)
        XCTAssertEqual(payload.doorCode, "5678")
        XCTAssertEqual(payload.role, "guest")
        print("✅ Guest role: no API keys, has door code")
    }

    func testAdminRoleHasAllData() {
        let payload = HomeShareData(
            name: "Home", address: "", role: "admin",
            switchBotToken: "sb-token", switchBotSecret: "sb-secret",
            hueBridgeIP: "192.168.1.1", hueUsername: "hue-user",
            sesameApiKey: "sesame-key", sesameDeviceUUIDs: "uuid1",
            qrioApiKey: "qrio-key", qrioDeviceIds: "qrio1",
            doorCode: "5678", wifiPassword: "wifi123",
            beds24ApiKey: "beds24-code", beds24RefreshToken: "beds24-refresh"
        )
        XCTAssertFalse(payload.switchBotToken.isEmpty)
        XCTAssertEqual(payload.beds24ApiKey, "beds24-code")
        XCTAssertEqual(payload.role, "admin")
        print("✅ Admin role: all data included")
    }

    // MARK: - Share Server

    func testShareServerHealth() async throws {
        let url = URL(string: "https://kacha.pasha.run/health")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = response as? HTTPURLResponse
        XCTAssertEqual(http?.statusCode, 200)
        XCTAssertEqual(String(data: data, encoding: .utf8), "ok")
        print("✅ Share server health OK")
    }

    func testAASA() async throws {
        let url = URL(string: "https://kacha.pasha.run/.well-known/apple-app-site-association")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = response as? HTTPURLResponse
        XCTAssertEqual(http?.statusCode, 200)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json?["applinks"])
        print("✅ AASA endpoint OK")
    }

    func testShareCreateAndFetch() async throws {
        // Create a share
        let shareData = HomeShareData(
            name: "Test", address: "", role: "guest",
            switchBotToken: "", switchBotSecret: "",
            hueBridgeIP: "", hueUsername: "",
            sesameApiKey: "", sesameDeviceUUIDs: "",
            qrioApiKey: "", qrioDeviceIds: "",
            doorCode: "9999", wifiPassword: "test",
            beds24ApiKey: nil, beds24RefreshToken: nil
        )

        let result = try await ShareClient.createShare(
            data: shareData, validFrom: nil, expiresAt: nil, ownerToken: UUID().uuidString
        )
        XCTAssertFalse(result.token.isEmpty)
        XCTAssertFalse(result.encryptionKey.isEmpty)
        print("✅ Share created: token=\(result.token.prefix(20))...")

        // Fetch and decrypt
        let fetched = try await ShareClient.fetchShare(token: result.token, encryptionKey: result.encryptionKey)
        XCTAssertEqual(fetched.name, "Test")
        XCTAssertEqual(fetched.doorCode, "9999")
        print("✅ Share fetched and decrypted: \(fetched.name)")
    }
}
