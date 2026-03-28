import Foundation
import SwiftData

// MARK: - PricingRule (SwiftData Model)

@Model
final class PricingRule {
    var id: String
    var homeId: String

    /// 0=日, 1=月, 2=火, 3=水, 4=木, 5=金, 6=土
    var dayOfWeek: Int

    /// 季節・繁忙期倍率 (e.g. 1.5 = +50%)
    var seasonMultiplier: Double

    /// イベント倍率（将来拡張用）
    var eventMultiplier: Double

    /// 基本価格（円・1泊）
    var basePrice: Int

    /// 最低価格（この価格を下回らない）
    var minPrice: Int

    /// 最高価格（この価格を超えない）
    var maxPrice: Int

    /// true = 提案価格を自動でBeds24に反映する
    var isAutoApply: Bool

    var updatedAt: Date

    init(
        homeId: String,
        dayOfWeek: Int = 0,
        basePrice: Int = 15000,
        minPrice: Int = 8000,
        maxPrice: Int = 50000,
        seasonMultiplier: Double = 1.0,
        eventMultiplier: Double = 1.0,
        isAutoApply: Bool = false
    ) {
        self.id = UUID().uuidString
        self.homeId = homeId
        self.dayOfWeek = dayOfWeek
        self.basePrice = basePrice
        self.minPrice = minPrice
        self.maxPrice = maxPrice
        self.seasonMultiplier = seasonMultiplier
        self.eventMultiplier = eventMultiplier
        self.isAutoApply = isAutoApply
        self.updatedAt = Date()
    }

    /// 曜日ラベル
    var dayLabel: String {
        ["日", "月", "火", "水", "木", "金", "土"][dayOfWeek]
    }
}

// MARK: - EventInfoProvider (将来拡張用プロトコル)

/// 周辺イベント情報を提供するプロトコル。
/// 将来的に Ticketmaster API、Google Events、じゃらん等を実装する。
protocol EventInfoProvider {
    /// 指定日の近隣イベント倍率を非同期取得
    /// - Parameters:
    ///   - date: 対象日
    ///   - latitude: 物件緯度
    ///   - longitude: 物件経度
    /// - Returns: イベント需要倍率 (1.0 = 変化なし)
    func demandMultiplier(for date: Date, latitude: Double, longitude: Double) async -> Double
}

/// デフォルト実装（イベントAPI未接続時のプレースホルダー）
struct NoOpEventInfoProvider: EventInfoProvider {
    func demandMultiplier(for date: Date, latitude: Double, longitude: Double) async -> Double {
        return 1.0
    }
}
