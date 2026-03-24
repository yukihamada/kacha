import Foundation

// MARK: - Beds24 Client
// Invite Code取得: Beds24 → 設定 → API v2 → Invite Code作成
// ドキュメント: https://beds24.com/api/v2
// 認証フロー: Invite Code → POST /authentication/setup → token取得 → 以降tokenで認証

final class Beds24Client {
    static let shared = Beds24Client()
    private let base = "https://api.beds24.com/v2"

    // MARK: - Authentication
    // Flow: Invite Code → GET /authentication/setup → refreshToken
    //       refreshToken → GET /authentication/token → token
    //       token → use in all API calls via "token" header

    /// Step 1: Invite Code → Refresh Token
    func setupWithInviteCode(_ inviteCode: String, deviceName: String = "カチャ") async throws -> String {
        guard !inviteCode.isEmpty else { throw Beds24Error.missingCode }
        var req = URLRequest(url: URL(string: "\(base)/authentication/setup")!)
        req.httpMethod = "GET"
        req.addValue(inviteCode, forHTTPHeaderField: "code")
        req.addValue(deviceName, forHTTPHeaderField: "deviceName")
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw Beds24Error.apiError((resp as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let refreshToken = json["refreshToken"] as? String, !refreshToken.isEmpty else {
            throw Beds24Error.invalidCode
        }
        return refreshToken
    }

    /// Step 2: Refresh Token → API Token
    func getToken(refreshToken: String) async throws -> String {
        guard !refreshToken.isEmpty else { throw Beds24Error.missingCode }
        var req = URLRequest(url: URL(string: "\(base)/authentication/token")!)
        req.httpMethod = "GET"
        req.addValue(refreshToken, forHTTPHeaderField: "refreshToken")
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw Beds24Error.apiError((resp as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? String, !token.isEmpty else {
            throw Beds24Error.apiError(0)
        }
        return token
    }

    /// Full auth: Invite Code → refreshToken → token
    func authenticate(inviteCode: String) async throws -> (refreshToken: String, token: String) {
        let refreshToken = try await setupWithInviteCode(inviteCode)
        let token = try await getToken(refreshToken: refreshToken)
        return (refreshToken, token)
    }

    // MARK: - Bookings

    /// Beds24 API v2でこれから60日分の予約を取得
    func fetchBookings(token: String) async throws -> [Beds24Booking] {
        guard !token.isEmpty else { return [] }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let start = df.string(from: Date())
        let endDate = Calendar.current.date(byAdding: .day, value: 60, to: Date()) ?? Date()
        let end = df.string(from: endDate)

        var req = URLRequest(url: URL(string: "\(base)/bookings?arrival=\(start)&departure=\(end)&includeInvoiceItems=true")!)
        req.addValue(token, forHTTPHeaderField: "token")
        req.addValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw Beds24Error.apiError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let decoded = try JSONDecoder().decode(Beds24Response.self, from: data)
        return decoded.data ?? []
    }

    /// Beds24 iCal URLからインポート（APIキーなしでも使用可能）
    func iCalURL(from propKey: String) -> String {
        "https://beds24.com/ical.php?propKey=\(propKey)&roomId=0"
    }

    // MARK: - Booking Operations

    /// 予約ステータスを更新
    func updateBookingStatus(bookId: Int, status: String, token: String) async throws {
        var req = URLRequest(url: URL(string: "\(base)/bookings")!)
        req.httpMethod = "POST"
        req.addValue(token, forHTTPHeaderField: "token")
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [["id": bookId, "status": status]])
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode < 300 else {
            throw Beds24Error.apiError((resp as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    /// 予約にメモを追加
    func addBookingNote(bookId: Int, note: String, token: String) async throws {
        var req = URLRequest(url: URL(string: "\(base)/bookings")!)
        req.httpMethod = "POST"
        req.addValue(token, forHTTPHeaderField: "token")
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [["id": bookId, "notes": note]])
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode < 300 else {
            throw Beds24Error.apiError((resp as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    /// 物件情報を取得
    func fetchProperties(token: String) async throws -> [[String: Any]] {
        var req = URLRequest(url: URL(string: "\(base)/properties")!)
        req.addValue(token, forHTTPHeaderField: "token")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let props = json["data"] as? [[String: Any]] else { return [] }
        return props
    }
}

enum Beds24Error: Error, LocalizedError {
    case apiError(Int)
    case missingCode
    case invalidCode
    var errorDescription: String? {
        switch self {
        case .apiError(let code): return "Beds24 APIエラー: HTTP \(code)"
        case .missingCode: return "Invite Codeが入力されていません"
        case .invalidCode: return "Invite Codeが無効です。Beds24で新しいコードを作成してください"
        }
    }
}

struct Beds24Response: Codable {
    let data: [Beds24Booking]?
}

struct Beds24Booking: Codable {
    let bookId: Int?
    let guestFirstName: String?
    let guestLastName: String?
    let guestEmail: String?
    let guestPhone: String?
    let checkIn: String?    // "YYYY-MM-DD"
    let checkOut: String?
    let numAdult: Int?
    let price: Double?
    let status: String?     // "1"=confirmed, "0"=tentative, "-1"=cancelled
    let referer: String?    // booking platform

    var guestFullName: String {
        [guestFirstName, guestLastName].compactMap { $0 }.filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
            .isEmpty ? "ゲスト" :
        [guestFirstName, guestLastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    var platformKey: String {
        let r = referer?.lowercased() ?? ""
        if r.contains("airbnb") { return "airbnb" }
        if r.contains("booking") { return "booking" }
        if r.contains("expedia") { return "expedia" }
        return "beds24"
    }
}
