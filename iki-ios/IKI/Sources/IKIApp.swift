import SwiftUI
import SwiftData
import UserNotifications

@main
struct IKIApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [IKIDevice.self])
    }

    init() {
        requestNotificationPermissions()
    }

    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge, .criticalAlert]
        ) { granted, error in
            #if DEBUG
            if granted {
                print("[IKIApp] 通知許可: 承認済み")
            } else if let error {
                print("[IKIApp] 通知許可エラー: \(error.localizedDescription)")
            }
            #endif
        }
    }
}
