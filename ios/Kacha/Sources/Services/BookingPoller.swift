import Foundation
import SwiftData
import UserNotifications

// MARK: - Booking Poller
// Beds24を定期ポーリングして新規予約を検知→プッシュ通知

struct BookingPoller {

    // MARK: - Auto-detect new properties

    /// Beds24の物件を自動チェックし、未登録の物件があればホームを自動作成
    static func autoDetectProperties(context: ModelContext, home: Home) async -> Int {
        guard !home.beds24RefreshToken.isEmpty else { return 0 }
        guard let token = try? await Beds24Client.shared.getToken(refreshToken: home.beds24RefreshToken) else { return 0 }
        guard let properties = try? await Beds24Client.shared.fetchProperties(token: token) else { return 0 }

        let allHomes = (try? context.fetch(FetchDescriptor<Home>())) ?? []
        let existingPropIds = Set(allHomes.compactMap { Int($0.beds24ApiKey) })
        var created = 0

        for prop in properties {
            guard let propId = prop["id"] as? Int, !existingPropIds.contains(propId) else { continue }
            let propName = prop["name"] as? String ?? "物件 \(propId)"

            let newHome = Home(name: propName, sortOrder: allHomes.count + created)
            newHome.beds24ApiKey = "\(propId)"
            newHome.beds24RefreshToken = home.beds24RefreshToken
            newHome.businessType = home.businessType
            context.insert(newHome)
            created += 1

            // Notify
            let content = UNMutableNotificationContent()
            content.title = "新しい物件を検出"
            content.body = "「\(propName)」がBeds24から自動追加されました"
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "new-property-\(propId)",
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)
        }

        if created > 0 { try? context.save() }
        return created
    }

    // MARK: - Poll Bookings

    /// Beds24から最新予約を取得し、新規があれば通知
    /// allHomes: propertyIdからhomeIdを解決するために全ホームを渡す
    static func pollAndNotify(context: ModelContext, home: Home, allHomes: [Home] = []) async -> Int {
        guard !home.beds24RefreshToken.isEmpty else { return 0 }
        guard let token = try? await Beds24Client.shared.getToken(refreshToken: home.beds24RefreshToken) else { return 0 }
        guard let b24Bookings = try? await Beds24Client.shared.fetchBookings(token: token) else { return 0 }

        let existingExtIDs = Set(((try? context.fetch(FetchDescriptor<Booking>())) ?? []).map { $0.externalId })
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        var imported = 0

        // Build propertyId → homeId mapping
        let propIdToHomeId: [Int: String] = {
            var map: [Int: String] = [:]
            let homes = allHomes.isEmpty ? [home] : allHomes
            for h in homes {
                if let propId = Int(h.beds24ApiKey) {
                    map[propId] = h.id
                }
            }
            return map
        }()

        for b24 in b24Bookings {
            let extId = "beds24-\(b24.effectiveId)"
            guard !existingExtIDs.contains(extId) else { continue }
            guard let cin = b24.arrival.flatMap({ df.date(from: $0) }),
                  let cout = b24.departure.flatMap({ df.date(from: $0) }) else { continue }

            // Resolve homeId from propertyId
            let resolvedHomeId = b24.propertyId.flatMap { propIdToHomeId[$0] } ?? home.id

            let booking = Booking(
                guestName: b24.guestFullName,
                guestEmail: b24.email ?? "",
                guestPhone: b24.phone ?? "",
                platform: b24.platformKey,
                homeId: resolvedHomeId,
                externalId: extId,
                checkIn: cin, checkOut: cout,
                totalAmount: Int((b24.price ?? 0) * 100),
                status: b24.status == "cancelled" ? "cancelled" : "upcoming"
            )
            context.insert(booking)
            imported += 1

            // Push notification for new booking
            // Find correct home name for notification
            let homeName = allHomes.first { $0.id == resolvedHomeId }?.name ?? home.name
            sendNewBookingNotification(
                guestName: b24.guestFullName,
                homeName: homeName,
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
