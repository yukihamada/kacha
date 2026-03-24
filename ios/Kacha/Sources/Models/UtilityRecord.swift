import Foundation
import SwiftData

@Model
final class UtilityRecord {
    var id: String
    var homeId: String
    var category: String   // "electric", "gas", "water"
    var amount: Int        // yen
    var month: String      // "2026-03"
    var note: String
    var createdAt: Date

    init(homeId: String, category: String, amount: Int, month: String, note: String = "") {
        self.id = UUID().uuidString
        self.homeId = homeId
        self.category = category
        self.amount = amount
        self.month = month
        self.note = note
        self.createdAt = Date()
    }

    static let categories: [(key: String, label: String, icon: String, color: String)] = [
        ("electric", "電気", "bolt.fill", "F59E0B"),
        ("gas", "ガス", "flame.fill", "EF4444"),
        ("water", "水道", "drop.fill", "3B9FE8"),
    ]
}
