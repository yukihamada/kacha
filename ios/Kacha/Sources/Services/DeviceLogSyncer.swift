import Foundation
import SwiftData

// MARK: - Device Log Syncer
// 各デバイスサービスのAPIから操作履歴を取得し、ActivityLogに同期する

struct DeviceLogSyncer {

    // MARK: - Sesame History Sync

    static func syncSesameHistory(
        context: ModelContext,
        homeId: String,
        uuids: [String],
        apiKey: String
    ) async -> Int {
        var imported = 0
        for uuid in uuids where !uuid.isEmpty {
            guard let entries = try? await SesameClient.shared.fetchHistory(uuid: uuid, apiKey: apiKey) else { continue }

            // Get existing log IDs to avoid duplicates
            let descriptor = FetchDescriptor<ActivityLog>(
                predicate: #Predicate { $0.homeId == homeId && $0.deviceName.contains("Sesame") }
            )
            let existingLogs = (try? context.fetch(descriptor)) ?? []
            let existingIds = Set(existingLogs.compactMap { extractExternalId($0.detail) })

            for entry in entries {
                let extId = "sesame-\(entry.recordID)"
                guard !existingIds.contains(extId) else { continue }

                let log = ActivityLog(
                    homeId: homeId,
                    action: entry.isLock ? "lock" : entry.isUnlock ? "unlock" : "scene",
                    detail: "[\(extId)] \(entry.actionLabel)",
                    actor: entry.actor,
                    deviceName: "Sesame (\(uuid.prefix(8))...)"
                )
                log.timestamp = entry.date
                context.insert(log)
                imported += 1
            }
        }
        try? context.save()
        return imported
    }

    // MARK: - SwitchBot Status Check

    static func syncSwitchBotStatus(
        context: ModelContext,
        homeId: String,
        token: String,
        secret: String
    ) async -> Int {
        guard !token.isEmpty else { return 0 }
        var imported = 0

        let devices = (try? await SwitchBotClient.shared.fetchDevices(token: token, secret: secret)) ?? []
        let lockDevices = devices.filter { $0.deviceType.lowercased().contains("lock") }

        for device in lockDevices {
            guard let status = try? await SwitchBotClient.shared.fetchStatus(
                deviceId: device.deviceId, token: token, secret: secret
            ) else { continue }

            let state = status.lockState ?? "unknown"
            let battery = status.battery ?? -1
            let action = state == "locked" ? "lock" : state == "unlocked" ? "unlock" : "scene"

            // Only log if state changed from last known
            let descriptor = FetchDescriptor<ActivityLog>(
                predicate: #Predicate { $0.homeId == homeId && $0.deviceName.contains("SwitchBot") },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            var fetchDescriptor = descriptor
            fetchDescriptor.fetchLimit = 1
            let lastLog = (try? context.fetch(fetchDescriptor))?.first

            let lastAction = lastLog?.action ?? ""
            if lastAction != action {
                let log = ActivityLog(
                    homeId: homeId,
                    action: action,
                    detail: state == "locked" ? "施錠を検知" : state == "unlocked" ? "解錠を検知" : "ステータス: \(state)",
                    actor: "デバイス",
                    deviceName: "SwitchBot \(device.deviceName)"
                )
                context.insert(log)
                imported += 1

                // Battery warning
                if battery >= 0 && battery <= 20 {
                    let battLog = ActivityLog(
                        homeId: homeId,
                        action: "maintenance",
                        detail: "バッテリー残量 \(battery)% — 交換を検討してください",
                        actor: "システム",
                        deviceName: "SwitchBot \(device.deviceName)"
                    )
                    context.insert(battLog)
                    imported += 1
                }
            }
        }
        try? context.save()
        return imported
    }

    // MARK: - Nuki Log Sync

    static func syncNukiLogs(
        context: ModelContext,
        homeId: String,
        token: String
    ) async -> Int {
        guard !token.isEmpty else { return 0 }
        var imported = 0
        let locks = (try? await NukiClient.shared.fetchSmartLocks(token: token)) ?? []

        let descriptor = FetchDescriptor<ActivityLog>(
            predicate: #Predicate { $0.homeId == homeId && $0.deviceName.contains("Nuki") }
        )
        let existingLogs = (try? context.fetch(descriptor)) ?? []
        let existingIds = Set(existingLogs.compactMap { extractExternalId($0.detail) })

        for lock in locks {
            guard let entries = try? await NukiClient.shared.fetchLogs(smartlockId: lock.smartlockId, token: token) else { continue }
            for entry in entries {
                let extId = "nuki-\(entry.id)"
                guard !existingIds.contains(extId) else { continue }
                let log = ActivityLog(
                    homeId: homeId,
                    action: entry.isLock ? "lock" : entry.isUnlock ? "unlock" : "scene",
                    detail: "[\(extId)] \(entry.actionLabel)",
                    actor: entry.actor,
                    deviceName: "Nuki \(lock.name)"
                )
                if let ts = entry.timestamp { log.timestamp = ts }
                context.insert(log)
                imported += 1
            }

            // Battery warning
            if lock.state?.batteryCritical == true {
                let log = ActivityLog(
                    homeId: homeId,
                    action: "maintenance",
                    detail: "バッテリー残量低下 — 交換してください",
                    actor: "システム",
                    deviceName: "Nuki \(lock.name)"
                )
                context.insert(log)
                imported += 1
            }
        }
        try? context.save()
        return imported
    }

    // MARK: - Hue Light Change Detection

    private static var lastHueSnapshots: [HueClient.LightSnapshot] = []

    static func syncHueChanges(
        context: ModelContext,
        homeId: String,
        bridgeIP: String,
        username: String
    ) async -> Int {
        guard !bridgeIP.isEmpty, !username.isEmpty else { return 0 }
        var imported = 0
        let current = await HueClient.shared.fetchLightSnapshots(bridgeIP: bridgeIP, username: username)

        if !lastHueSnapshots.isEmpty {
            for light in current {
                if let prev = lastHueSnapshots.first(where: { $0.id == light.id }), prev.on != light.on {
                    let log = ActivityLog(
                        homeId: homeId,
                        action: light.on ? "light_on" : "light_off",
                        detail: "\(light.name)を\(light.on ? "点灯" : "消灯")",
                        actor: "デバイス",
                        deviceName: "Hue \(light.name)"
                    )
                    context.insert(log)
                    imported += 1
                }
            }
            try? context.save()
        }
        lastHueSnapshots = current
        return imported
    }

    // MARK: - Sync All

    static func syncAll(
        context: ModelContext,
        homeId: String,
        sesameUUIDs: [String],
        sesameApiKey: String,
        switchBotToken: String,
        switchBotSecret: String,
        nukiToken: String = "",
        hueBridgeIP: String = "",
        hueUsername: String = ""
    ) async -> Int {
        var total = 0
        total += await syncSesameHistory(context: context, homeId: homeId, uuids: sesameUUIDs, apiKey: sesameApiKey)
        total += await syncSwitchBotStatus(context: context, homeId: homeId, token: switchBotToken, secret: switchBotSecret)
        total += await syncNukiLogs(context: context, homeId: homeId, token: nukiToken)
        total += await syncHueChanges(context: context, homeId: homeId, bridgeIP: hueBridgeIP, username: hueUsername)
        return total
    }

    // MARK: - Helpers

    private static func extractExternalId(_ detail: String) -> String? {
        guard let start = detail.firstIndex(of: "["),
              let end = detail.firstIndex(of: "]"),
              start < end else { return nil }
        return String(detail[detail.index(after: start)..<end])
    }
}
