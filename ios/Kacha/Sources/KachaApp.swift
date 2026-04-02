import SwiftUI
import SwiftData
import UIKit
import UserNotifications

// MARK: - AppDelegate for APNs token

class KachaAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// APNsデバイストークン（サーバー登録用）
    static var apnsToken: String?

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Self.apnsToken = token
        #if DEBUG
        print("[APNs] Device token: \(token)")
        #endif
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        print("[APNs] Registration failed: \(error)")
        #endif
    }

    // フォアグラウンドで通知を表示
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .badge, .sound]
    }
}

@main
struct KachaApp: App {
    @UIApplicationDelegateAdaptor(KachaAppDelegate.self) var appDelegate
    let container: ModelContainer

    init() {
        let models: [any PersistentModel.Type] = [
            Home.self, Booking.self, SmartDevice.self, DeviceIntegration.self, ShareRecord.self,
            ChecklistItem.self, UtilityRecord.self, MaintenanceTask.self, NearbyPlace.self,
            ActivityLog.self, HouseManual.self, SecureItem.self, PropertyExpense.self,
            GuestReview.self, SentMessage.self,
        ]
        do {
            container = try ModelContainer(for: Schema(models), configurations: ModelConfiguration())
        } catch {
            // Schema changed — delete old DB and retry (Keychain backup will restore data)
            let dbURL = URL.applicationSupportDirectory.appending(path: "default.store")
            try? FileManager.default.removeItem(at: dbURL)
            try? FileManager.default.removeItem(at: dbURL.appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: dbURL.appendingPathExtension("shm"))
            do {
                container = try ModelContainer(for: Schema(models), configurations: ModelConfiguration())
            } catch {
                // In-memory fallback to avoid crash (data will not persist)
                #if DEBUG
                print("[Kacha] Falling back to in-memory ModelContainer: \(error)")
                #endif
                let inMemoryConfig = ModelConfiguration(isStoredInMemoryOnly: true)
                // swiftlint:disable:next force_try
                container = try! ModelContainer(for: Schema(models), configurations: inMemoryConfig)
            }
        }
        migrateIfNeeded()
        BackgroundRefresh.register(container: container)
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(container)
                .preferredColorScheme(.dark)
                .onAppear {
                    // Restore from Keychain if fresh install
                    let restored = KeychainBackup.restoreIfNeeded(context: container.mainContext)
                    #if DEBUG
                    if restored { print("[Kacha] Restored from Keychain backup") }
                    #endif

                    // SeedData は初回のみ（既存データがある場合はスキップ）
                    // #if DEBUG
                    // SeedData.insert(into: container.mainContext)
                    // #endif
                    #if !targetEnvironment(simulator)
                    Task { await NotificationManager.shared.requestPermission() }
                    // リモート通知登録（APNsトークン取得）
                    UNUserNotificationCenter.current().delegate = appDelegate
                    UIApplication.shared.registerForRemoteNotifications()
                    #endif
                    GeofenceManager.registerNotificationCategory()

                    // Backup to Keychain on every launch (skip if just restored to avoid overwriting)
                    if !restored {
                        KeychainBackup.backup(context: container.mainContext)
                    }

                    // Schedule background refresh (lightweight, no delay)
                    BackgroundRefresh.scheduleNext()
                }
                .task {
                    // Defer heavy network operations to not block UI launch
                    try? await Task.sleep(for: .seconds(1.5))

                    var homes = (try? container.mainContext.fetch(FetchDescriptor<Home>())) ?? []

                    // Auto-detect new Beds24 properties & enable inquiry import
                    var checkedTokens = Set<String>()
                    for home in homes where !home.beds24RefreshToken.isEmpty {
                        if !checkedTokens.contains(home.beds24RefreshToken) {
                            checkedTokens.insert(home.beds24RefreshToken)
                            let created = await BookingPoller.autoDetectProperties(context: container.mainContext, home: home)
                            if created > 0 {
                                homes = (try? container.mainContext.fetch(FetchDescriptor<Home>())) ?? []
                            }

                            // Enable Airbnb inquiry import (once per token)
                            let inquiryKey = "beds24_inquiry_enabled_\(home.beds24RefreshToken.prefix(16))"
                            if !UserDefaults.standard.bool(forKey: inquiryKey) {
                                do {
                                    let token = try await Beds24Client.shared.getToken(refreshToken: home.beds24RefreshToken)
                                    let props = try await Beds24Client.shared.fetchProperties(token: token, includePhotos: false)
                                    for prop in props {
                                        if let propId = prop["id"] as? Int {
                                            try await Beds24Client.shared.enableAirbnbInquiryImport(propertyId: propId, token: token)
                                        }
                                    }
                                    UserDefaults.standard.set(true, forKey: inquiryKey)
                                    #if DEBUG
                                    print("[Beds24] Airbnb inquiry import enabled for \(props.count) properties")
                                    #endif
                                } catch {
                                    #if DEBUG
                                    print("[Beds24] Failed to enable inquiry import: \(error)")
                                    #endif
                                }
                            }
                        }
                    }

                    // Poll Beds24 once per unique refreshToken
                    var polledTokens = Set<String>()
                    for home in homes {
                        if !home.beds24RefreshToken.isEmpty && !polledTokens.contains(home.beds24RefreshToken) {
                            polledTokens.insert(home.beds24RefreshToken)
                            let _ = await BookingPoller.pollAndNotify(context: container.mainContext, home: home, allHomes: homes)
                            // Initialize message tracking for first run, then poll for new messages
                            await MessagePoller.initializeLastSeen(context: container.mainContext, home: home, allHomes: homes)
                            let _ = await MessagePoller.pollNewMessages(context: container.mainContext, home: home, allHomes: homes)
                        }
                        GuestMessenger.scheduleMessages(context: container.mainContext, home: home)
                        CleanerNotifier.scheduleCleaningNotifications(context: container.mainContext, home: home)
                    }

                    // APNs registration
                    if let apnsToken = KachaAppDelegate.apnsToken {
                        for home in homes where !home.beds24RefreshToken.isEmpty {
                            await Beds24PushRegistrar.register(
                                userId: home.id, refreshToken: home.beds24RefreshToken, pushToken: apnsToken
                            )
                        }
                    }
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                KeychainBackup.backup(context: container.mainContext)
            }
        }
    }

    // MARK: - Deep Link (E2E encrypted only)
    // Universal Link: https://kagi.pasha.run/join?t=TOKEN#ENCRYPTION_KEY
    // Custom scheme:  kacha://join?t=TOKEN#ENCRYPTION_KEY

    private func handleDeepLink(_ url: URL) {
        let isUniversalLink = url.scheme == "https" && url.host == "kagi.pasha.run" && url.path == "/join"
        let isCustomScheme = url.scheme == "kacha" && url.host == "join"
        guard isUniversalLink || isCustomScheme else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        guard let token = components?.queryItems?.first(where: { $0.name == "t" })?.value,
              let fragment = url.fragment?.removingPercentEncoding, !fragment.isEmpty else { return }

        Task {
            do {
                let shareData = try await ShareClient.fetchShare(token: token, encryptionKey: fragment)
                await MainActor.run { importHome(from: shareData) }
            } catch {
                #if DEBUG
                print("Share fetch failed: \(error)")
                #endif
            }
        }
    }

    private func importHome(from shareData: HomeShareData) {
        let context = container.mainContext
        let existing = (try? context.fetch(FetchDescriptor<Home>())) ?? []
        guard !existing.contains(where: { $0.name == shareData.name }) else { return }

        let home = Home(name: shareData.name, sortOrder: existing.count)
        home.address           = shareData.address
        home.sharedRole        = shareData.role  // Save the shared role
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
        // Admin-only: Beds24 credentials
        if shareData.role == "admin" {
            home.beds24ApiKey  = shareData.beds24ApiKey ?? ""
            home.beds24RefreshToken = shareData.beds24RefreshToken ?? ""
            home.businessType  = "minpaku"
        }
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

        // Clean up legacy secret keys from UserDefaults
        for key in ["switchBotToken", "switchBotSecret", "facilityDoorCode", "facilityWifiPassword"] {
            d.removeObject(forKey: key)
        }
    }
}

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Query private var homes: [Home]

    var body: some View {
        if hasCompletedOnboarding || !homes.isEmpty {
            ContentView()
                .onAppear {
                    // Auto-complete onboarding if homes exist (e.g. restored from Keychain)
                    if !homes.isEmpty && !hasCompletedOnboarding {
                        hasCompletedOnboarding = true
                    }
                }
        } else {
            OnboardingView()
        }
    }
}
