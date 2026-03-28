import ActivityKit
import Foundation

// MARK: - ActivityAttributes

/// KAGIスマートロックのLive Activity属性定義。
/// iOS側（LiveActivityManager）とWidget Extension（KachaLiveActivity）の両方から参照される。
@available(iOS 16.1, *)
struct KachaLockAttributes: ActivityAttributes {

    // MARK: Static attributes (変化しない物件情報)

    /// 物件名（例: "渋谷ハウス"）
    public var homeName: String

    /// 物件ID（SwiftDataのHome.id）
    public var homeId: String

    // MARK: ContentState (動的に変化する状態)

    public struct ContentState: Codable, Hashable {

        /// 施錠中かどうか
        var isLocked: Bool

        /// SwitchBotのバッテリー残量 (0–100)。取得不可の場合は -1
        var batteryLevel: Int

        /// 次に到着するゲスト名。予約なしの場合は nil
        var nextGuestName: String?

        /// 次のチェックイン日時。予約なしの場合は nil
        var nextCheckIn: Date?

        /// 最終更新日時
        var lastUpdated: Date
    }
}
