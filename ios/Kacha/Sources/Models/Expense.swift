import Foundation
import SwiftData

@Model
final class Expense {
    var id: String
    var homeId: String
    var category: String   // "cleaning" | "utility" | "supplies" | "maintenance" | "other"
    var amount: Int        // yen
    var date: Date
    var notes: String
    var receiptImageData: Data?
    var createdAt: Date

    init(
        homeId: String,
        category: String,
        amount: Int,
        date: Date = Date(),
        notes: String = "",
        receiptImageData: Data? = nil
    ) {
        self.id = UUID().uuidString
        self.homeId = homeId
        self.category = category
        self.amount = amount
        self.date = date
        self.notes = notes
        self.receiptImageData = receiptImageData
        self.createdAt = Date()
    }

    static let categories: [(key: String, label: String, icon: String, color: String)] = [
        ("cleaning",    "清掃費",   "sparkles",              "3B9FE8"),
        ("utility",     "光熱費",   "bolt.fill",             "F59E0B"),
        ("supplies",    "消耗品",   "cart.fill",             "10B981"),
        ("maintenance", "修繕費",   "wrench.and.screwdriver","EF4444"),
        ("other",       "その他",   "ellipsis.circle.fill",  "8B5CF6"),
    ]

    var categoryLabel: String {
        Self.categories.first { $0.key == category }?.label ?? "その他"
    }

    var categoryIcon: String {
        Self.categories.first { $0.key == category }?.icon ?? "ellipsis.circle.fill"
    }

    var categoryColor: String {
        Self.categories.first { $0.key == category }?.color ?? "8B5CF6"
    }

    /// "yyyy-MM" 形式（RevenueReportView の expensesForMonth と同じ粒度）
    var month: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f.string(from: date)
    }
}
