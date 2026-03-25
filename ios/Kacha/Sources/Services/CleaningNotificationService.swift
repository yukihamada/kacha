import Foundation
import UserNotifications

// MARK: - CleaningNotificationService
// チェックアウト検知 → 清掃スタッフへ通知
// 清掃完了 → オーナーへ通知

struct CleaningNotificationService {

    // MARK: - Permission

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    // MARK: - Checkout detected → notify cleaner

    /// チェックアウト時刻になったら清掃スタッフへ通知をスケジュール
    /// - Parameters:
    ///   - homeName: 物件名
    ///   - checkoutTime: チェックアウト予定時刻
    ///   - identifier: 一意な識別子（予約IDなど）
    static func scheduleCheckoutNotification(
        homeName: String,
        checkoutTime: Date,
        identifier: String
    ) {
        let content = UNMutableNotificationContent()
        content.title = "清掃依頼 — \(homeName)"
        content.body = "チェックアウトが完了しました。清掃を開始してください。"
        content.sound = .default
        content.categoryIdentifier = "CLEANING_REQUEST"
        content.userInfo = ["homeId": identifier, "type": "checkout"]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: checkoutTime
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: "checkout_\(identifier)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("[CleaningNotification] schedule error: \(error)") }
        }
    }

    /// スケジュール済み通知をキャンセル（予約変更時）
    static func cancelCheckoutNotification(identifier: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["checkout_\(identifier)"])
    }

    // MARK: - Cleaning started → notify owner

    static func notifyCleaningStarted(homeName: String, cleanerName: String) {
        let content = UNMutableNotificationContent()
        content.title = "清掃開始 — \(homeName)"
        content.body = "\(cleanerName) が清掃を開始しました。"
        content.sound = .default
        content.categoryIdentifier = "CLEANING_STATUS"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "cleaning_start_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Cleaning completed → notify owner

    /// 清掃完了時にオーナーへ通知
    /// - Parameters:
    ///   - report: 完了した清掃報告
    static func notifyCleaningCompleted(report: CleaningReport) {
        let content = UNMutableNotificationContent()
        content.title = "清掃完了 — \(report.homeName)"

        var body = "\(report.cleanerName) が清掃を完了しました。所要時間: \(report.durationLabel)"
        if !report.suppliesNeeded.isEmpty {
            body += "\n備品補充が必要: \(report.suppliesNeeded)"
        }
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "CLEANING_COMPLETE"
        content.userInfo = [
            "reportId": report.id,
            "homeId": report.homeId,
            "type": "cleaning_complete"
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "cleaning_complete_\(report.id)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("[CleaningNotification] complete error: \(error)") }
        }
    }

    // MARK: - Supplies needed reminder

    /// 備品が必要な場合、翌朝9時にリマインダーをセット
    static func scheduleSuppliesReminder(homeName: String, supplies: String, reportId: String) {
        guard !supplies.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = "備品補充リマインダー — \(homeName)"
        content.body = "補充が必要: \(supplies)"
        content.sound = .default

        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.day? += 1
        components.hour = 9
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: "supplies_\(reportId)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Register notification categories (call once at app launch)

    static func registerCategories() {
        let startAction = UNNotificationAction(
            identifier: "START_CLEANING",
            title: "清掃を開始",
            options: .foreground
        )
        let cleaningCategory = UNNotificationCategory(
            identifier: "CLEANING_REQUEST",
            actions: [startAction],
            intentIdentifiers: [],
            options: []
        )

        let viewAction = UNNotificationAction(
            identifier: "VIEW_REPORT",
            title: "報告を見る",
            options: .foreground
        )
        let completeCategory = UNNotificationCategory(
            identifier: "CLEANING_COMPLETE",
            actions: [viewAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            cleaningCategory,
            completeCategory
        ])
    }
}
