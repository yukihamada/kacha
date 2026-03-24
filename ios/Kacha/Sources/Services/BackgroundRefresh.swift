import BackgroundTasks
import SwiftData
import UserNotifications

struct BackgroundRefresh {
    static let taskIdentifier = "com.enablerdao.kacha.refresh"

    static func register(container: ModelContainer) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            handleRefresh(refreshTask, container: container)
        }
    }

    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if DEBUG
            print("[BGRefresh] Failed to schedule: \(error)")
            #endif
        }
    }

    private static func handleRefresh(_ task: BGAppRefreshTask, container: ModelContainer) {
        scheduleNext()

        let workTask = Task {
            let context = ModelContext(container)
            let homes = (try? context.fetch(FetchDescriptor<Home>())) ?? []

            var totalNew = 0
            var polledTokens = Set<String>()

            for home in homes where !home.beds24ICalURL.isEmpty {
                if !polledTokens.contains(home.beds24ICalURL) {
                    polledTokens.insert(home.beds24ICalURL)
                    let _ = await BookingPoller.autoDetectProperties(context: context, home: home)
                    let refreshedHomes = (try? context.fetch(FetchDescriptor<Home>())) ?? homes
                    totalNew += await BookingPoller.pollAndNotify(context: context, home: home, allHomes: refreshedHomes)
                }
            }

            KeychainBackup.backup(context: context)
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
