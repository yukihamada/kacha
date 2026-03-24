import BackgroundTasks
import SwiftData
import UserNotifications

// MARK: - Background Refresh
// アプリが閉じていてもBeds24をポーリングして新規予約を通知

struct BackgroundRefresh {
    static let taskIdentifier = "com.enablerdao.kacha.refresh"

    /// BGTaskSchedulerにタスクを登録（AppDelegateまたはApp.init()で呼ぶ）
    static func register(container: ModelContainer) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            handleRefresh(refreshTask, container: container)
        }
    }

    /// 次回のバックグラウンドフェッチをスケジュール
    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60) // 30分後〜
        do {
            try BGTaskScheduler.shared.submit(request)
            print("[BGRefresh] Scheduled next refresh")
        } catch {
            print("[BGRefresh] Failed to schedule: \(error)")
        }
    }

    private static func handleRefresh(_ task: BGAppRefreshTask, container: ModelContainer) {
        // Schedule next immediately
        scheduleNext()

        let workTask = Task {
            let context = ModelContext(container)
            let homes = (try? context.fetch(FetchDescriptor<Home>())) ?? []

            var totalNew = 0
            var polledTokens = Set<String>()

            for home in homes where !home.beds24ICalURL.isEmpty {
                if !polledTokens.contains(home.beds24ICalURL) {
                    polledTokens.insert(home.beds24ICalURL)
                    // Auto-detect new properties
                    let _ = await BookingPoller.autoDetectProperties(context: context, home: home)
                    // Poll bookings
                    let refreshedHomes = (try? context.fetch(FetchDescriptor<Home>())) ?? homes
                    totalNew += await BookingPoller.pollAndNotify(context: context, home: home, allHomes: refreshedHomes)
                }
            }

            // Backup to Keychain
            KeychainBackup.backup(context: context)

            print("[BGRefresh] Completed: \(totalNew) new bookings")
        }

        task.expirationHandler = {
            workTask.cancel()
        }

        Task {
            await workTask.value
            task.setTaskCompleted(success: true)
        }
    }
}
