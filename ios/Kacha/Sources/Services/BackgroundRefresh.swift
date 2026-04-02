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
            // SwiftData ModelContext must be accessed on MainActor
            let (context, homes) = await MainActor.run {
                let ctx = ModelContext(container)
                let h = (try? ctx.fetch(FetchDescriptor<Home>())) ?? []
                return (ctx, h)
            }

            var polledTokens = Set<String>()

            for home in homes where !home.beds24RefreshToken.isEmpty {
                if !polledTokens.contains(home.beds24RefreshToken) {
                    polledTokens.insert(home.beds24RefreshToken)
                    let _ = await BookingPoller.autoDetectProperties(context: context, home: home)
                    let refreshedHomes = await MainActor.run {
                        (try? context.fetch(FetchDescriptor<Home>())) ?? homes
                    }
                    let _ = await BookingPoller.pollAndNotify(context: context, home: home, allHomes: refreshedHomes)
                    // Check for new guest messages
                    let _ = await MessagePoller.pollNewMessages(context: context, home: home, allHomes: refreshedHomes)
                }
            }

            await MainActor.run { KeychainBackup.backup(context: context) }
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
