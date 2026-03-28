import Foundation

// MARK: - Beds24 Client
// Invite Code取得: Beds24 → 設定 → API v2 → Invite Code作成
// ドキュメント: https://beds24.com/api/v2
// 認証フロー: Invite Code → POST /authentication/setup → token取得 → 以降tokenで認証

final class Beds24Client: Sendable {
    static let shared = Beds24Client()
    private let base = "https://api.beds24.com/v2"

    // MARK: - Authentication
    // Flow: Invite Code → GET /authentication/setup → refreshToken
    //       refreshToken → GET /authentication/token → token
    //       token → use in all API calls via "token" header

    /// Step 1: Invite Code → Refresh Token
    func setupWithInviteCode(_ inviteCode: String, deviceName: String = "カチャ") async throws -> String {
        guard !inviteCode.isEmpty else { throw Beds24Error.missingCode }
        guard let setupURL = URL(string: "\(base)/authentication/setup") else { throw Beds24Error.apiError(0) }
        var req = URLRequest(url: setupURL)
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
        guard let tokenURL = URL(string: "\(base)/authentication/token") else { throw Beds24Error.apiError(0) }
        var req = URLRequest(url: tokenURL)
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

    /// Beds24 API v2で予約を取得
    /// パラメータなし = upcoming bookings（最も確実）
    func fetchBookings(token: String, includeGuests: Bool = true) async throws -> [Beds24Booking] {
        guard !token.isEmpty else { return [] }

        // No date params — API returns upcoming bookings by default
        var urlStr = "\(base)/bookings?"
        if includeGuests { urlStr += "includeGuests=true&" }
        urlStr += "includeInvoiceItems=true"

        guard let bookingsURL = URL(string: urlStr) else { throw Beds24Error.apiError(0) }
        var req = URLRequest(url: bookingsURL)
        req.addValue(token, forHTTPHeaderField: "token")
        req.addValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: req)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        #if DEBUG
        if let rawStr = String(data: data, encoding: .utf8) {
            print("[Beds24] Status: \(statusCode), Response: \(rawStr.prefix(200))")
        }
        #endif

        guard statusCode == 200 else {
            throw Beds24Error.apiError(statusCode)
        }

        // Try decoding with flexible structure
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Check if data is in "data" key or top level
            if let bookingsArray = json["data"] as? [[String: Any]] {
                #if DEBUG
                print("[Beds24] Found \(bookingsArray.count) bookings in 'data' key")
                #endif
                let reencoded = try JSONSerialization.data(withJSONObject: bookingsArray)
                do {
                    return try JSONDecoder().decode([Beds24Booking].self, from: reencoded)
                } catch {
                    #if DEBUG
                    print("[Beds24] Booking decode error: \(error)")
                    #endif
                    return []
                }
            }
        }

        // Try direct decode
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
        guard let bookingsURL = URL(string: "\(base)/bookings") else { throw Beds24Error.apiError(0) }
        var req = URLRequest(url: bookingsURL)
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
        guard let bookingsURL = URL(string: "\(base)/bookings") else { throw Beds24Error.apiError(0) }
        var req = URLRequest(url: bookingsURL)
        req.httpMethod = "POST"
        req.addValue(token, forHTTPHeaderField: "token")
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [["id": bookId, "notes": note]])
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode < 300 else {
            throw Beds24Error.apiError((resp as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    /// 物件情報を取得（includePhotos=true で photos[] も含む）
    func fetchProperties(token: String, includePhotos: Bool = true) async throws -> [[String: Any]] {
        var urlStr = "\(base)/properties"
        if includePhotos { urlStr += "?includePhotos=true" }
        guard let propsURL = URL(string: urlStr) else { throw Beds24Error.apiError(0) }
        var req = URLRequest(url: propsURL)
        req.addValue(token, forHTTPHeaderField: "token")
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Beds24Error.apiError(status) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let props = json["data"] as? [[String: Any]] else { return [] }
        return props
    }

    /// プロパティ辞書から画像URLを抽出する。
    /// 優先順位: photos[0].url > photos[0].large > image (トップレベル文字列)
    /// 相対パスの場合は https://beds24.com をプレフィックスとして付与。
    static func extractImageURL(from prop: [String: Any]) -> String? {
        let beds24Base = "https://beds24.com"

        // photos 配列を探索
        if let photos = prop["photos"] as? [[String: Any]] {
            for photo in photos {
                let candidate = (photo["url"] as? String)
                    ?? (photo["large"] as? String)
                    ?? (photo["medium"] as? String)
                if let raw = candidate, !raw.isEmpty {
                    return raw.hasPrefix("http") ? raw : "\(beds24Base)\(raw)"
                }
            }
        }

        // トップレベル image フィールド
        if let raw = prop["image"] as? String, !raw.isEmpty {
            return raw.hasPrefix("http") ? raw : "\(beds24Base)\(raw)"
        }

        return nil
    }

    // MARK: - Property Details

    /// 物件の詳細情報を取得
    func getProperty(id: Int, token: String) async throws -> [String: Any] {
        let data = try await apiGet("/properties/\(id)", token: token)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Beds24Error.decodingFailed
        }
        return json
    }

    /// 物件情報を更新（名前、設備、ルール等）
    func updateProperty(id: Int, fields: [String: Any], token: String) async throws {
        var payload = fields
        payload["id"] = id
        try await apiPost("/properties", body: [payload], token: token)
    }

    // MARK: - Property Content (説明文・写真)

    /// 物件のコンテンツ（説明文・写真一覧）を取得
    func getPropertyContent(propertyId: Int, token: String) async throws -> Beds24PropertyContent {
        let data = try await apiGet("/propertyContent?propertyId=\(propertyId)", token: token)
        // レスポンスが配列の場合とオブジェクトの場合に対応
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], let first = arr.first {
            return Beds24PropertyContent(from: first)
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dataArr = obj["data"] as? [[String: Any]], let first = dataArr.first {
            return Beds24PropertyContent(from: first)
        }
        throw Beds24Error.decodingFailed
    }

    /// 物件の説明文を更新
    func updatePropertyDescription(propertyId: Int, description: String, token: String) async throws {
        try await apiPost("/setPropertyContent", body: [["propertyId": propertyId, "description": description]], token: token)
    }

    /// 物件の写真を追加（URL指定）
    func addPropertyPhoto(propertyId: Int, imageURL: String, caption: String? = nil, token: String) async throws {
        var photo: [String: Any] = ["url": imageURL]
        if let caption { photo["caption"] = caption }
        try await apiPost("/setPropertyContent", body: [["propertyId": propertyId, "photos": [photo]]], token: token)
    }

    /// 物件のコンテンツを一括更新（説明文、写真、チェックイン案内等）
    func updatePropertyContent(propertyId: Int, content: [String: Any], token: String) async throws {
        var payload = content
        payload["propertyId"] = propertyId
        try await apiPost("/setPropertyContent", body: [payload], token: token)
    }

    // MARK: - Availability & Room Dates (空室・日別料金)

    /// 空室・料金情報を取得
    func getAvailabilities(propertyId: Int, startDate: String, endDate: String, token: String) async throws -> [Beds24Availability] {
        let data = try await apiGet("/availabilities?propertyId=\(propertyId)&startDate=\(startDate)&endDate=\(endDate)", token: token)
        return decodeDataArray(data) ?? []
    }

    /// 日別の料金・制限・空室を取得
    func getRoomDates(propertyId: Int, startDate: String, endDate: String, roomId: Int? = nil, token: String) async throws -> [Beds24RoomDate] {
        var url = "/roomDates?propertyId=\(propertyId)&startDate=\(startDate)&endDate=\(endDate)"
        if let roomId { url += "&roomId=\(roomId)" }
        let data = try await apiGet(url, token: token)
        return decodeDataArray(data) ?? []
    }

    /// 日別の料金・空室・制限を更新
    func setRoomDates(entries: [Beds24RoomDateUpdate], token: String) async throws {
        let payload = entries.map { $0.toDict() }
        try await apiPost("/setRoomDates", body: payload, token: token)
    }

    // MARK: - Rates (料金プラン)

    /// 料金プラン一覧を取得
    func getRates(propertyId: Int, token: String) async throws -> [[String: Any]] {
        let data = try await apiGet("/rates?propertyId=\(propertyId)", token: token)
        return decodeRawDataArray(data) ?? []
    }

    /// 料金プランを更新
    func setRate(rateData: [String: Any], token: String) async throws {
        try await apiPost("/setRate", body: [rateData], token: token)
    }

    /// 複数の料金プランを一括更新
    func setRates(rates: [[String: Any]], token: String) async throws {
        try await apiPost("/setRates", body: rates, token: token)
    }

    /// 料金リンク情報を取得
    func getRateLinks(propertyId: Int, token: String) async throws -> [[String: Any]] {
        let data = try await apiGet("/rateLinks?propertyId=\(propertyId)", token: token)
        return decodeRawDataArray(data) ?? []
    }

    /// 料金リンクを更新
    func setRateLinks(links: [[String: Any]], token: String) async throws {
        try await apiPost("/setRateLinks", body: links, token: token)
    }

    // MARK: - Prices (日別料金 — PricingSuggestionServiceから移動)

    /// 日別料金を設定
    func setPrices(entries: [Beds24PriceEntry], token: String) async throws {
        let payload = entries.map { $0.toDict() }
        try await apiPost("/prices", body: payload, token: token)
    }

    // MARK: - Daily Price Setup

    /// 料金設定ルールを取得
    func getDailyPriceSetup(propertyId: Int, token: String) async throws -> [[String: Any]] {
        let data = try await apiGet("/dailyPriceSetup?propertyId=\(propertyId)", token: token)
        return decodeRawDataArray(data) ?? []
    }

    /// 料金設定ルールを更新
    func setDailyPriceSetup(setup: [[String: Any]], token: String) async throws {
        try await apiPost("/setDailyPriceSetup", body: setup, token: token)
    }

    // MARK: - Booking Messages (ゲストメッセージ)

    /// 予約にメッセージを送信（ゲスト通知）
    func sendBookingMessage(bookingId: Int, message: String, subject: String? = nil, token: String) async throws {
        var payload: [String: Any] = ["bookingId": bookingId, "message": message]
        if let subject { payload["subject"] = subject }
        try await apiPatch("/bookings/messages", body: [payload], token: token)
    }

    /// 予約のメッセージ履歴を取得
    func getBookingMessages(bookingId: Int, token: String) async throws -> [[String: Any]] {
        let data = try await apiGet("/bookings/messages?bookingId=\(bookingId)", token: token)
        return decodeRawDataArray(data) ?? []
    }

    // MARK: - Booking Create / Modify

    /// 新規予約を作成
    func createBooking(booking: Beds24BookingCreate, token: String) async throws -> Int? {
        let data = try await apiPostReturningData("/bookings", body: [booking.toDict()], token: token)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let ids = json["data"] as? [[String: Any]], let first = ids.first,
           let newId = first["id"] as? Int {
            return newId
        }
        return nil
    }

    // MARK: - Invoices (請求)

    /// 請求書一覧を取得
    func getInvoices(propertyId: Int? = nil, token: String) async throws -> [Beds24Invoice] {
        var url = "/invoices"
        if let propertyId { url += "?propertyId=\(propertyId)" }
        let data = try await apiGet(url, token: token)
        return decodeDataArray(data) ?? []
    }

    /// 請求先情報を取得
    func getInvoicees(token: String) async throws -> [[String: Any]] {
        let data = try await apiGet("/invoicees", token: token)
        return decodeRawDataArray(data) ?? []
    }

    /// 請求先情報を更新
    func setInvoicees(invoicees: [[String: Any]], token: String) async throws {
        try await apiPost("/setInvoicees", body: invoicees, token: token)
    }

    // MARK: - Channels (チャネル連携)

    /// Booking.comのレビューを取得
    func getBookingComReviews(propertyId: Int, token: String) async throws -> [Beds24Review] {
        let data = try await apiGet("/channels/booking/reviews?propertyId=\(propertyId)", token: token)
        return decodeDataArray(data) ?? []
    }

    /// Stripe決済リンクを作成
    func createStripePayment(bookingId: Int, amount: Double, currency: String = "JPY", token: String) async throws -> String? {
        let payload: [String: Any] = ["bookingId": bookingId, "amount": amount, "currency": currency]
        let data = try await apiPostReturningData("/channels/stripe", body: [payload], token: token)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let url = json["url"] as? String {
            return url
        }
        return nil
    }

    // MARK: - Inventory (在庫管理)

    /// 部屋の料金・空室を一括更新（チャネルマネージャー向け）
    func updateRoomCalendar(entries: [[String: Any]], token: String) async throws {
        try await apiPost("/inventory/rooms/calendar", body: entries, token: token)
    }

    /// 部屋のオファー（料金プラン付き空室）を取得
    func getRoomOffers(propertyId: Int, startDate: String, endDate: String, adults: Int = 2, token: String) async throws -> [[String: Any]] {
        let url = "/inventory/rooms/offers?propertyId=\(propertyId)&startDate=\(startDate)&endDate=\(endDate)&adults=\(adults)"
        let data = try await apiGet(url, token: token)
        return decodeRawDataArray(data) ?? []
    }

    // MARK: - CSV Export/Import

    /// 予約CSVをエクスポート
    func exportBookingsCSV(propertyId: Int, startDate: String, endDate: String, token: String) async throws -> String {
        let data = try await apiGet("/bookingsCSV?propertyId=\(propertyId)&arrivalFrom=\(startDate)&arrivalTo=\(endDate)", token: token)
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// 料金CSVをエクスポート
    func exportRatesCSV(propertyId: Int, token: String) async throws -> String {
        let data = try await apiGet("/ratesCSV?propertyId=\(propertyId)", token: token)
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Private Helpers

    private func buildURL(_ path: String) throws -> URL {
        guard let url = URL(string: "\(base)\(path)"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let resolved = components.url else {
            throw Beds24Error.invalidURL(path)
        }
        return resolved
    }

    private func apiGet(_ path: String, token: String) async throws -> Data {
        let url = try buildURL(path)
        var req = URLRequest(url: url)
        req.addValue(token, forHTTPHeaderField: "token")
        req.addValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15
        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw Beds24Error.networkError(error)
        }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Beds24Error.apiError(status) }
        return data
    }

    private func apiPost(_ path: String, body: [[String: Any]], token: String) async throws {
        _ = try await apiPostReturningData(path, body: body, token: token)
    }

    private func apiPostReturningData(_ path: String, body: [[String: Any]], token: String) async throws -> Data {
        let url = try buildURL(path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue(token, forHTTPHeaderField: "token")
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 15
        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw Beds24Error.networkError(error)
        }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Beds24Error.apiError(status) }
        return data
    }

    private func apiPatch(_ path: String, body: [[String: Any]], token: String) async throws {
        let url = try buildURL(path)
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.addValue(token, forHTTPHeaderField: "token")
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 15
        let (_,  resp): (Data, URLResponse)
        do {
            (_, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw Beds24Error.networkError(error)
        }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Beds24Error.apiError(status) }
    }

    private func decodeDataArray<T: Decodable>(_ data: Data) -> [T]? {
        // { "data": [...] } 形式
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let arr = json["data"] {
            let arrData = try? JSONSerialization.data(withJSONObject: arr)
            if let arrData, let decoded = try? JSONDecoder().decode([T].self, from: arrData) {
                return decoded
            }
        }
        // 直接配列の場合
        if let direct = try? JSONDecoder().decode([T].self, from: data) {
            return direct
        }
        #if DEBUG
        print("[Beds24] decodeDataArray failed for \(T.self): \(String(data: data, encoding: .utf8)?.prefix(200) ?? "nil")")
        #endif
        return nil
    }

    private func decodeRawDataArray(_ data: Data) -> [[String: Any]]? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let arr = json["data"] as? [[String: Any]] { return arr }
        return try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    }
}

enum Beds24Error: Error, LocalizedError {
    case apiError(Int)
    case missingCode
    case invalidCode
    case invalidURL(String)
    case decodingFailed
    case networkError(Error)
    var errorDescription: String? {
        switch self {
        case .apiError(let code): return "Beds24 APIエラー: HTTP \(code)"
        case .missingCode: return "Invite Codeが入力されていません"
        case .invalidCode: return "Invite Codeが無効です。Beds24で新しいコードを作成してください"
        case .invalidURL(let path): return "Beds24 URL構築エラー: \(path)"
        case .decodingFailed: return "Beds24レスポンスの解析に失敗しました"
        case .networkError(let err): return "ネットワークエラー: \(err.localizedDescription)"
        }
    }
}

struct Beds24Response: Codable {
    let data: [Beds24Booking]?
}

struct Beds24Booking: Codable {
    let id: Int?
    let propertyId: Int?
    let roomId: Int?
    let status: String?          // "new", "confirmed", "request", "cancelled"
    let arrival: String?         // "2026-05-05"
    let departure: String?       // "2026-05-06"
    let firstName: String?       // API v2 uses firstName, not guestFirstName
    let lastName: String?
    let email: String?
    let phone: String?
    let numAdult: Int?
    let numChild: Int?
    let price: Double?
    let commission: Double?
    let referer: String?
    let channel: String?
    let apiReference: String?
    let comments: String?
    let notes: String?

    var effectiveId: Int { id ?? 0 }

    var guestFullName: String {
        let parts = [lastName, firstName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "ゲスト" : parts.joined(separator: " ")
    }

    var platformKey: String {
        let ch = (channel ?? referer ?? "").lowercased()
        if ch.contains("airbnb") { return "airbnb" }
        if ch.contains("booking") { return "booking" }
        if ch.contains("expedia") { return "expedia" }
        if ch.contains("jalan") { return "jalan" }
        return "beds24"
    }
}

// MARK: - Property Content Model

struct Beds24PropertyContent {
    let propertyId: Int
    let name: String
    let description: String
    let checkInInfo: String
    let photos: [Beds24Photo]

    init(from dict: [String: Any]) {
        self.propertyId = dict["propertyId"] as? Int ?? 0
        self.name = dict["name"] as? String ?? ""
        self.description = dict["description"] as? String ?? ""
        self.checkInInfo = dict["checkInInfo"] as? String ?? ""
        let rawPhotos = dict["photos"] as? [[String: Any]] ?? []
        self.photos = rawPhotos.map { Beds24Photo(from: $0) }
    }
}

struct Beds24Photo {
    let url: String
    let caption: String
    let position: Int

    init(from dict: [String: Any]) {
        let raw = (dict["url"] as? String) ?? (dict["large"] as? String) ?? ""
        self.url = raw.hasPrefix("http") ? raw : "https://beds24.com\(raw)"
        self.caption = dict["caption"] as? String ?? ""
        self.position = dict["position"] as? Int ?? 0
    }
}

// MARK: - Availability Model

struct Beds24Availability: Codable {
    let propertyId: Int?
    let roomId: Int?
    let date: String?
    let available: Int?
    let price: Double?
    let minStay: Int?
    let maxStay: Int?
}

// MARK: - Room Date Models

struct Beds24RoomDate: Codable {
    let propertyId: Int?
    let roomId: Int?
    let date: String?
    let price1: Double?
    let price2: Double?
    let available: Int?
    let minStay: Int?
    let maxStay: Int?
    let closedOnArrival: Bool?
    let closedOnDeparture: Bool?
}

struct Beds24RoomDateUpdate {
    let propertyId: Int
    let roomId: Int
    let date: String        // "2026-04-01"
    var price: Double?
    var available: Int?
    var minStay: Int?
    var maxStay: Int?
    var closedOnArrival: Bool?
    var closedOnDeparture: Bool?

    func toDict() -> [String: Any] {
        var d: [String: Any] = ["propertyId": propertyId, "roomId": roomId, "date": date]
        if let price { d["price1"] = price }
        if let available { d["available"] = available }
        if let minStay { d["minStay"] = minStay }
        if let maxStay { d["maxStay"] = maxStay }
        if let closedOnArrival { d["closedOnArrival"] = closedOnArrival }
        if let closedOnDeparture { d["closedOnDeparture"] = closedOnDeparture }
        return d
    }
}

// MARK: - Price Entry

struct Beds24PriceEntry {
    let propertyId: Int
    let roomId: Int
    let date: String
    let price: Double

    func toDict() -> [String: Any] {
        ["propertyId": propertyId, "roomId": roomId, "date": date, "price": price]
    }
}

// MARK: - Booking Create

struct Beds24BookingCreate {
    let propertyId: Int
    let roomId: Int?
    let arrival: String
    let departure: String
    var firstName: String?
    var lastName: String?
    var email: String?
    var phone: String?
    var numAdult: Int?
    var numChild: Int?
    var price: Double?
    var status: String?     // "new", "confirmed"

    func toDict() -> [String: Any] {
        var d: [String: Any] = ["propertyId": propertyId, "arrival": arrival, "departure": departure]
        if let roomId { d["roomId"] = roomId }
        if let firstName { d["firstName"] = firstName }
        if let lastName { d["lastName"] = lastName }
        if let email { d["email"] = email }
        if let phone { d["phone"] = phone }
        if let numAdult { d["numAdult"] = numAdult }
        if let numChild { d["numChild"] = numChild }
        if let price { d["price"] = price }
        if let status { d["status"] = status }
        return d
    }
}

// MARK: - Invoice Model

struct Beds24Invoice: Codable {
    let id: Int?
    let propertyId: Int?
    let bookingId: Int?
    let date: String?
    let dueDate: String?
    let amount: Double?
    let currency: String?
    let status: String?
    let description: String?
}

// MARK: - Review Model

struct Beds24Review: Codable {
    let id: Int?
    let propertyId: Int?
    let bookingId: Int?
    let date: String?
    let guestName: String?
    let title: String?
    let positive: String?
    let negative: String?
    let score: Double?
    let reply: String?
}

// MARK: - Push Notification Registration

/// サーバーにBeds24アカウント+APNsトークンを登録（プッシュ通知用）
enum Beds24PushRegistrar {
    private static let serverBase = "https://kacha-server.fly.dev"

    static func register(userId: String, refreshToken: String, pushToken: String) async {
        guard let url = URL(string: "\(serverBase)/api/v1/beds24/register") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10
        let body: [String: String] = [
            "user_id": userId,
            "refresh_token": refreshToken,
            "push_token": pushToken,
            "platform": "apns"
        ]
        req.httpBody = try? JSONEncoder().encode(body)
        _ = try? await URLSession.shared.data(for: req)
        #if DEBUG
        print("[Beds24Push] Registered userId=\(userId.prefix(8))...")
        #endif
    }

    static func unregister(userId: String) async {
        guard let url = URL(string: "\(serverBase)/api/v1/beds24/unregister") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10
        req.httpBody = try? JSONEncoder().encode(["user_id": userId])
        _ = try? await URLSession.shared.data(for: req)
    }
}
