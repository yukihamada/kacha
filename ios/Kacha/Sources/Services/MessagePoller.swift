import Foundation
import SwiftData
import UserNotifications

// MARK: - Message Poller
// Beds24の全アクティブ予約のメッセージをポーリングし、
// 新着ゲストメッセージがあればプッシュ通知を送る

struct MessagePoller {

    /// UserDefaultsに保存する「最後に確認したメッセージID」のキー
    private static func lastSeenKey(bookingExtId: String) -> String {
        "lastSeenMsgId_\(bookingExtId)"
    }

    /// 全アクティブ・upcoming予約のメッセージをチェックし、新着があれば通知
    static func pollNewMessages(context: ModelContext, home: Home, allHomes: [Home] = []) async -> Int {
        guard !home.beds24RefreshToken.isEmpty else { return 0 }
        guard let token = try? await Beds24Client.shared.getToken(refreshToken: home.beds24RefreshToken) else { return 0 }

        // アクティブ・upcoming・confirmed の予約を取得
        let homes = allHomes.isEmpty ? [home] : allHomes
        let homeIds = Set(homes.map(\.id))
        let allBookings = (try? context.fetch(FetchDescriptor<Booking>())) ?? []
        let activeBookings = allBookings.filter { booking in
            homeIds.contains(booking.homeId)
            && booking.externalId.hasPrefix("beds24-")
            && (booking.status == "active" || booking.status == "upcoming" || booking.status == "confirmed")
        }

        var newMessageCount = 0

        for booking in activeBookings {
            let bookId = extractBookId(from: booking.externalId)
            guard bookId > 0 else { continue }

            do {
                let raw = try await Beds24Client.shared.getBookingMessages(bookingId: bookId, token: token)
                let guestMessages = parseGuestMessages(raw)

                guard let latest = guestMessages.last else { continue }

                let lastSeenId = UserDefaults.standard.string(forKey: lastSeenKey(bookingExtId: booking.externalId)) ?? ""

                if latest.id != lastSeenId && !lastSeenId.isEmpty {
                    // New message(s) since last check
                    let newMessages = guestMessages.filter { msg in
                        msg.timestamp > (guestMessages.first { $0.id == lastSeenId }?.timestamp ?? .distantPast)
                    }

                    for msg in newMessages {
                        sendMessageNotification(
                            guestName: booking.guestName,
                            homeName: homes.first { $0.id == booking.homeId }?.name ?? home.name,
                            messagePreview: String(msg.text.prefix(100)),
                            bookingId: booking.id
                        )
                        newMessageCount += 1
                    }
                }

                // Update last seen
                UserDefaults.standard.set(latest.id, forKey: lastSeenKey(bookingExtId: booking.externalId))
            } catch {
                #if DEBUG
                print("[MessagePoller] Error checking messages for \(booking.externalId): \(error)")
                #endif
            }

            // Small delay between API calls to avoid rate limiting
            try? await Task.sleep(for: .milliseconds(300))
        }

        return newMessageCount
    }

    /// 初回セットアップ: 既存メッセージのIDを記録して、次回から差分検知
    static func initializeLastSeen(context: ModelContext, home: Home, allHomes: [Home] = []) async {
        guard !home.beds24RefreshToken.isEmpty else { return }
        guard let token = try? await Beds24Client.shared.getToken(refreshToken: home.beds24RefreshToken) else { return }

        let homes = allHomes.isEmpty ? [home] : allHomes
        let homeIds = Set(homes.map(\.id))
        let allBookings = (try? context.fetch(FetchDescriptor<Booking>())) ?? []
        let activeBookings = allBookings.filter { booking in
            homeIds.contains(booking.homeId)
            && booking.externalId.hasPrefix("beds24-")
            && (booking.status == "active" || booking.status == "upcoming" || booking.status == "confirmed")
        }

        for booking in activeBookings {
            let key = lastSeenKey(bookingExtId: booking.externalId)
            // Only initialize if not already set
            guard UserDefaults.standard.string(forKey: key) == nil else { continue }

            let bookId = extractBookId(from: booking.externalId)
            guard bookId > 0 else { continue }

            do {
                let raw = try await Beds24Client.shared.getBookingMessages(bookingId: bookId, token: token)
                let guestMessages = parseGuestMessages(raw)
                if let latest = guestMessages.last {
                    UserDefaults.standard.set(latest.id, forKey: key)
                } else {
                    // No messages yet — mark as initialized with empty marker
                    UserDefaults.standard.set("_init_", forKey: key)
                }
            } catch {
                #if DEBUG
                print("[MessagePoller] Init error for \(booking.externalId): \(error)")
                #endif
            }

            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    // MARK: - Helpers

    private static func extractBookId(from externalId: String) -> Int {
        let raw = externalId.hasPrefix("beds24-")
            ? String(externalId.dropFirst(7))
            : externalId
        return Int(raw) ?? 0
    }

    private struct ParsedMessage {
        let id: String
        let text: String
        let timestamp: Date
    }

    private static func parseGuestMessages(_ raw: [[String: Any]]) -> [ParsedMessage] {
        var results: [ParsedMessage] = []

        for (index, dict) in raw.enumerated() {
            // Only guest messages (received, not sent)
            let isGuest: Bool
            if let from = dict["from"] as? String {
                isGuest = from.lowercased() == "guest"
            } else if let direction = dict["direction"] as? String {
                isGuest = direction.lowercased() == "in" || direction.lowercased() == "received"
            } else if let type = dict["type"] as? String {
                isGuest = type.lowercased() == "received"
            } else {
                isGuest = false
            }

            guard isGuest else { continue }

            let text = (dict["message"] as? String)
                ?? (dict["body"] as? String)
                ?? (dict["text"] as? String)
                ?? ""

            var timestamp = Date()
            if let dateStr = (dict["date"] as? String) ?? (dict["dateTime"] as? String) ?? (dict["created"] as? String) {
                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let parsed = isoFormatter.date(from: dateStr) {
                    timestamp = parsed
                } else {
                    isoFormatter.formatOptions = [.withInternetDateTime]
                    if let parsed = isoFormatter.date(from: dateStr) {
                        timestamp = parsed
                    } else {
                        let df = DateFormatter()
                        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
                        if let parsed = df.date(from: dateStr) {
                            timestamp = parsed
                        }
                    }
                }
            }

            let id = (dict["id"] as? Int).map(String.init)
                ?? (dict["id"] as? String)
                ?? "\(index)-\(text.prefix(20).hashValue)"

            results.append(ParsedMessage(id: id, text: text, timestamp: timestamp))
        }

        return results.sorted { $0.timestamp < $1.timestamp }
    }

    private static func sendMessageNotification(guestName: String, homeName: String, messagePreview: String, bookingId: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(guestName) — \(homeName)"
        content.body = messagePreview
        content.sound = .default
        content.categoryIdentifier = "GUEST_MESSAGE"
        content.userInfo = [
            "type": "guest_message_received",
            "bookingId": bookingId
        ]

        let request = UNNotificationRequest(
            identifier: "guest-msg-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
