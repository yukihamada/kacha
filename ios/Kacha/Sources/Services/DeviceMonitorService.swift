import Foundation
import SwiftData
import UserNotifications

// MARK: - DeviceMonitorService
// バックグラウンドで定期的にデバイス状態を監視し、異常を検知して通知を送る。
// 各ホームごとに設定済みのAPIクレデンシャルを使用する。

@MainActor
final class DeviceMonitorService: ObservableObject {
    static let shared = DeviceMonitorService()

    // 監視間隔: 5分（バッテリー/オフライン） — 頻度の高い判定はポーリングで補完
    private let checkInterval: TimeInterval = 5 * 60
    private var monitorTask: Task<Void, Never>?

    // 照明ONになった時刻を追跡する (lightId -> turnedOnDate)
    // UserDefaultsで永続化するため起動跨ぎも保持
    private let lightOnTimestampKey = "deviceMonitor_lightOnTimestamps"

    private var lightOnTimestamps: [String: Date] {
        get {
            guard let raw = UserDefaults.standard.dictionary(forKey: lightOnTimestampKey) as? [String: Double] else { return [:] }
            return raw.mapValues { Date(timeIntervalSince1970: $0) }
        }
        set {
            let encoded = newValue.mapValues { $0.timeIntervalSince1970 }
            UserDefaults.standard.set(encoded, forKey: lightOnTimestampKey)
        }
    }

    private init() {}

    // MARK: - Start / Stop

    func start(container: ModelContainer) {
        stop()
        monitorTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.runChecks(container: container)
                try? await Task.sleep(for: .seconds(checkInterval))
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    // MARK: - Main Check Loop

    func runChecks(container: ModelContainer) async {
        let context = container.mainContext
        let homes = (try? context.fetch(FetchDescriptor<Home>())) ?? []
        let bookings = (try? context.fetch(FetchDescriptor<Booking>())) ?? []

        for home in homes {
            await checkSesame(home: home, bookings: bookings, context: context)
            await checkSwitchBot(home: home, bookings: bookings, context: context)
            await checkNuki(home: home, bookings: bookings, context: context)
            await checkHueLights(home: home, context: context)
        }
    }

    // MARK: - Sesame (CANDY HOUSE)

    private func checkSesame(home: Home, bookings: [Booking], context: ModelContext) async {
        let apiKey = home.sesameApiKey
        guard !apiKey.isEmpty else { return }

        let uuids = home.sesameDeviceUUIDs
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for uuid in uuids {
            do {
                let status = try await SesameClient.shared.fetchStatus(uuid: uuid, apiKey: apiKey)

                // ルールa: 電池残量 < 20%
                if let battery = status.batteryPercentage, battery < 20 {
                    await fireAlert(
                        context: context,
                        homeId: home.id,
                        deviceName: "Sesame (\(uuid.prefix(8))...)",
                        type: .lowBattery,
                        message: "電池残量が\(battery)%です。早めに交換してください。",
                        severity: "warning",
                        deduplicationKey: "sesame_battery_\(uuid)"
                    )
                }

                // ルールb: チェックアウト後30分経過で未施錠
                if status.isInLockRange == false {
                    checkUnlockAfterCheckout(
                        homeId: home.id,
                        deviceName: "Sesame (\(uuid.prefix(8))...)",
                        bookings: bookings,
                        context: context,
                        deduplicationKey: "sesame_unlock_checkout_\(uuid)"
                    )
                }

            } catch {
                // ルールf: デバイス応答なし
                await fireAlert(
                    context: context,
                    homeId: home.id,
                    deviceName: "Sesame (\(uuid.prefix(8))...)",
                    type: .deviceOffline,
                    message: "Sesameデバイスに接続できません: \(error.localizedDescription)",
                    severity: "critical",
                    deduplicationKey: "sesame_offline_\(uuid)"
                )
            }
        }
    }

    // MARK: - SwitchBot

    private func checkSwitchBot(home: Home, bookings: [Booking], context: ModelContext) async {
        let token = home.switchBotToken
        let secret = home.switchBotSecret
        guard !token.isEmpty, !secret.isEmpty else { return }

        do {
            let devices = try await SwitchBotClient.shared.fetchDevices(token: token, secret: secret)
            let lockDevices = devices.filter { $0.deviceType.lowercased().contains("lock") }

            for device in lockDevices {
                do {
                    let status = try await SwitchBotClient.shared.fetchStatus(
                        deviceId: device.deviceId, token: token, secret: secret
                    )

                    // ルールa: 電池残量 < 20%
                    if let battery = status.battery, battery < 20 {
                        await fireAlert(
                            context: context,
                            homeId: home.id,
                            deviceName: device.deviceName,
                            type: .lowBattery,
                            message: "電池残量が\(battery)%です。早めに交換してください。",
                            severity: "warning",
                            deduplicationKey: "switchbot_battery_\(device.deviceId)"
                        )
                    }

                    // ルールb: チェックアウト後30分経過で未施錠
                    if status.lockState?.lowercased() == "unlocked" {
                        checkUnlockAfterCheckout(
                            homeId: home.id,
                            deviceName: device.deviceName,
                            bookings: bookings,
                            context: context,
                            deduplicationKey: "switchbot_unlock_checkout_\(device.deviceId)"
                        )
                    }

                } catch {
                    await fireAlert(
                        context: context,
                        homeId: home.id,
                        deviceName: device.deviceName,
                        type: .deviceOffline,
                        message: "\(device.deviceName)に接続できません: \(error.localizedDescription)",
                        severity: "critical",
                        deduplicationKey: "switchbot_offline_\(device.deviceId)"
                    )
                }
            }

            // SwitchBotセンサー(温湿度計)チェック
            let sensorDevices = devices.filter {
                let t = $0.deviceType.lowercased()
                return t.contains("meter") || t.contains("sensor") || t.contains("hub")
            }
            for sensor in sensorDevices {
                do {
                    let _ = try await SwitchBotClient.shared.fetchStatus(
                        deviceId: sensor.deviceId, token: token, secret: secret
                    )
                    // 温湿度の詳細はSwitchBot APIのbodyにtemperature/humidityが含まれる場合のみ
                    // 現在のDeviceStatusモデルには含まれていないため、拡張時に対応
                    // (SwitchBotClient.DeviceStatusにtemperature/humidityを追加することで有効化可能)
                } catch {
                    await fireAlert(
                        context: context,
                        homeId: home.id,
                        deviceName: sensor.deviceName,
                        type: .deviceOffline,
                        message: "\(sensor.deviceName)に接続できません",
                        severity: "critical",
                        deduplicationKey: "switchbot_offline_\(sensor.deviceId)"
                    )
                }
            }

        } catch {
            // SwitchBotデバイスリスト取得失敗 = ネットワークor認証エラー
            // 個別デバイス名が不明のためホーム全体として記録
            await fireAlert(
                context: context,
                homeId: home.id,
                deviceName: "SwitchBot",
                type: .deviceOffline,
                message: "SwitchBotサービスへの接続に失敗しました: \(error.localizedDescription)",
                severity: "critical",
                deduplicationKey: "switchbot_service_offline_\(home.id)"
            )
        }
    }

    // MARK: - Nuki

    private func checkNuki(home: Home, bookings: [Booking], context: ModelContext) async {
        // NukiトークンはDeviceIntegration経由で管理
        // Home.idで関連付けられたnuki integrationを検索
        guard let integrations = try? context.fetch(FetchDescriptor<DeviceIntegration>()) else { return }
        let nukiIntegrations = integrations.filter {
            $0.homeId == home.id && $0.platform == "nuki" && $0.isEnabled
        }

        for integration in nukiIntegrations {
            let token = integration["token"]
            guard !token.isEmpty else { continue }

            do {
                let locks = try await NukiClient.shared.fetchSmartLocks(token: token)
                for lock in locks {
                    // ルールa: batteryCritical フラグ
                    if lock.state?.batteryCritical == true {
                        await fireAlert(
                            context: context,
                            homeId: home.id,
                            deviceName: lock.name,
                            type: .lowBattery,
                            message: "\(lock.name)の電池残量が危険レベルです。すぐに交換してください。",
                            severity: "critical",
                            deduplicationKey: "nuki_battery_\(lock.smartlockId)"
                        )
                    }

                    // ルールb: チェックアウト後30分経過で未施錠
                    if lock.state?.isLocked == false {
                        checkUnlockAfterCheckout(
                            homeId: home.id,
                            deviceName: lock.name,
                            bookings: bookings,
                            context: context,
                            deduplicationKey: "nuki_unlock_checkout_\(lock.smartlockId)"
                        )
                    }
                }
            } catch {
                await fireAlert(
                    context: context,
                    homeId: home.id,
                    deviceName: integration.name.isEmpty ? "Nuki" : integration.name,
                    type: .deviceOffline,
                    message: "Nukiデバイスに接続できません: \(error.localizedDescription)",
                    severity: "critical",
                    deduplicationKey: "nuki_offline_\(integration.id)"
                )
            }
        }
    }

    // MARK: - Philips Hue (照明)

    private func checkHueLights(home: Home, context: ModelContext) async {
        let bridgeIP = home.hueBridgeIP
        let username = home.hueUsername
        guard !bridgeIP.isEmpty, !username.isEmpty else { return }

        do {
            let lights = try await HueClient.shared.fetchLights(bridgeIP: bridgeIP, username: username)
            let now = Date()
            var timestamps = lightOnTimestamps

            for light in lights {
                let key = "\(home.id)_\(light.id)"

                if light.on {
                    // 点灯中: タイムスタンプが未記録なら記録開始
                    if timestamps[key] == nil {
                        timestamps[key] = now
                    }

                    // ルールe: 12時間以上ON
                    if let onSince = timestamps[key],
                       now.timeIntervalSince(onSince) >= 12 * 3600 {
                        let hours = Int(now.timeIntervalSince(onSince) / 3600)
                        await fireAlert(
                            context: context,
                            homeId: home.id,
                            deviceName: light.name,
                            type: .lightLeftOn,
                            message: "\(light.name)が\(hours)時間以上点灯したままです。",
                            severity: "warning",
                            deduplicationKey: "hue_lighton_\(home.id)_\(light.id)"
                        )
                    }
                } else {
                    // 消灯時はタイムスタンプをクリア
                    timestamps.removeValue(forKey: key)
                    // 解決済みにする
                    await resolveAlerts(
                        context: context,
                        homeId: home.id,
                        type: .lightLeftOn,
                        deduplicationKey: "hue_lighton_\(home.id)_\(light.id)"
                    )
                }
            }
            lightOnTimestamps = timestamps

        } catch {
            await fireAlert(
                context: context,
                homeId: home.id,
                deviceName: "Philips Hue",
                type: .deviceOffline,
                message: "Hueブリッジ(\(bridgeIP))に接続できません",
                severity: "critical",
                deduplicationKey: "hue_offline_\(home.id)"
            )
        }
    }

    // MARK: - Checkout + Unlock Check (共通ロジック)

    private func checkUnlockAfterCheckout(
        homeId: String,
        deviceName: String,
        bookings: [Booking],
        context: ModelContext,
        deduplicationKey: String
    ) {
        let now = Date()
        let thirtyMinutesAgo = now.addingTimeInterval(-30 * 60)

        // チェックアウト済み(completed)または当日チェックアウトで30分以上経過した予約を探す
        let recentCheckouts = bookings.filter { booking in
            guard booking.homeId == homeId else { return false }
            let isCompletedOrExpired = booking.status == "completed" ||
                (booking.status == "active" && booking.checkOut < thirtyMinutesAgo)
            return isCompletedOrExpired && booking.checkOut > now.addingTimeInterval(-3 * 3600)
        }

        guard !recentCheckouts.isEmpty else { return }

        let guestName = recentCheckouts.first?.guestName ?? "ゲスト"
        Task {
            await fireAlert(
                context: context,
                homeId: homeId,
                deviceName: deviceName,
                type: .unlockAfterCheckout,
                message: "\(guestName)様のチェックアウトから30分以上経過しましたが、\(deviceName)が解錠状態です。",
                severity: "critical",
                deduplicationKey: deduplicationKey
            )
        }
    }

    // MARK: - Alert Persistence & Deduplication

    /// 重複なくアラートを発火。homeId + alertType + deviceName が一致するアクティブアラートがあればスキップ。
    private func fireAlert(
        context: ModelContext,
        homeId: String,
        deviceName: String,
        type: AlertType,
        message: String,
        severity: String,
        deduplicationKey: String
    ) async {
        let existingAlerts = (try? context.fetch(FetchDescriptor<DeviceAlert>())) ?? []
        let isDuplicate = existingAlerts.contains { alert in
            !alert.isResolved &&
            alert.alertType == type.rawValue &&
            alert.homeId == homeId &&
            alert.deviceName == deviceName
        }
        guard !isDuplicate else { return }

        let alert = DeviceAlert(
            homeId: homeId,
            deviceName: deviceName,
            alertType: type.rawValue,
            message: message,
            severity: severity
        )
        context.insert(alert)
        try? context.save()

        sendNotification(type: type, deviceName: deviceName, message: message, severity: severity, alertId: alert.id)
    }

    /// 特定デバイス・タイプのアクティブなアラートを解決済みにする
    private func resolveAlerts(
        context: ModelContext,
        homeId: String,
        type: AlertType,
        deduplicationKey: String
    ) async {
        let alerts = (try? context.fetch(FetchDescriptor<DeviceAlert>())) ?? []
        let targets = alerts.filter {
            !$0.isResolved && $0.alertType == type.rawValue && $0.homeId == homeId
        }
        for alert in targets {
            alert.isResolved = true
            alert.resolvedAt = Date()
        }
        if !targets.isEmpty {
            try? context.save()
        }
    }

    // MARK: - Local Notification

    private func sendNotification(type: AlertType, deviceName: String, message: String, severity: String, alertId: String) {
        let content = UNMutableNotificationContent()
        content.title = type.title
        content.body = message
        content.sound = severity == "critical" ? .defaultCritical : .default
        content.userInfo = [
            "alertId": alertId,
            "alertType": type.rawValue,
            "severity": severity
        ]
        // categoryIdentifierを使いアクション(対応済み)をロック画面から実行可能に
        content.categoryIdentifier = "DEVICE_ALERT"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let identifier = "\(type.notificationIdentifierPrefix)_\(alertId)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Notification Category Registration

    static func registerNotificationCategory() {
        let resolveAction = UNNotificationAction(
            identifier: "RESOLVE_ALERT",
            title: "対応済み",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: "DEVICE_ALERT",
            actions: [resolveAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}

// MARK: - SwitchBot DeviceStatus Extension
// SwitchBotのセンサー系デバイス(温湿度計)から温度・湿度を取得するための拡張。
// 現在のSwitchBotClient.DeviceStatusにフィールドを追加すれば自動的に活用される。
extension SwitchBotClient.DeviceStatus {
    /// 温度(摂氏)。Meter/Hub Miniデバイスで利用可能。
    var temperature: Double? { nil }  // SwitchBotClient.DeviceStatusにtemperatureが追加されたら置換

    /// 湿度(%)。Meter/Hub Miniデバイスで利用可能。
    var humidity: Int? { nil }        // SwitchBotClient.DeviceStatusにhumidityが追加されたら置換
}
