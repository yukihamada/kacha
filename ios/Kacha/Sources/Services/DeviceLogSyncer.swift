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

    // MARK: - Sync All

    static func syncAll(
        context: ModelContext,
        homeId: String,
        sesameUUIDs: [String],
        sesameApiKey: String,
        switchBotToken: String,
        switchBotSecret: String
    ) async -> Int {
        async let sesameCount = syncSesameHistory(
            context: context, homeId: homeId,
            uuids: sesameUUIDs, apiKey: sesameApiKey
        )
        async let switchBotCount = syncSwitchBotStatus(
            context: context, homeId: homeId,
            token: switchBotToken, secret: switchBotSecret
        )
        let s = await sesameCount
        let b = await switchBotCount
        return s + b
    }

    // MARK: - Helpers

    private static func extractExternalId(_ detail: String) -> String? {
        // Extract [sesame-123] from detail string
        guard let start = detail.firstIndex(of: "["),
              let end = detail.firstIndex(of: "]"),
              start < end else { return nil }
        return String(detail[detail.index(after: start)..<end])
    }
}
