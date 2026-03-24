import Foundation
import SwiftData

@Model
final class Booking {
    var id: String
    var guestName: String
    var guestEmail: String
    var guestPhone: String
    var platform: String  // "airbnb" | "jalan" | "beds24" | "booking" | "direct" | "other"
    var homeId: String = ""
    var externalId: String = ""  // beds24 bookId etc.
    var checkIn: Date
    var checkOut: Date
    var roomCount: Int
    var totalAmount: Int
    var status: String    // "upcoming" | "active" | "completed" | "cancelled"
    var notes: String
    var autoUnlock: Bool
    var autoLight: Bool
    var cleaningDone: Bool
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        guestName: String,
        guestEmail: String = "",
        guestPhone: String = "",
        platform: String = "direct",
        homeId: String = "",
        externalId: String = "",
        checkIn: Date,
        checkOut: Date,
        roomCount: Int = 1,
        totalAmount: Int = 0,
        status: String = "upcoming",
        notes: String = "",
        autoUnlock: Bool = true,
        autoLight: Bool = true,
        cleaningDone: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.guestName = guestName
        self.guestEmail = guestEmail
        self.guestPhone = guestPhone
        self.platform = platform
        self.homeId = homeId
        self.externalId = externalId
        self.checkIn = checkIn
        self.checkOut = checkOut
        self.roomCount = roomCount
        self.totalAmount = totalAmount
        self.status = status
        self.notes = notes
        self.autoUnlock = autoUnlock
        self.autoLight = autoLight
        self.cleaningDone = cleaningDone
        self.createdAt = createdAt
    }

    var nights: Int {
        Calendar.current.dateComponents([.day], from: checkIn, to: checkOut).day ?? 0
    }

    var isActive: Bool { status == "active" }

    var isToday: Bool { Calendar.current.isDateInToday(checkIn) }

    var platformLabel: String {
        switch platform {
        case "airbnb":   return "Airbnb"
        case "jalan":    return "じゃらん"
        case "beds24":   return "Beds24"
        case "booking":  return "Booking.com"
        case "expedia":  return "Expedia"
        case "direct":   return "直接"
        default:         return "その他"
        }
    }

    var platformColor: String {
        switch platform {
        case "airbnb":   return "FF5A5F"
        case "jalan":    return "FF6600"
        case "beds24":   return "0066CC"
        case "booking":  return "003580"
        case "expedia":  return "1C6BBA"
        case "direct":   return "3B9FE8"
        default:         return "6B7280"
        }
    }

    var statusLabel: String {
        switch status {
        case "upcoming": return "予定"
        case "active": return "滞在中"
        case "completed": return "完了"
        case "cancelled": return "キャンセル"
        default: return status
        }
    }
}
