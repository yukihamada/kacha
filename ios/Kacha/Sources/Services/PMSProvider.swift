import Foundation

// MARK: - PMS共通プロトコル
// Airhost, 手間いらず, Beds24など複数のPMSに対応するための抽象層。
// 新しいPMSを追加する場合はこのプロトコルに準拠したクライアントを実装する。

protocol PMSProvider {
    /// 表示名（設定画面等で使用）
    var name: String { get }
    /// SF Symbols or アセット名
    var icon: String { get }
    /// 認証を行いAPIトークンを返す
    /// - Parameter credentials: PMS固有の認証情報（"apiKey", "username", "password" 等）
    /// - Returns: 以降のAPI呼び出しで使用するトークン文字列
    func authenticate(credentials: [String: String]) async throws -> String
    /// 予約一覧を取得する
    func fetchBookings(token: String) async throws -> [PMSBooking]
    /// 物件一覧を取得する
    func fetchProperties(token: String) async throws -> [PMSProperty]
}

// MARK: - 共通予約構造体
// 各PMSの独自スキーマをこの共通型にマッピングして使用する。

struct PMSBooking: Identifiable {
    let id: String
    let externalId: String          // PMS側の予約ID
    let guestName: String
    let guestEmail: String
    let guestPhone: String
    let checkIn: Date
    let checkOut: Date
    let platform: String            // "airhost", "temaira", "beds24" 等
    let totalAmount: Double
    let currency: String            // "JPY", "USD" 等
    let status: String              // "confirmed", "cancelled", "pending"
    let notes: String
    let propertyId: String
    let numAdults: Int
    let numChildren: Int

    var guestCount: Int { numAdults + numChildren }

    var nights: Int {
        Calendar.current.dateComponents([.day], from: checkIn, to: checkOut).day ?? 0
    }
}

// MARK: - 共通物件構造体

struct PMSProperty: Identifiable {
    let id: String
    let externalId: String          // PMS側の物件ID
    let name: String
    let address: String
    let imageURL: String?
    let provider: String            // PMSProvider.name
}

// MARK: - PMS共通エラー

enum PMSError: Error, LocalizedError {
    case missingCredential(String)
    case authenticationFailed(String)
    case apiError(Int, String)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .missingCredential(let key):
            return "認証情報が不足しています: \(key)"
        case .authenticationFailed(let reason):
            return "認証に失敗しました: \(reason)"
        case .apiError(let code, let message):
            return "APIエラー \(code): \(message)"
        case .decodingError:
            return "レスポンスの解析に失敗しました"
        }
    }
}

// MARK: - 日付ユーティリティ（PMS共通）

extension DateFormatter {
    /// PMS APIで広く使われるYYYY-MM-DD形式
    static let pmsDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
