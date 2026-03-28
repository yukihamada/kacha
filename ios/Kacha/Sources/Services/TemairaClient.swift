import Foundation

// MARK: - 手間いらず (Temaira) API クライアント
// 手間いらず: https://temaira.com
// API仕様: https://temaira.com/api/ (推定 — 実際のAPIキーで動作確認を要する)
//
// 認証フロー:
//   credentials["username"] + credentials["password"]
//   → POST /api/login → access_token (JWT)
//
// 必要な認証情報:
//   - "username": 手間いらずのログインメールアドレス
//   - "password": 手間いらずのパスワード
//
// 参考: 手間いらず は民泊・旅館向けPMS。
//       APIドキュメントが非公開の場合はサポートに問い合わせてください。

final class TemairaClient: PMSProvider {

    // MARK: PMSProvider

    var name: String { "手間いらず" }
    var icon: String { "calendar.badge.checkmark" }

    private let base = "https://temaira.com/api/v1"

    // MARK: - 認証

    /// 手間いらずのユーザー名/パスワードでJWTトークンを取得する。
    /// - Parameter credentials: ["username": "<email>", "password": "<password>"]
    /// - Returns: JWT アクセストークン
    func authenticate(credentials: [String: String]) async throws -> String {
        guard let username = credentials["username"], !username.isEmpty else {
            throw PMSError.missingCredential("username")
        }
        guard let password = credentials["password"], !password.isEmpty else {
            throw PMSError.missingCredential("password")
        }

        guard let loginURL = URL(string: "\(base)/login") else { throw PMSError.authenticationFailed("Invalid URL") }
        var req = URLRequest(url: loginURL)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": username,
            "password": password
        ])
        req.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard status == 200 else {
            throw PMSError.authenticationFailed("HTTP \(status) — ユーザー名またはパスワードが間違っています")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PMSError.decodingError
        }

        // JWTトークンは "access_token" または "token" キーで返される想定
        let token = (json["access_token"] as? String)
            ?? (json["token"] as? String)
            ?? ""

        guard !token.isEmpty else {
            throw PMSError.authenticationFailed("レスポンスにトークンが含まれていません")
        }

        return token
    }

    // MARK: - 予約取得

    /// 手間いらずから予約一覧を取得する。
    /// エンドポイント: GET /reservations
    func fetchBookings(token: String) async throws -> [PMSBooking] {
        guard var components = URLComponents(string: "\(base)/reservations") else { throw PMSError.apiError(0, "Invalid URL") }
        // 今日以降のチェックイン予約を取得
        let today = DateFormatter.pmsDateFormatter.string(from: Date())
        components.queryItems = [
            URLQueryItem(name: "check_in_from", value: today),
            URLQueryItem(name: "per_page", value: "100"),
            URLQueryItem(name: "page", value: "1"),
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

        let reservations = (json["reservations"] as? [[String: Any]])
            ?? (json["data"] as? [[String: Any]])
            ?? []

        return reservations.compactMap { Self.mapBooking($0) }
    }

    // MARK: - 物件取得

    /// 手間いらずから物件（施設）一覧を取得する。
    /// エンドポイント: GET /facilities
    func fetchProperties(token: String) async throws -> [PMSProperty] {
        guard let facilURL = URL(string: "\(base)/facilities") else { throw PMSError.apiError(0, "Invalid URL") }
        var req = URLRequest(url: facilURL)
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

        let facilities = (json["facilities"] as? [[String: Any]])
            ?? (json["data"] as? [[String: Any]])
            ?? []

        return facilities.compactMap { Self.mapProperty($0) }
    }

    // MARK: - マッピング（private）

    private static func mapBooking(_ raw: [String: Any]) -> PMSBooking? {
        guard
            let idRaw = raw["id"],
            let checkInStr = raw["check_in_date"] as? String
                ?? raw["checkin"] as? String
                ?? raw["arrival"] as? String,
            let checkOutStr = raw["check_out_date"] as? String
                ?? raw["checkout"] as? String
                ?? raw["departure"] as? String,
            let checkIn = DateFormatter.pmsDateFormatter.date(from: checkInStr),
            let checkOut = DateFormatter.pmsDateFormatter.date(from: checkOutStr)
        else { return nil }

        let id = "\(idRaw)"

        // 手間いらずはゲスト情報をネストまたはフラットで返す可能性がある
        let guestName: String
        if let nested = raw["guest"] as? [String: Any] {
            let last = nested["last_name"] as? String ?? ""
            let first = nested["first_name"] as? String ?? ""
            guestName = [last, first].filter { !$0.isEmpty }.joined(separator: " ")
        } else {
            guestName = raw["guest_name"] as? String ?? ""
        }

        return PMSBooking(
            id: UUID().uuidString,
            externalId: id,
            guestName: guestName.isEmpty ? "ゲスト" : guestName,
            guestEmail: (raw["guest"] as? [String: Any])?["email"] as? String
                ?? raw["guest_email"] as? String ?? "",
            guestPhone: (raw["guest"] as? [String: Any])?["phone"] as? String
                ?? raw["guest_phone"] as? String ?? "",
            checkIn: checkIn,
            checkOut: checkOut,
            platform: "temaira",
            totalAmount: (raw["total_amount"] as? Double)
                ?? (raw["total_price"] as? Double)
                ?? Double(raw["total_amount"] as? Int ?? 0),
            currency: "JPY",
            status: mapStatus(raw["status"] as? String),
            notes: raw["memo"] as? String
                ?? raw["notes"] as? String ?? "",
            propertyId: "\(raw["facility_id"] ?? raw["property_id"] ?? "")",
            numAdults: raw["adult_count"] as? Int
                ?? raw["guests"] as? Int ?? 1,
            numChildren: raw["child_count"] as? Int ?? 0
        )
    }

    private static func mapStatus(_ raw: String?) -> String {
        switch raw?.lowercased() {
        case "confirmed", "reserved": return "confirmed"
        case "cancelled", "canceled": return "cancelled"
        case "pending", "tentative":  return "pending"
        default:                      return "confirmed"
        }
    }

    private static func mapProperty(_ raw: [String: Any]) -> PMSProperty? {
        guard let idRaw = raw["id"] else { return nil }
        let id = "\(idRaw)"

        let imageURL: String? = (raw["images"] as? [[String: Any]])?.first?["url"] as? String
            ?? raw["image_url"] as? String
            ?? raw["thumbnail"] as? String

        return PMSProperty(
            id: UUID().uuidString,
            externalId: id,
            name: raw["name"] as? String
                ?? raw["facility_name"] as? String ?? "施設",
            address: raw["address"] as? String
                ?? raw["location"] as? String ?? "",
            imageURL: imageURL,
            provider: "手間いらず"
        )
    }
}
