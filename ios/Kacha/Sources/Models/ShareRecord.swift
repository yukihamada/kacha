import Foundation
import SwiftData

@Model
final class ShareRecord {
    var id: String
    var homeId: String
    var homeName: String
    var token: String          // server-side token
    var ownerToken: String     // secret — needed to revoke
    var validFrom: Date
    var expiresAt: Date
    var revoked: Bool
    var createdAt: Date

    var isActive: Bool {
        !revoked && Date() >= validFrom && Date() <= expiresAt
    }

    var isExpired: Bool {
        !revoked && Date() > expiresAt
    }

    var statusLabel: String {
        if revoked { return "取り消し済み" }
        if Date() < validFrom { return "開始前" }
        if Date() > expiresAt { return "期限切れ" }
        return "有効"
    }

    init(homeId: String, homeName: String, token: String, ownerToken: String, validFrom: Date, expiresAt: Date) {
        self.id = UUID().uuidString
        self.homeId = homeId
        self.homeName = homeName
        self.token = token
        self.ownerToken = ownerToken
        self.validFrom = validFrom
        self.expiresAt = expiresAt
        self.revoked = false
        self.createdAt = Date()
    }
}
