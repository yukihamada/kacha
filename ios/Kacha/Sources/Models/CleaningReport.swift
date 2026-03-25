import Foundation
import SwiftData

// MARK: - CleaningReport SwiftData Model

@Model
final class CleaningReport {
    var id: String
    var homeId: String
    var homeName: String
    var cleanerName: String
    var startedAt: Date
    var completedAt: Date?
    /// カンマ区切りのファイルパス (Documents/CleaningPhotos/ 以下)
    var photoPaths: String
    /// JSON encoded [[String: Any]] — [{id, title, isChecked}]
    var checklistJSON: String
    var notes: String
    var suppliesNeeded: String
    /// "in_progress" | "completed"
    var status: String

    // MARK: Computed helpers

    var isCompleted: Bool { status == "completed" }

    var duration: TimeInterval? {
        guard let end = completedAt else { return nil }
        return end.timeIntervalSince(startedAt)
    }

    var durationLabel: String {
        guard let d = duration else { return "進行中" }
        let minutes = Int(d / 60)
        if minutes < 60 { return "\(minutes)分" }
        return "\(minutes / 60)時間\(minutes % 60)分"
    }

    var photoPathList: [String] {
        photoPaths.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    var checklist: [CleaningCheckItem] {
        get {
            guard let data = checklistJSON.data(using: .utf8),
                  let items = try? JSONDecoder().decode([CleaningCheckItem].self, from: data)
            else { return CleaningCheckItem.defaults }
            return items
        }
        set {
            checklistJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]"
        }
    }

    init(homeId: String, homeName: String, cleanerName: String) {
        self.id = UUID().uuidString
        self.homeId = homeId
        self.homeName = homeName
        self.cleanerName = cleanerName
        self.startedAt = Date()
        self.completedAt = nil
        self.photoPaths = ""
        let defaultItems = CleaningCheckItem.defaults
        self.checklistJSON = (try? String(data: JSONEncoder().encode(defaultItems), encoding: .utf8)) ?? "[]"
        self.notes = ""
        self.suppliesNeeded = ""
        self.status = "in_progress"
    }
}

// MARK: - Checklist Item (value type, embedded in JSON)

struct CleaningCheckItem: Codable, Identifiable {
    var id: String
    var title: String
    var isChecked: Bool
    var category: String  // "cleaning" | "check" | "supplies"

    init(id: String = UUID().uuidString, title: String, isChecked: Bool = false, category: String = "cleaning") {
        self.id = id
        self.title = title
        self.isChecked = isChecked
        self.category = category
    }

    static let defaults: [CleaningCheckItem] = [
        // 清掃
        CleaningCheckItem(title: "床を掃除機がけ・モップ", category: "cleaning"),
        CleaningCheckItem(title: "バスルーム清掃・消毒", category: "cleaning"),
        CleaningCheckItem(title: "トイレ清掃", category: "cleaning"),
        CleaningCheckItem(title: "キッチン清掃（コンロ・シンク）", category: "cleaning"),
        CleaningCheckItem(title: "冷蔵庫の中身を確認・不要物廃棄", category: "cleaning"),
        CleaningCheckItem(title: "ゴミ袋を交換", category: "cleaning"),
        CleaningCheckItem(title: "ベッドメイク・リネン交換", category: "cleaning"),
        CleaningCheckItem(title: "窓・ガラス面を拭く", category: "cleaning"),
        // 確認
        CleaningCheckItem(title: "全ての照明が消えているか確認", category: "check"),
        CleaningCheckItem(title: "エアコンがOFFか確認", category: "check"),
        CleaningCheckItem(title: "全窓の施錠確認", category: "check"),
        CleaningCheckItem(title: "忘れ物がないか確認", category: "check"),
        // 備品
        CleaningCheckItem(title: "タオルをセット", category: "supplies"),
        CleaningCheckItem(title: "アメニティ補充（シャンプー・石鹸等）", category: "supplies"),
        CleaningCheckItem(title: "トイレットペーパー補充", category: "supplies"),
        CleaningCheckItem(title: "コーヒー・お茶セット補充", category: "supplies"),
    ]

    static func categoryLabel(_ category: String) -> String {
        switch category {
        case "cleaning": return "清掃"
        case "check":    return "確認"
        case "supplies": return "備品"
        default:         return "その他"
        }
    }

    static func categoryIcon(_ category: String) -> String {
        switch category {
        case "cleaning": return "sparkles"
        case "check":    return "checkmark.shield.fill"
        case "supplies": return "archivebox.fill"
        default:         return "list.bullet"
        }
    }
}
