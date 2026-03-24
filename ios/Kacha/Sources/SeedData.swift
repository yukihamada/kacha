import Foundation
import SwiftData

#if DEBUG
struct SeedData {
    static func insert(into context: ModelContext) {
        // Check if already seeded
        let descriptor = FetchDescriptor<Booking>()
        let existing = (try? context.fetch(descriptor)) ?? []
        guard existing.isEmpty else { return }

        let cal = Calendar.current
        let now = Date()

        func date(daysOffset: Int) -> Date {
            cal.date(byAdding: .day, value: daysOffset, to: now) ?? now
        }

        let bookings: [Booking] = [
            // Active — checked in today
            {
                let b = Booking(
                    guestName: "田中 美咲",
                    guestEmail: "misaki@example.com",
                    guestPhone: "090-1234-5678",
                    platform: "airbnb",
                    checkIn: date(daysOffset: -1),
                    checkOut: date(daysOffset: 2),
                    totalAmount: 36000,
                    status: "active",
                    notes: "猫アレルギーあり。早めチェックアウト希望",
                    autoUnlock: true,
                    autoLight: true
                )
                return b
            }(),

            // Upcoming — today
            {
                let b = Booking(
                    guestName: "Kenji Yamamoto",
                    guestEmail: "kenji.y@example.com",
                    guestPhone: "080-9876-5432",
                    platform: "airbnb",
                    checkIn: now,
                    checkOut: date(daysOffset: 3),
                    totalAmount: 54000,
                    status: "upcoming",
                    notes: "英語対応希望 / Late check-in around 21:00",
                    autoUnlock: true,
                    autoLight: true
                )
                return b
            }(),

            // Upcoming — tomorrow
            {
                let b = Booking(
                    guestName: "鈴木 一郎",
                    platform: "jalan",
                    checkIn: date(daysOffset: 1),
                    checkOut: date(daysOffset: 4),
                    totalAmount: 42000,
                    status: "upcoming"
                )
                return b
            }(),

            // Upcoming — next week
            {
                let b = Booking(
                    guestName: "Lin Wei",
                    guestEmail: "linwei@example.com",
                    platform: "direct",
                    checkIn: date(daysOffset: 7),
                    checkOut: date(daysOffset: 10),
                    totalAmount: 45000,
                    status: "upcoming",
                    notes: "3名様でのご利用です"
                )
                return b
            }(),

            // Completed
            {
                let b = Booking(
                    guestName: "佐藤 花子",
                    platform: "airbnb",
                    checkIn: date(daysOffset: -10),
                    checkOut: date(daysOffset: -8),
                    totalAmount: 24000,
                    status: "completed",
                    cleaningDone: true
                )
                return b
            }(),

            // Completed
            {
                let b = Booking(
                    guestName: "Park Soyeon",
                    platform: "jalan",
                    checkIn: date(daysOffset: -20),
                    checkOut: date(daysOffset: -17),
                    totalAmount: 48000,
                    status: "completed",
                    cleaningDone: true
                )
                return b
            }()
        ]

        for booking in bookings {
            context.insert(booking)
        }
    }
}
#endif
