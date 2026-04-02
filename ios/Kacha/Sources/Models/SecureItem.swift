import Foundation
import SwiftData

@Model
final class SecureItem {
    var id: String
    var homeId: String
    var title: String
    var category: String    // "password", "apikey", "wifi", "pin", "note", "card"
    var username: String
    var encryptedValue: String  // stored encrypted in SwiftData (device-level encryption)
    var url: String
    var note: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(homeId: String, title: String, category: String = "password") {
        self.id = UUID().uuidString
        self.homeId = homeId
        self.title = title
        self.category = category
        self.username = ""
        self.encryptedValue = ""
        self.url = ""
        self.note = ""
        self.sortOrder = 0
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    static let categories: [(key: String, label: String, icon: String)] = [
        ("password", "パスワード", "key.fill"),
        ("apikey", "APIキー", "chevron.left.forwardslash.chevron.right"),
        ("wifi", "Wi-Fi", "wifi"),
        ("pin", "暗証番号", "lock.fill"),
        ("card", "クレジットカード", "creditcard.fill"),
        ("bank", "銀行口座", "building.columns.fill"),
        ("ssh", "SSH鍵", "terminal.fill"),
        ("token", "トークン / シークレット", "shield.checkered"),
        ("license", "ライセンスキー", "checkmark.seal.fill"),
        ("email", "メールアカウント", "envelope.fill"),
        ("server", "サーバー / DB", "server.rack"),
        ("social", "SNSアカウント", "person.crop.circle.fill"),
        ("crypto", "暗号通貨ウォレット", "bitcoinsign.circle.fill"),
        ("id", "本人確認 / ID", "person.text.rectangle.fill"),
        ("note", "セキュアメモ", "note.text"),
    ]
}
