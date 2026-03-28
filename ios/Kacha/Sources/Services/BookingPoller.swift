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

    /// Beds24から最新予約を取得し、新規追加・既存更新・削除同期を行う
    /// allHomes: propertyIdからhomeIdを解決するために全ホームを渡す
    static func pollAndNotify(context: ModelContext, home: Home, allHomes: [Home] = []) async -> Int {
        guard !home.beds24RefreshToken.isEmpty else { return 0 }
        guard let token = try? await Beds24Client.shared.getToken(refreshToken: home.beds24RefreshToken) else { return 0 }
        guard let b24Bookings = try? await Beds24Client.shared.fetchBookings(token: token) else { return 0 }

        let allBookings: [Booking] = {
            // Fetch all bookings then filter in-memory (Set.contains in #Predicate can crash on iOS 17.0-17.3)
            let homeIds = Set((allHomes.isEmpty ? [home] : allHomes).map(\.id))
            let all = (try? context.fetch(FetchDescriptor<Booking>())) ?? []
            return all.filter { homeIds.contains($0.homeId) }
        }()
        let existingByExtId: [String: Booking] = Dictionary(
            allBookings.compactMap { b in b.externalId.isEmpty ? nil : (b.externalId, b) },
            uniquingKeysWith: { _, last in last }
        )
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

        // Beds24側の予約IDセット（削除検知用）
        var remoteExtIds = Set<String>()

        for b24 in b24Bookings {
            let extId = "beds24-\(b24.effectiveId)"
            remoteExtIds.insert(extId)

            guard let cin = b24.arrival.flatMap({ df.date(from: $0) }),
                  let cout = b24.departure.flatMap({ df.date(from: $0) }) else { continue }

            let resolvedHomeId = b24.propertyId.flatMap { propIdToHomeId[$0] } ?? home.id
            let newStatus = Booking.mapBeds24Status(b24.status, checkIn: cin, checkOut: cout)
            let newAmount = Int(b24.price ?? 0)

            if let existing = existingByExtId[extId] {
                // --- 既存予約の更新 ---
                var changed = false
                if existing.status != newStatus { existing.status = newStatus; changed = true }
                if existing.totalAmount != newAmount { existing.totalAmount = newAmount; changed = true }
                if existing.guestName != b24.guestFullName { existing.guestName = b24.guestFullName; changed = true }
                if existing.guestEmail != (b24.email ?? "") { existing.guestEmail = b24.email ?? ""; changed = true }
                if existing.guestPhone != (b24.phone ?? "") { existing.guestPhone = b24.phone ?? ""; changed = true }
                if existing.checkIn != cin { existing.checkIn = cin; changed = true }
                if existing.checkOut != cout { existing.checkOut = cout; changed = true }
                if let na = b24.numAdult, existing.numAdults != na { existing.numAdults = na; changed = true }
                if let nc = b24.numChild, existing.numChildren != nc { existing.numChildren = nc; changed = true }
                if let rid = b24.roomId, existing.roomId != String(rid) { existing.roomId = String(rid); changed = true }
                if let com = b24.commission, existing.commission != Int(com) { existing.commission = Int(com); changed = true }
                if let notes = b24.comments, existing.guestNotes != notes { existing.guestNotes = notes; changed = true }
                #if DEBUG
                if changed { print("[Beds24] Updated booking \(extId)") }
                #endif
            } else {
                // --- 新規予約 ---
                let booking = Booking(
                    guestName: b24.guestFullName,
                    guestEmail: b24.email ?? "",
                    guestPhone: b24.phone ?? "",
                    platform: b24.platformKey,
                    homeId: resolvedHomeId,
                    externalId: extId,
                    checkIn: cin, checkOut: cout,
                    totalAmount: newAmount,
                    numAdults: b24.numAdult ?? 1,
                    numChildren: b24.numChild ?? 0,
                    roomId: b24.roomId.map { String($0) } ?? "",
                    commission: Int(b24.commission ?? 0),
                    guestNotes: b24.comments ?? "",
                    status: newStatus
                )
                context.insert(booking)
                imported += 1

                let homeName = allHomes.first { $0.id == resolvedHomeId }?.name ?? home.name
                sendNewBookingNotification(
                    guestName: b24.guestFullName,
                    homeName: homeName,
                    checkIn: b24.arrival ?? "",
                    platform: b24.platformKey
                )
            }
        }

        // --- 削除同期: Beds24に存在しない予約を削除 ---
        let homeIds = Set(propIdToHomeId.values)
        for booking in allBookings {
            guard booking.externalId.hasPrefix("beds24-"),
                  homeIds.contains(booking.homeId) || booking.homeId == home.id,
                  !remoteExtIds.contains(booking.externalId) else { continue }
            #if DEBUG
            print("[Beds24] Removing deleted booking \(booking.externalId)")
            #endif
            context.delete(booking)
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
