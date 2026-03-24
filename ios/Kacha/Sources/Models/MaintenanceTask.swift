import Foundation
import SwiftData

@Model
final class MaintenanceTask {
    var id: String
    var homeId: String
    var title: String
    var intervalDays: Int      // repeat every N days
    var lastCompletedAt: Date?
    var createdAt: Date

    var nextDueDate: Date {
        guard let last = lastCompletedAt else { return createdAt }
        return Calendar.current.date(byAdding: .day, value: intervalDays, to: last) ?? last
    }

    var isOverdue: Bool { nextDueDate < Date() }
    var daysUntilDue: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: nextDueDate).day ?? 0
    }

    init(homeId: String, title: String, intervalDays: Int) {
        self.id = UUID().uuidString
        self.homeId = homeId
        self.title = title
        self.intervalDays = intervalDays
        self.lastCompletedAt = nil
        self.createdAt = Date()
    }

    static let defaults: [(String, Int)] = [
        ("エアコンフィルター掃除", 90),
        ("浄水器カートリッジ交換", 180),
        ("火災報知器点検", 365),
        ("換気扇掃除", 180),
        ("排水口掃除", 30),
    ]
}

@Model
final class NearbyPlace {
    var id: String
    var homeId: String
    var name: String
    var category: String   // "convenience", "super", "station", "hospital", "restaurant", "other"
    var address: String
    var note: String
    var sortOrder: Int

    init(homeId: String, name: String, category: String, address: String = "", note: String = "", sortOrder: Int = 0) {
        self.id = UUID().uuidString
        self.homeId = homeId
        self.name = name
        self.category = category
        self.address = address
        self.note = note
        self.sortOrder = sortOrder
    }

    static let categoryInfo: [(key: String, label: String, icon: String)] = [
        ("convenience", "コンビニ", "bag.fill"),
        ("super", "スーパー", "cart.fill"),
        ("station", "駅", "tram.fill"),
        ("hospital", "病院", "cross.case.fill"),
        ("restaurant", "飲食店", "fork.knife"),
        ("other", "その他", "mappin.and.ellipse"),
    ]
}
