import Foundation
import SwiftData
import UserNotifications

// MARK: - Guest Auto-Messenger
// チェックイン前日にゲストにWiFi/ドアコード等を自動送信
// デフォルトOFF — 設定で有効化

struct GuestMessenger {

    /// チェックイン前日の予約を見つけて通知をスケジュール
    static func scheduleMessages(context: ModelContext, home: Home) {
        guard UserDefaults.standard.bool(forKey: "autoGuestMessage_\(home.id)") else { return }

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let startOfTomorrow = Calendar.current.startOfDay(for: tomorrow)
        let endOfTomorrow = Calendar.current.date(byAdding: .day, value: 1, to: startOfTomorrow) ?? tomorrow
        let homeId = home.id

        var descriptor = FetchDescriptor<Booking>()
        descriptor.predicate = #Predicate<Booking> { booking in
            booking.homeId == homeId &&
            booking.status == "upcoming" &&
            booking.checkIn >= startOfTomorrow &&
            booking.checkIn < endOfTomorrow
        }
        let tomorrowBookings = (try? context.fetch(descriptor)) ?? []

        for booking in tomorrowBookings {
            let message = buildMessage(home: home, booking: booking)

            // Local notification to owner to review/send
            let content = UNMutableNotificationContent()
            content.title = "ゲストメッセージ準備完了"
            content.body = "\(booking.guestName)様へのチェックイン案内を確認してください"
            content.sound = .default
            content.userInfo = [
                "type": "guest_message",
                "bookingId": booking.id,
                "message": message
            ]

            // Schedule for 18:00 today
            var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            components.hour = 18
            components.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: "guest-msg-\(booking.id)",
                content: content,
                trigger: trigger
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    static func buildMessage(home: Home, booking: Booking) -> String {
        var lines: [String] = []
        lines.append("\(booking.guestName)様")
        lines.append("")
        lines.append("明日のチェックインのご案内です。")
        lines.append("")
        lines.append("【\(home.name)】")
        if !home.address.isEmpty {
            lines.append("住所: \(home.address)")
        }
        lines.append("")
        if !home.doorCode.isEmpty {
            lines.append("ドアコード: \(home.doorCode)")
        }
        if !home.wifiPassword.isEmpty {
            lines.append("Wi-Fi: \(home.wifiPassword)")
        }
        if !home.autolockRoomNumber.isEmpty {
            lines.append("部屋番号: \(home.autolockRoomNumber)")
        }
        lines.append("")
        lines.append("チェックイン: \(booking.checkIn.formatted(date: .abbreviated, time: .omitted))")
        lines.append("")
        lines.append("何かご不明な点がございましたらお気軽にご連絡ください。")
        lines.append("お待ちしております。")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Cleaner Notifier
// チェックアウト時に清掃スタッフに通知
// デフォルトOFF

struct CleanerNotifier {

    static func scheduleCleaningNotifications(context: ModelContext, home: Home) {
        guard UserDefaults.standard.bool(forKey: "autoCleanerNotify_\(home.id)") else { return }

        let today = Date()
        let startOfToday = Calendar.current.startOfDay(for: today)
        let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: startOfToday) ?? today
        let homeId = home.id

        var descriptor = FetchDescriptor<Booking>()
        descriptor.predicate = #Predicate<Booking> { booking in
            booking.homeId == homeId &&
            booking.status == "active" &&
            booking.checkOut >= startOfToday &&
            booking.checkOut < endOfToday
        }
        let todayCheckouts = (try? context.fetch(descriptor)) ?? []

        for booking in todayCheckouts {
            let content = UNMutableNotificationContent()
            content.title = "清掃依頼 — \(home.name)"
            content.body = "\(booking.guestName)様がチェックアウトしました。清掃をお願いします。"
            content.sound = .default
            content.userInfo = ["type": "cleaning_request", "homeId": home.id]

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: booking.checkOut)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: "clean-\(booking.id)",
                content: content,
                trigger: trigger
            )
            UNUserNotificationCenter.current().add(request)
        }
    }
}
