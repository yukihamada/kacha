import Foundation

// MARK: - Beds24 Client
// API Key取得: Beds24ダッシュボード → Settings → Account → API Keys
// ドキュメント: https://beds24.com/api/v2

final class Beds24Client {
    static let shared = Beds24Client()
    private let base = "https://api.beds24.com/v2"

    /// Beds24 API v2でこれから60日分の予約を取得
    func fetchBookings(apiKey: String) async throws -> [Beds24Booking] {
        guard !apiKey.isEmpty else { return [] }
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd"
        let start = df.string(from: Date())
        let endDate = Calendar.current.date(byAdding: .day, value: 60, to: Date()) ?? Date()
        let end = df.string(from: endDate)

        var req = URLRequest(url: URL(string: "\(base)/bookings?checkInFrom=\(start)&checkInTo=\(end)&includeInvoice=true")!)
        req.addValue(apiKey, forHTTPHeaderField: "X-Api-Key")
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
}

enum Beds24Error: Error, LocalizedError {
    case apiError(Int)
    var errorDescription: String? {
        switch self { case .apiError(let code): return "Beds24 APIエラー: HTTP \(code)" }
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
