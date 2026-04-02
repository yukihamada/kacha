import Foundation
import SwiftData

/// Stores sent messages for smart reply suggestion.
/// Past replies are analyzed to generate contextual suggestions.
@Model
final class SentMessage {
    var id: String
    var homeId: String
    var bookingId: String
    var guestName: String
    var text: String
    var inReplyTo: String  // the guest message this was a reply to (if any)
    var category: String   // "checkin", "wifi", "checkout", "thanks", "trouble", "general"
    var sentAt: Date

    init(
        homeId: String,
        bookingId: String,
        guestName: String,
        text: String,
        inReplyTo: String = "",
        category: String = "general",
        sentAt: Date = Date()
    ) {
        self.id = UUID().uuidString
        self.homeId = homeId
        self.bookingId = bookingId
        self.guestName = guestName
        self.text = text
        self.inReplyTo = inReplyTo
        self.category = category
        self.sentAt = sentAt
    }
}
