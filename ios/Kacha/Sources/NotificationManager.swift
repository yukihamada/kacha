import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    func requestPermission() async {
        try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    // MARK: - Check-in reminder (1 hour before)

    func scheduleCheckInReminder(booking: Booking) {
        guard let triggerDate = Calendar.current.date(byAdding: .hour, value: -1, to: booking.checkIn),
              triggerDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "チェックイン1時間前"
        content.body = "\(booking.guestName)様のチェックイン予定です。スマートロックを確認してください。"
        content.sound = .default
        content.userInfo = ["bookingId": booking.id, "type": "checkIn"]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "checkin-\(booking.id)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Check-out reminder (30 min after check-out)

    func scheduleCheckOutReminder(booking: Booking) {
        guard let triggerDate = Calendar.current.date(byAdding: .minute, value: 30, to: booking.checkOut),
              triggerDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "チェックアウト確認"
        content.body = "\(booking.guestName)様がチェックアウトされました。鍵の確認をお願いします。"
        content.sound = .default
        content.userInfo = ["bookingId": booking.id, "type": "checkOut"]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "checkout-\(booking.id)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Cleaning reminder (right after check-out)

    func scheduleCleaningReminder(booking: Booking) {
        guard booking.checkOut > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "清掃リマインダー"
        content.body = "\(booking.guestName)様がチェックアウトされました。清掃を開始してください。"
        content.sound = .default
        content.userInfo = ["bookingId": booking.id, "type": "cleaning"]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: booking.checkOut)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "cleaning-\(booking.id)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Cancel all notifications for a booking

    func cancelNotifications(bookingId: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
            "checkin-\(bookingId)",
            "checkout-\(bookingId)",
            "cleaning-\(bookingId)"
        ])
    }
}
