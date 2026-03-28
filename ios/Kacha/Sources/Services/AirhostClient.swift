import Foundation

// MARK: - Airhost API クライアント
// Airhost: https://airhost.co
// API仕様: https://airhost.co/api/v1/ (推定 — 実際のAPIキーで動作確認を要する)
//
// 認証フロー:
//   credentials["apiKey"] → POST /sessions → token
//
// 必要な認証情報:
//   - "apiKey": Airhost管理画面 → 設定 → API連携 で取得

final class AirhostClient: PMSProvider {

    // MARK: PMSProvider

    var name: String { "Airhost" }
    var icon: String { "building.2"  }

    private let base = "https://airhost.co/api/v1"

    // MARK: - 認証

    /// Airhost APIキーからセッショントークンを取得する。
    /// - Parameter credentials: ["apiKey": "<Airhost APIキー>"]
    /// - Returns: Bearer トークン文字列
    func authenticate(credentials: [String: String]) async throws -> String {
        guard let apiKey = credentials["apiKey"], !apiKey.isEmpty else {
            throw PMSError.missingCredential("apiKey")
        }

        guard let sessionsURL = URL(string: "\(base)/sessions") else { throw PMSError.authenticationFailed("Invalid URL") }
        var req = URLRequest(url: sessionsURL)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["api_key": apiKey])
        req.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard status == 200 || status == 201 else {
            throw PMSError.authenticationFailed("HTTP \(status)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? String, !token.isEmpty else {
            throw PMSError.authenticationFailed("レスポンスにトークンが含まれていません")
        }

        return token
    }

    // MARK: - 予約取得

    /// Airhostから今後の予約一覧を取得する。
    /// エンドポイント: GET /reservations
    func fetchBookings(token: String) async throws -> [PMSBooking] {
        guard var components = URLComponents(string: "\(base)/reservations") else { throw PMSError.apiError(0, "Invalid URL") }
        components.queryItems = [
            URLQueryItem(name: "status", value: "confirmed"),
            URLQueryItem(name: "per_page", value: "100"),
        ]

        guard let reqURL = components.url else { throw PMSError.apiError(0, "Invalid URL") }
        var req = URLRequest(url: reqURL)
        req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.addValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard status == 200 else {
            throw PMSError.apiError(status, "予約取得失敗")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PMSError.decodingError
        }

        // Airhost APIはレスポンスを "reservations" キーに格納すると想定
        let reservations = (json["reservations"] as? [[String: Any]])
            ?? (json["data"] as? [[String: Any]])
            ?? []

        return reservations.compactMap { Self.mapBooking($0) }
    }

    // MARK: - 物件取得

    /// Airhostから物件一覧を取得する。
    /// エンドポイント: GET /spaces
    func fetchProperties(token: String) async throws -> [PMSProperty] {
        guard let spacesURL = URL(string: "\(base)/spaces") else { throw PMSError.apiError(0, "Invalid URL") }
        var req = URLRequest(url: spacesURL)
        req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.addValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard status == 200 else {
            throw PMSError.apiError(status, "物件取得失敗")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PMSError.decodingError
        }

        let spaces = (json["spaces"] as? [[String: Any]])
            ?? (json["data"] as? [[String: Any]])
            ?? []

        return spaces.compactMap { Self.mapProperty($0) }
    }

    // MARK: - マッピング（private）

    private static func mapBooking(_ raw: [String: Any]) -> PMSBooking? {
        guard
            let idRaw = raw["id"],
            let checkInStr = raw["check_in"] as? String,
            let checkOutStr = raw["check_out"] as? String,
            let checkIn = DateFormatter.pmsDateFormatter.date(from: checkInStr),
            let checkOut = DateFormatter.pmsDateFormatter.date(from: checkOutStr)
        else { return nil }

        let id = "\(idRaw)"
        let guest = raw["guest"] as? [String: Any] ?? [:]
        let guestFirstName = guest["first_name"] as? String ?? ""
        let guestLastName = guest["last_name"] as? String ?? ""
        let guestName = [guestLastName, guestFirstName]
            .filter { !$0.isEmpty }.joined(separator: " ")

        return PMSBooking(
            id: UUID().uuidString,
            externalId: id,
            guestName: guestName.isEmpty ? "ゲスト" : guestName,
            guestEmail: guest["email"] as? String ?? "",
            guestPhone: guest["phone"] as? String ?? "",
            checkIn: checkIn,
            checkOut: checkOut,
            platform: "airhost",
            totalAmount: (raw["total_price"] as? Double)
                ?? Double(raw["total_price"] as? Int ?? 0),
            currency: raw["currency"] as? String ?? "JPY",
            status: raw["status"] as? String ?? "confirmed",
            notes: raw["remarks"] as? String ?? "",
            propertyId: "\(raw["space_id"] ?? "")",
            numAdults: raw["number_of_guests"] as? Int ?? 1,
            numChildren: 0
        )
    }

    private static func mapProperty(_ raw: [String: Any]) -> PMSProperty? {
        guard let idRaw = raw["id"] else { return nil }
        let id = "\(idRaw)"
        let images = raw["images"] as? [[String: Any]] ?? []
        let imageURL = images.first?["url"] as? String

        return PMSProperty(
            id: UUID().uuidString,
            externalId: id,
            name: raw["name"] as? String ?? "物件",
            address: raw["address"] as? String ?? "",
            imageURL: imageURL,
            provider: "Airhost"
        )
    }
}
