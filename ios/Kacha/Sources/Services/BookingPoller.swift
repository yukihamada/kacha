import Foundation
import SwiftData
import UserNotifications

// MARK: - Booking Poller
// Beds24を定期ポーリングして新規予約を検知→プッシュ通知

struct BookingPoller {

    /// Beds24から最新予約を取得し、新規があれば通知
    static func pollAndNotify(context: ModelContext, home: Home) async -> Int {
        guard !home.beds24ICalURL.isEmpty else { return 0 }
        guard let token = try? await Beds24Client.shared.getToken(refreshToken: home.beds24ICalURL) else { return 0 }
        guard let b24Bookings = try? await Beds24Client.shared.fetchBookings(token: token) else { return 0 }

        let existingExtIDs = Set(((try? context.fetch(FetchDescriptor<Booking>())) ?? []).map { $0.externalId })
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        var imported = 0

        for b24 in b24Bookings {
            let extId = "beds24-\(b24.effectiveId)"
            guard !existingExtIDs.contains(extId) else { continue }
            guard let cin = b24.arrival.flatMap({ df.date(from: $0) }),
                  let cout = b24.departure.flatMap({ df.date(from: $0) }) else { continue }

            let booking = Booking(
                guestName: b24.guestFullName,
                guestEmail: b24.email ?? "",
                guestPhone: b24.phone ?? "",
                platform: b24.platformKey,
                homeId: home.id,
                externalId: extId,
                checkIn: cin, checkOut: cout,
                totalAmount: Int((b24.price ?? 0) * 100),
                status: b24.status == "cancelled" ? "cancelled" : "upcoming"
            )
            context.insert(booking)
            imported += 1

            // Push notification for new booking
            sendNewBookingNotification(
                guestName: b24.guestFullName,
                homeName: home.name,
                checkIn: b24.arrival ?? "",
                platform: b24.platformKey
            )
        }
        try? context.save()
        return imported
    }

    private static func sendNewBookingNotification(guestName: String, homeName: String, checkIn: String, platform: String) {
        let content = UNMutableNotificationContent()
        content.title = "新しい予約 — \(homeName)"
        content.body = "\(guestName)様 · \(checkIn) · \(platform)"
        content.sound = .default
        content.userInfo = ["type": "new_booking"]

        let request = UNNotificationRequest(
            identifier: "new-booking-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
