import Foundation
import SwiftData

@Model
final class HouseManual {
    var id: String
    var homeId: String
    var sections: String  // JSON encoded [ManualSection]
    var updatedAt: Date

    init(homeId: String) {
        self.id = UUID().uuidString
        self.homeId = homeId
        self.sections = "[]"
        self.updatedAt = Date()
    }

    var decodedSections: [ManualSection] {
        get {
            guard let data = sections.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([ManualSection].self, from: data)) ?? []
        }
        set {
            sections = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]"
            updatedAt = Date()
        }
    }
}

struct ManualSection: Codable, Identifiable {
    var id: String
    var type: String      // template key
    var title: String
    var content: String
    var enabled: Bool

    init(type: String, title: String, content: String = "", enabled: Bool = true) {
        self.id = UUID().uuidString
        self.type = type
        self.title = title
        self.content = content
        self.enabled = enabled
    }

    static let templates: [(key: String, icon: String, title: String, defaultContent: String)] = [
        ("welcome", "hand.wave.fill", "ようこそ",
         "ようこそお越しくださいました。快適にお過ごしいただけるよう、こちらのガイドをご確認ください。"),
        ("checkin", "key.fill", "チェックイン",
         "チェックイン: 15:00以降\nドアコードでお入りください。"),
        ("checkout", "door.right.hand.open", "チェックアウト",
         "チェックアウト: 10:00まで\n鍵は自動ロックです。ドアを閉めるだけでOKです。"),
        ("wifi", "wifi", "Wi-Fi",
         "ネットワーク名: \nパスワード: "),
        ("trash", "trash.fill", "ゴミの出し方",
         "燃えるゴミ: 月・木\n資源ゴミ: 水\nゴミ袋はキッチン下にあります。"),
        ("bathroom", "shower.fill", "お風呂・トイレ",
         "シャンプー・ボディソープは浴室にあります。\nタオルはクローゼットの中です。"),
        ("kitchen", "fork.knife", "キッチン",
         "調理器具と食器は自由にお使いください。\n使った後は洗って元の場所にお戻しください。"),
        ("laundry", "washer.fill", "洗濯機",
         "洗濯機はバスルーム横にあります。\n洗剤は洗濯機の上に置いてあります。"),
        ("aircon", "air.conditioner.horizontal.fill", "エアコン",
         "リモコンはベッドサイドにあります。\nお出かけの際はOFFにしてください。"),
        ("emergency", "exclamationmark.triangle.fill", "緊急時",
         "警察: 110\n消防・救急: 119\n管理人: "),
        ("rules", "list.bullet.rectangle.fill", "ハウスルール",
         "・室内禁煙\n・22時以降はお静かに\n・ペット不可\n・パーティー禁止"),
        ("parking", "car.fill", "駐車場",
         "駐車場はありません。近隣のコインパーキングをご利用ください。"),
        ("transport", "tram.fill", "アクセス",
         "最寄り駅: 徒歩○分\nバス停: 徒歩○分"),
        ("custom", "text.badge.plus", "カスタム", ""),
    ]
}
