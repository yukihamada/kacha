import Foundation
import SwiftData

@Model
final class ChecklistItem {
    var id: String
    var homeId: String
    var title: String
    var category: String   // "checkin" or "checkout"
    var isCompleted: Bool
    var sortOrder: Int
    var createdAt: Date

    init(homeId: String, title: String, category: String, sortOrder: Int = 0) {
        self.id = UUID().uuidString
        self.homeId = homeId
        self.title = title
        self.category = category
        self.isCompleted = false
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }

    static let defaultCheckIn = [
        "エアコンをONにする",
        "照明を点ける",
        "Wi-Fiが繋がるか確認",
        "タオル・アメニティを確認",
        "ゴミ箱を空にする",
    ]

    static let defaultCheckOut = [
        "エアコンをOFFにする",
        "窓を閉める・施錠する",
        "照明を消す",
        "ゴミを回収する",
        "忘れ物がないか確認",
        "鍵を施錠する",
    ]
}
