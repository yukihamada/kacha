import SwiftUI
import SwiftData

@main
struct KachaApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: Home.self, Booking.self, SmartDevice.self, DeviceIntegration.self, ShareRecord.self,
                configurations: ModelConfiguration()
            )
        } catch {
            fatalError("SwiftData container init failed: \(error)")
        }
        migrateIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(container)
                .preferredColorScheme(.dark)
                .onAppear {
                    #if DEBUG
                    SeedData.insert(into: container.mainContext)
                    #endif
                    Task { await NotificationManager.shared.requestPermission() }
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL {
                        handleDeepLink(url)
                    }
                }
        }
    }

    // MARK: - Deep Link
    // Universal Link: https://kacha.pasha.run/join?t=TOKEN#ENCRYPTION_KEY
    // Custom scheme:  kacha://join?t=TOKEN#ENCRYPTION_KEY
    // Legacy:         kacha://join?d=BASE64

    private func handleDeepLink(_ url: URL) {
        let isUniversalLink = url.scheme == "https" && url.host == "kacha.pasha.run" && url.path == "/join"
        let isCustomScheme = url.scheme == "kacha" && url.host == "join"
        guard isUniversalLink || isCustomScheme else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        // New E2E format
        if let token = components?.queryItems?.first(where: { $0.name == "t" })?.value,
           let fragment = url.fragment?.removingPercentEncoding, !fragment.isEmpty {
            Task {
                do {
                    let shareData = try await ShareClient.fetchShare(token: token, encryptionKey: fragment)
                    await MainActor.run { importHome(from: shareData) }
                } catch {
                    print("Share fetch failed: \(error)")
                }
            }
            return
        }

        // Legacy inline format (backward compat)
        if let dParam = components?.queryItems?.first(where: { $0.name == "d" })?.value,
           let decoded = dParam.removingPercentEncoding,
           let data = Data(base64Encoded: decoded),
           let shareData = try? JSONDecoder().decode(HomeShareData.self, from: data) {
            importHome(from: shareData)
        }
    }

    private func importHome(from shareData: HomeShareData) {
        let context = container.mainContext
        let existing = (try? context.fetch(FetchDescriptor<Home>())) ?? []
        guard !existing.contains(where: { $0.name == shareData.name }) else { return }

        let home = Home(name: shareData.name, sortOrder: existing.count)
        home.address           = shareData.address
        home.switchBotToken    = shareData.switchBotToken
        home.switchBotSecret   = shareData.switchBotSecret
        home.hueBridgeIP       = shareData.hueBridgeIP
        home.hueUsername       = shareData.hueUsername
        home.sesameApiKey      = shareData.sesameApiKey
        home.sesameDeviceUUIDs = shareData.sesameDeviceUUIDs
        home.qrioApiKey        = shareData.qrioApiKey
        home.qrioDeviceIds     = shareData.qrioDeviceIds
        home.doorCode          = shareData.doorCode
        home.wifiPassword      = shareData.wifiPassword
        context.insert(home)
        try? context.save()

        UserDefaults.standard.set(home.id, forKey: "activeHomeId")
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        home.syncToAppStorage()
    }

    // MARK: - Migration

    /// AppStorageに既存設定があれば最初のHomeオブジェクトとして移行
    private func migrateIfNeeded() {
        let context = container.mainContext
        let existing = (try? context.fetch(FetchDescriptor<Home>())) ?? []
        guard existing.isEmpty else { return }

        let d = UserDefaults.standard
        let name = d.string(forKey: "facilityName") ?? ""
        let home = Home(name: name.isEmpty ? "私の家" : name)
        home.address         = d.string(forKey: "facilityAddress") ?? ""
        home.doorCode        = d.string(forKey: "facilityDoorCode") ?? ""
        home.wifiPassword    = d.string(forKey: "facilityWifiPassword") ?? ""
        home.switchBotToken  = d.string(forKey: "switchBotToken") ?? ""
        home.switchBotSecret = d.string(forKey: "switchBotSecret") ?? ""
        home.hueBridgeIP     = d.string(forKey: "hueBridgeIP") ?? ""
        home.hueUsername     = d.string(forKey: "hueUsername") ?? ""
        home.airbnbICalURL   = d.string(forKey: "airbnbICalURL") ?? ""
        home.jalanICalURL    = d.string(forKey: "jalanICalURL") ?? ""
        home.minpakuNumber   = d.string(forKey: "minpakuNumber") ?? ""
        home.minpakuNights   = d.integer(forKey: "minpakuNights")
        context.insert(home)
        try? context.save()
        d.set(home.id, forKey: "activeHomeId")
    }
}

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Query private var homes: [Home]

    var body: some View {
        if hasCompletedOnboarding && !homes.isEmpty {
            ContentView()
        } else {
            OnboardingView()
        }
    }
}
