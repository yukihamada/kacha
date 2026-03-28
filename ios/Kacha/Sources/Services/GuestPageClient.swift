import Foundation

// MARK: - Guest Page Client
// Generates a hosted web page from HouseManual data.
// The page is publicly accessible — no encryption. Do not include sensitive API keys.

struct GuestPageClient {
    static let baseURL = "https://kacha.pasha.run"

    // MARK: - Request / Response

    struct CreateRequest: Encodable {
        let home_name: String
        let wifi_ssid: String?
        let wifi_password: String?
        let door_code: String?
        let address: String?
        let check_in_info: String?
        let check_out_info: String?
        let house_rules: String?
        let emergency_info: String?
        let nearby_places: String?   // JSON array string, e.g. [{"emoji":"🍜","name":"Ramen","description":"5 min"}]
        let custom_sections: String? // JSON array string
        let language: String?
        let expires_at: String?      // ISO8601, nil = never expires
    }

    struct CreateResponse: Decodable {
        let token: String
        let url: String
    }

    // MARK: - Create from Home + HouseManual

    static func createPage(
        home: Home,
        manual: HouseManual,
        language: String = "ja",
        expiresAt: Date? = nil
    ) async throws -> CreateResponse {
        // Extract well-known sections from HouseManual
        let sections = manual.decodedSections.filter(\.enabled)
        func content(for key: String) -> String? {
            let s = sections.first(where: { $0.type == key })?.content ?? ""
            return s.isEmpty ? nil : s
        }

        // Wifi SSID is not stored in HouseManual; derive from Home
        let wifiSSID: String? = home.name.isEmpty ? nil : home.name
        // wifi_password is stored on Home.wifiPassword
        let wifiPass: String? = home.wifiPassword.isEmpty ? nil : home.wifiPassword
        let doorCode: String? = home.doorCode.isEmpty ? nil : home.doorCode
        let address: String? = home.address.isEmpty ? nil : home.address

        let iso = ISO8601DateFormatter()
        let req = CreateRequest(
            home_name: home.name,
            wifi_ssid: wifiSSID,
            wifi_password: wifiPass,
            door_code: doorCode,
            address: address,
            check_in_info: content(for: "checkin"),
            check_out_info: content(for: "checkout"),
            house_rules: content(for: "rules"),
            emergency_info: content(for: "emergency"),
            nearby_places: nil,
            custom_sections: nil,
            language: language,
            expires_at: expiresAt.map { iso.string(from: $0) }
        )

        return try await post(request: req)
    }

    // MARK: - Create with explicit fields

    static func createPage(request: CreateRequest) async throws -> CreateResponse {
        return try await post(request: request)
    }

    // MARK: - Private

    private static func post(request: CreateRequest) async throws -> CreateResponse {
        guard let url = URL(string: "\(baseURL)/api/v1/guest-pages") else { throw GuestPageError.uploadFailed }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 15

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
            throw GuestPageError.uploadFailed
        }

        return try JSONDecoder().decode(CreateResponse.self, from: data)
    }
}

// MARK: - Errors

enum GuestPageError: Error, LocalizedError {
    case uploadFailed
    case networkError

    var errorDescription: String? {
        switch self {
        case .uploadFailed:  return "ゲストページの作成に失敗しました"
        case .networkError:  return "ネットワークエラー"
        }
    }
}
