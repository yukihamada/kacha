import AppIntents
import CryptoKit
import Foundation
import WidgetKit

// MARK: - App Group constants

enum WidgetSharedDefaults {
    static let suiteName = "group.com.enablerdao.kacha"
    static let isLockedKey = "widget_is_locked"
    static let switchBotTokenKey = "widget_switchbot_token"
    static let switchBotSecretKey = "widget_switchbot_secret"
    static let lockDeviceIdKey = "widget_lock_device_id"
    static let homeNameKey = "widget_home_name"
    static let todayCheckInsKey = "widget_today_checkins"
    static let todayCheckOutsKey = "widget_today_checkouts"
    static let monthNightsKey = "widget_month_nights"
    static let upcomingBookingsKey = "widget_upcoming_bookings"
    static let nextGuestNameKey = "widget_next_guest_name"
    static let nextCheckInKey = "widget_next_checkin"
    static let nextCheckInLabelKey = "widget_next_checkin_label"
    static let nextPlatformKey = "widget_next_platform"
    static let lastUpdatedKey = "widget_last_updated"
    static let propertyCountKey = "widget_property_count"
    static let vacantCountKey = "widget_vacant_count"
    static let todayEventsKey = "widget_today_events"
}

// MARK: - SwitchBot API (lightweight, widget-side)

private enum SwitchBotWidgetAPI {
    static let baseURL = "https://api.switch-bot.com/v1.1"

    static func makeHeaders(token: String, secret: String) -> [String: String] {
        let nonce = UUID().uuidString
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let stringToSign = token + timestamp + nonce
        let hmac = HMAC<SHA256>.authenticationCode(
            for: Data(stringToSign.utf8),
            using: SymmetricKey(data: Data(secret.utf8))
        )
        let sign = Data(hmac).base64EncodedString().uppercased()
        return [
            "Authorization": token,
            "sign": sign,
            "nonce": nonce,
            "t": timestamp,
            "Content-Type": "application/json"
        ]
    }

    static func sendCommand(
        deviceId: String,
        command: String,
        token: String,
        secret: String
    ) async throws {
        let url = URL(string: "\(baseURL)/devices/\(deviceId)/commands")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        makeHeaders(token: token, secret: secret).forEach {
            request.setValue($1, forHTTPHeaderField: $0)
        }
        let body: [String: Any] = [
            "command": command,
            "parameter": "default",
            "commandType": "command"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }
}

// MARK: - Lock Intent

struct LockIntent: AppIntent {
    static let title: LocalizedStringResource = "施錠する"
    static let description = IntentDescription("KAGIウィジェットから玄関を施錠します")
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: WidgetSharedDefaults.suiteName)
        guard
            let token = defaults?.string(forKey: WidgetSharedDefaults.switchBotTokenKey),
            let secret = defaults?.string(forKey: WidgetSharedDefaults.switchBotSecretKey),
            let deviceId = defaults?.string(forKey: WidgetSharedDefaults.lockDeviceIdKey),
            !token.isEmpty, !secret.isEmpty, !deviceId.isEmpty
        else { return .result() }

        try await SwitchBotWidgetAPI.sendCommand(
            deviceId: deviceId,
            command: "lock",
            token: token,
            secret: secret
        )
        defaults?.set(true, forKey: WidgetSharedDefaults.isLockedKey)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Unlock Intent

struct UnlockIntent: AppIntent {
    static let title: LocalizedStringResource = "解錠する"
    static let description = IntentDescription("KAGIウィジェットから玄関を解錠します")
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: WidgetSharedDefaults.suiteName)
        guard
            let token = defaults?.string(forKey: WidgetSharedDefaults.switchBotTokenKey),
            let secret = defaults?.string(forKey: WidgetSharedDefaults.switchBotSecretKey),
            let deviceId = defaults?.string(forKey: WidgetSharedDefaults.lockDeviceIdKey),
            !token.isEmpty, !secret.isEmpty, !deviceId.isEmpty
        else { return .result() }

        try await SwitchBotWidgetAPI.sendCommand(
            deviceId: deviceId,
            command: "unlock",
            token: token,
            secret: secret
        )
        defaults?.set(false, forKey: WidgetSharedDefaults.isLockedKey)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Toggle Intent (convenient alias for small/medium widgets)

struct LockToggleIntent: AppIntent {
    static let title: LocalizedStringResource = "施錠/解錠を切り替える"
    static let description = IntentDescription("現在の状態を反転します")
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: WidgetSharedDefaults.suiteName)
        let isLocked = defaults?.bool(forKey: WidgetSharedDefaults.isLockedKey) ?? true

        guard
            let token = defaults?.string(forKey: WidgetSharedDefaults.switchBotTokenKey),
            let secret = defaults?.string(forKey: WidgetSharedDefaults.switchBotSecretKey),
            let deviceId = defaults?.string(forKey: WidgetSharedDefaults.lockDeviceIdKey),
            !token.isEmpty, !secret.isEmpty, !deviceId.isEmpty
        else { return .result() }

        let command = isLocked ? "unlock" : "lock"
        try await SwitchBotWidgetAPI.sendCommand(
            deviceId: deviceId,
            command: command,
            token: token,
            secret: secret
        )
        defaults?.set(!isLocked, forKey: WidgetSharedDefaults.isLockedKey)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
