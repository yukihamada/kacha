import SwiftUI

@main
struct KachaWatchApp: App {

    @StateObject private var connectivityManager = WatchConnectivityManager.shared

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environmentObject(connectivityManager)
        }
    }
}
