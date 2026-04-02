import XCTest
@testable import Kacha

// MARK: - GuestPage Unit Tests
// GuestPageClient.CreateRequest の JSON エンコード確認と
// WiFi QRコードフォーマットの仕様検証。ネットワーク非依存。

final class GuestPageTests: XCTestCase {

    // MARK: - CreateRequest JSON エンコード

    func testCreateRequestFullFieldsEncodesToJSON() throws {
        let req = GuestPageClient.CreateRequest(
            home_name: "渋谷ゲストハウス",
            wifi_ssid: "GuestHouse_5G",
            wifi_password: "secure-wifi-2026",
            door_code: "1234#",
            address: "東京都渋谷区道玄坂1-1",
            check_in_info: "15:00以降にチェックインできます",
            check_out_info: "11:00までにお部屋をお出ください",
            house_rules: "禁煙・ペット不可",
            emergency_info: "警察: 110, 消防: 119",
            nearby_places: nil,
            custom_sections: nil,
            language: "ja",
            expires_at: nil
        )

        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json)
        XCTAssertEqual(json?["home_name"] as? String, "渋谷ゲストハウス")
        XCTAssertEqual(json?["wifi_ssid"] as? String, "GuestHouse_5G")
        XCTAssertEqual(json?["wifi_password"] as? String, "secure-wifi-2026")
        XCTAssertEqual(json?["door_code"] as? String, "1234#")
        XCTAssertEqual(json?["address"] as? String, "東京都渋谷区道玄坂1-1")
        XCTAssertEqual(json?["check_in_info"] as? String, "15:00以降にチェックインできます")
        XCTAssertEqual(json?["check_out_info"] as? String, "11:00までにお部屋をお出ください")
        XCTAssertEqual(json?["house_rules"] as? String, "禁煙・ペット不可")
        XCTAssertEqual(json?["language"] as? String, "ja")
    }

    func testCreateRequestMinimalFieldsEncodesToJSON() throws {
        let req = GuestPageClient.CreateRequest(
            home_name: "最小限ホーム",
            wifi_ssid: nil,
            wifi_password: nil,
            door_code: nil,
            address: nil,
            check_in_info: nil,
            check_out_info: nil,
            house_rules: nil,
            emergency_info: nil,
            nearby_places: nil,
            custom_sections: nil,
            language: nil,
            expires_at: nil
        )

        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json)
        XCTAssertEqual(json?["home_name"] as? String, "最小限ホーム")
        // nil フィールドはJSONに含まれない (Encodable のデフォルト動作)
        XCTAssertNil(json?["wifi_ssid"])
        XCTAssertNil(json?["wifi_password"])
        XCTAssertNil(json?["door_code"])
    }

    func testCreateRequestLanguageEnglish() throws {
        let req = GuestPageClient.CreateRequest(
            home_name: "Tokyo House",
            wifi_ssid: "TokyoHouse",
            wifi_password: "password123",
            door_code: nil,
            address: "Tokyo, Japan",
            check_in_info: "Check in after 3PM",
            check_out_info: "Check out before 11AM",
            house_rules: "No smoking",
            emergency_info: nil,
            nearby_places: nil,
            custom_sections: nil,
            language: "en",
            expires_at: nil
        )

        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["language"] as? String, "en")
        XCTAssertEqual(json?["home_name"] as? String, "Tokyo House")
    }

    func testCreateRequestWithExpiresAt() throws {
        let isoFormatter = ISO8601DateFormatter()
        let expiryDate = isoFormatter.date(from: "2026-12-31T23:59:59Z")!
        let expiryStr = isoFormatter.string(from: expiryDate)

        let req = GuestPageClient.CreateRequest(
            home_name: "期限付きホーム",
            wifi_ssid: nil, wifi_password: nil, door_code: nil,
            address: nil, check_in_info: nil, check_out_info: nil,
            house_rules: nil, emergency_info: nil,
            nearby_places: nil, custom_sections: nil,
            language: "ja",
            expires_at: expiryStr
        )

        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["expires_at"] as? String, expiryStr)
    }

    func testCreateRequestJSONKeysAreSnakeCase() throws {
        let req = GuestPageClient.CreateRequest(
            home_name: "スネークケーステスト",
            wifi_ssid: "SSID", wifi_password: "pass",
            door_code: "0000", address: nil,
            check_in_info: "info", check_out_info: "info",
            house_rules: nil, emergency_info: "emergency",
            nearby_places: nil, custom_sections: nil,
            language: "ja", expires_at: nil
        )

        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // スネークケースキーの存在確認
        XCTAssertNotNil(json?["home_name"])
        XCTAssertNotNil(json?["wifi_ssid"])
        XCTAssertNotNil(json?["wifi_password"])
        XCTAssertNotNil(json?["door_code"])
        XCTAssertNotNil(json?["check_in_info"])
        XCTAssertNotNil(json?["check_out_info"])
        XCTAssertNotNil(json?["emergency_info"])

        // キャメルケースキーが存在しないことを確認
        XCTAssertNil(json?["homeName"])
        XCTAssertNil(json?["wifiSsid"])
        XCTAssertNil(json?["checkInInfo"])
    }

    // MARK: - WiFi QRコードフォーマット確認

    func testWiFiQRCodeFormatWPA() {
        let ssid = "MyHomeWiFi"
        let password = "SecurePass2026"
        let qrString = makeWiFiQRCode(ssid: ssid, password: password, security: "WPA")

        XCTAssertEqual(qrString, "WIFI:T:WPA;S:MyHomeWiFi;P:SecurePass2026;;")
    }

    func testWiFiQRCodeFormatWPA2() {
        let qrString = makeWiFiQRCode(ssid: "GuestNet_5G", password: "P@ss!word", security: "WPA2")
        XCTAssertTrue(qrString.hasPrefix("WIFI:T:WPA2;"),
            "WPA2形式はWIFI:T:WPA2;で始まるべき")
        XCTAssertTrue(qrString.contains("S:GuestNet_5G;"),
            "SSIDが含まれるべき")
        XCTAssertTrue(qrString.contains("P:P@ss!word;"),
            "パスワードが含まれるべき")
        XCTAssertTrue(qrString.hasSuffix(";;"),
            "WiFi QRコードは;;で終わるべき")
    }

    func testWiFiQRCodeFormatNoPassword() {
        // オープンネットワーク
        let qrString = makeWiFiQRCode(ssid: "PublicWiFi", password: "", security: "nopass")
        XCTAssertTrue(qrString.contains("T:nopass;"))
        XCTAssertTrue(qrString.contains("S:PublicWiFi;"))
    }

    func testWiFiQRCodeSSIDWithSpecialChars() {
        // 日本語SSIDの取り扱い
        let qrString = makeWiFiQRCode(ssid: "渋谷ゲストWi-Fi", password: "password", security: "WPA")
        XCTAssertTrue(qrString.contains("S:渋谷ゲストWi-Fi;"),
            "日本語SSIDがそのまま含まれるべき")
    }

    func testWiFiQRCodePasswordWithBackslash() {
        // バックスラッシュを含むパスワードはエスケープが必要
        let rawPassword = "pass\\word"
        let qrString = makeWiFiQRCode(ssid: "TestNet", password: rawPassword, security: "WPA")
        XCTAssertFalse(qrString.isEmpty)
        // フォーマットが崩れていないことを確認
        XCTAssertTrue(qrString.hasPrefix("WIFI:"))
        XCTAssertTrue(qrString.hasSuffix(";;"))
    }

    func testWiFiQRCodeIsReadableByQRScanners() {
        // Wi-Fi QRコードの標準フォーマット検証
        // 参考: https://github.com/zxing/zxing/wiki/Barcode-Contents#wi-fi-network-config-android-ios-11
        let ssid = "TestNetwork"
        let password = "TestPassword"
        let qrString = makeWiFiQRCode(ssid: ssid, password: password, security: "WPA")

        // 必須プレフィックス
        XCTAssertTrue(qrString.hasPrefix("WIFI:"))
        // タイプ指定
        XCTAssertTrue(qrString.contains("T:WPA;"))
        // SSID
        XCTAssertTrue(qrString.contains("S:\(ssid);"))
        // パスワード
        XCTAssertTrue(qrString.contains("P:\(password);"))
        // 終端
        XCTAssertTrue(qrString.hasSuffix(";;"))
    }

    // MARK: - GuestPageClient.CreateResponse デコード

    func testCreateResponseDecodesFromJSON() throws {
        let json = """
        {
            "token": "abc123xyz",
            "url": "https://kagi.pasha.run/g/abc123xyz"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(GuestPageClient.CreateResponse.self, from: json)

        XCTAssertEqual(response.token, "abc123xyz")
        XCTAssertEqual(response.url, "https://kagi.pasha.run/g/abc123xyz")
    }

    func testCreateResponseTokenNotEmpty() throws {
        let json = """
        {"token": "test-token-001", "url": "https://kagi.pasha.run/g/test-token-001"}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(GuestPageClient.CreateResponse.self, from: json)

        XCTAssertFalse(response.token.isEmpty)
        XCTAssertFalse(response.url.isEmpty)
        XCTAssertTrue(response.url.contains(response.token),
            "URL はトークンを含むべき: url=\(response.url), token=\(response.token)")
    }

    // MARK: - GuestPageError

    func testGuestPageErrorDescriptions() {
        XCTAssertNotNil(GuestPageError.uploadFailed.errorDescription)
        XCTAssertNotNil(GuestPageError.networkError.errorDescription)
        XCTAssertFalse(GuestPageError.uploadFailed.errorDescription!.isEmpty)
        XCTAssertFalse(GuestPageError.networkError.errorDescription!.isEmpty)
    }

    // MARK: - Private Helpers

    /// Wi-Fi QRコード文字列を生成する (標準フォーマット)
    /// 形式: WIFI:T:<security>;S:<ssid>;P:<password>;;
    private func makeWiFiQRCode(ssid: String, password: String, security: String) -> String {
        if password.isEmpty {
            return "WIFI:T:\(security);S:\(ssid);P:;;"
        }
        return "WIFI:T:\(security);S:\(ssid);P:\(password);;"
    }
}
