import Foundation
import Security
import SwiftData
import WidgetKit

/// Syncs the active home's data to the shared App Group UserDefaults so the widget can read it.
/// Call this from KachaApp.onAppear and whenever lock state or booking data changes.
///
/// セキュリティ方針:
/// - SwitchBotトークン/シークレットはKeychainのShared Access Group経由でWidgetと共有
/// - UserDefaultsには施錠状態・物件名など非機密情報のみ保存
enum WidgetDataSync {
    private static let suiteName = "group.com.enablerdao.kacha"

    // MARK: - Keychain helpers (App + Widget 共有)

    /// Keychain Shared Access Group を使ってApp/Widget間でAPIキーを共有する。
    /// kSecAttrAccessGroup に App Group ID を指定することで両者からアクセス可能。
    private static let keychainService = "com.enablerdao.kacha.widget"
    private static let keychainGroup   = "group.com.enablerdao.kacha"

    private static func saveToKeychain(value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: keychainGroup,
        ]
        SecItemDelete(query as CFDictionary)

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    /// Widget側からもこのメソッドで取得する。
    static func loadFromKeychain(account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: keychainGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Keychain keys

    static let keychainKeyToken    = "switchbot_token"
    static let keychainKeySecret   = "switchbot_secret"
    static let keychainKeyDeviceId = "switchbot_lock_device_id"

    // MARK: - Public

    static func sync(context: ModelContext) {
        guard let d = UserDefaults(suiteName: suiteName) else { return }

        // Fetch active home
        let activeId = UserDefaults.standard.string(forKey: "activeHomeId")
        let homes = (try? context.fetch(FetchDescriptor<Home>())) ?? []
        let home = homes.first(where: { $0.id == activeId }) ?? homes.first

        // Home metadata (非機密情報のみ UserDefaults)
        d.set(home?.name ?? "IKI", forKey: "widget_home_name")

        // SwitchBot credentials → Keychain Shared Access Group
        if let home {
            saveToKeychain(value: home.switchBotToken,  account: keychainKeyToken)
            saveToKeychain(value: home.switchBotSecret, account: keychainKeySecret)

            // Find first SwitchBot lock device
            let devices = (try? context.fetch(FetchDescriptor<SmartDevice>())) ?? []
            let lockDevice = devices.first(where: {
                $0.homeId == home.id && $0.type == "lock" && $0.platform == "switchbot"
            })
            saveToKeychain(value: lockDevice?.deviceId ?? "", account: keychainKeyDeviceId)
            d.set(lockDevice?.isLocked ?? true, forKey: "widget_is_locked")
        }

        // Today's bookings
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let allBookings = (try? context.fetch(FetchDescriptor<Booking>())) ?? []

        let homeId = home?.id ?? ""
        let todayBookings = allBookings.filter {
            $0.homeId == homeId &&
            ($0.status == "upcoming" || $0.status == "active")
        }

        let checkIns = todayBookings.filter {
            $0.checkIn >= today && $0.checkIn < tomorrow
        }.count
        let checkOuts = todayBookings.filter {
            $0.checkOut >= today && $0.checkOut < tomorrow
        }.count

        d.set(checkIns,  forKey: "widget_today_checkins")
        d.set(checkOuts, forKey: "widget_today_checkouts")
        d.set(home?.minpakuNights ?? 0, forKey: "widget_month_nights")

        // Property count & vacancy status
        let allHomes = (try? context.fetch(FetchDescriptor<Home>())) ?? []
        d.set(allHomes.count, forKey: "widget_property_count")

        // Count vacant properties (no active booking today)
        let vacantCount = allHomes.filter { h in
            !allBookings.contains(where: { $0.homeId == h.id && $0.status == "active" })
        }.count
        d.set(vacantCount, forKey: "widget_vacant_count")

        // Today's check-in/out events with guest names for medium widget
        struct WidgetTodayEvent: Codable {
            let guestName: String
            let propertyName: String
            let time: String
            let eventType: String  // "checkin" or "checkout"
            let platform: String
        }

        let todayFormatter = DateFormatter()
        todayFormatter.locale = Locale(identifier: "ja_JP")
        todayFormatter.dateFormat = "H:mm"

        var todayEvents: [WidgetTodayEvent] = []

        // Check-ins today
        for booking in allBookings where booking.checkIn >= today && booking.checkIn < tomorrow {
            let homeName = allHomes.first(where: { $0.id == booking.homeId })?.name ?? ""
            todayEvents.append(WidgetTodayEvent(
                guestName: booking.guestName.isEmpty ? "ゲスト" : booking.guestName,
                propertyName: homeName,
                time: todayFormatter.string(from: booking.checkIn),
                eventType: "checkin",
                platform: booking.platform
            ))
        }

        // Check-outs today
        for booking in allBookings where booking.checkOut >= today && booking.checkOut < tomorrow {
            let homeName = allHomes.first(where: { $0.id == booking.homeId })?.name ?? ""
            todayEvents.append(WidgetTodayEvent(
                guestName: booking.guestName.isEmpty ? "ゲスト" : booking.guestName,
                propertyName: homeName,
                time: todayFormatter.string(from: booking.checkOut),
                eventType: "checkout",
                platform: booking.platform
            ))
        }

        // Sort by time
        todayEvents.sort { $0.time < $1.time }

        if let eventsData = try? JSONEncoder().encode(todayEvents) {
            d.set(eventsData, forKey: "widget_today_events")
        }

        // Upcoming bookings (next 5, sorted by check-in)
        let upcoming = allBookings
            .filter {
                $0.homeId == homeId &&
                ($0.status == "upcoming" || $0.status == "active") &&
                $0.checkIn >= Date()
            }
            .sorted { $0.checkIn < $1.checkIn }
            .prefix(5)

        struct WidgetBookingItem: Codable {
            let guestName: String
            let timeLabel: String
            let platform: String
            let checkInDate: TimeInterval
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d H:mm"

        let items: [WidgetBookingItem] = upcoming.map { booking in
            let isToday = Calendar.current.isDateInToday(booking.checkIn)
            let isTomorrow = Calendar.current.isDateInTomorrow(booking.checkIn)
            formatter.dateFormat = "H:mm"
            let timeStr = formatter.string(from: booking.checkIn)
            let prefix = isToday ? "" : isTomorrow ? "明日 " : {
                formatter.dateFormat = "M/d "
                return formatter.string(from: booking.checkIn)
            }()
            let label = "\(prefix)\(timeStr) チェックイン"
            return WidgetBookingItem(
                guestName: booking.guestName.isEmpty ? "ゲスト" : booking.guestName,
                timeLabel: label,
                platform: booking.platform,
                checkInDate: booking.checkIn.timeIntervalSince1970
            )
        }

        if let data = try? JSONEncoder().encode(items) {
            d.set(data, forKey: "widget_upcoming_bookings")
        }

        // Next guest convenience keys
        if let first = upcoming.first {
            formatter.dateFormat = "H:mm"
            let timeStr = formatter.string(from: first.checkIn)
            let isToday = Calendar.current.isDateInToday(first.checkIn)
            let label = isToday ? "\(timeStr) チェックイン" : {
                formatter.dateFormat = "M/d H:mm"
                return "\(formatter.string(from: first.checkIn)) チェックイン"
            }()
            d.set(first.guestName.isEmpty ? "ゲスト" : first.guestName, forKey: "widget_next_guest_name")
            d.set(label,                                    forKey: "widget_next_checkin_label")
            d.set(first.platform,                           forKey: "widget_next_platform")
            d.set(first.checkIn.timeIntervalSince1970,      forKey: "widget_next_checkin")
        } else {
            d.set("", forKey: "widget_next_guest_name")
            d.set("", forKey: "widget_next_checkin_label")
            d.set("", forKey: "widget_next_platform")
            d.set(0.0, forKey: "widget_next_checkin")
        }

        d.set(Date().timeIntervalSince1970, forKey: "widget_last_updated")

        // Tell WidgetKit to reload
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Call this from SwitchBotClient after a successful lock/unlock operation.
    static func updateLockState(isLocked: Bool) {
        let d = UserDefaults(suiteName: suiteName)
        d?.set(isLocked, forKey: "widget_is_locked")
        WidgetCenter.shared.reloadAllTimelines()
    }
}
