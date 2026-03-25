import Foundation
import Security
import SwiftData

struct KeychainBackup {
    private static let service = "com.enablerdao.kacha.backup"

    private static func save(key: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    struct HomeBackupData: Codable {
        let id: String
        let name: String
        let address: String
        let sortOrder: Int
        let doorCode: String
        let wifiPassword: String
        let switchBotToken: String
        let switchBotSecret: String
        let hueBridgeIP: String
        let hueUsername: String
        let sesameApiKey: String
        let sesameDeviceUUIDs: String
        let qrioApiKey: String
        let qrioDeviceIds: String
        let autolockEnabled: Bool
        let autolockBotDeviceId: String
        let autolockRoomNumber: String
        let latitude: Double
        let longitude: Double
        let geofenceRadius: Double
        let geofenceEnabled: Bool
        let businessType: String
        let beds24ApiKey: String
        let beds24RefreshToken: String
        let minpakuNumber: String
        let minpakuNights: Int
    }

    struct AppBackupData: Codable {
        let homes: [HomeBackupData]
        let activeHomeId: String
        let hasCompletedOnboarding: Bool
        let minpakuModeEnabled: Bool
        let backedUpAt: Date
    }

    static func backup(context: ModelContext) {
        let homes = (try? context.fetch(FetchDescriptor<Home>())) ?? []
        guard !homes.isEmpty else { return }

        let backupHomes = homes.map { h in
            HomeBackupData(
                id: h.id, name: h.name, address: h.address, sortOrder: h.sortOrder,
                doorCode: h.doorCode, wifiPassword: h.wifiPassword,
                switchBotToken: h.switchBotToken, switchBotSecret: h.switchBotSecret,
                hueBridgeIP: h.hueBridgeIP, hueUsername: h.hueUsername,
                sesameApiKey: h.sesameApiKey, sesameDeviceUUIDs: h.sesameDeviceUUIDs,
                qrioApiKey: h.qrioApiKey, qrioDeviceIds: h.qrioDeviceIds,
                autolockEnabled: h.autolockEnabled,
                autolockBotDeviceId: h.autolockBotDeviceId,
                autolockRoomNumber: h.autolockRoomNumber,
                latitude: h.latitude, longitude: h.longitude,
                geofenceRadius: h.geofenceRadius, geofenceEnabled: h.geofenceEnabled,
                businessType: h.businessType,
                beds24ApiKey: h.beds24ApiKey, beds24RefreshToken: h.beds24RefreshToken,
                minpakuNumber: h.minpakuNumber, minpakuNights: h.minpakuNights
            )
        }

        let backup = AppBackupData(
            homes: backupHomes,
            activeHomeId: UserDefaults.standard.string(forKey: "activeHomeId") ?? "",
            hasCompletedOnboarding: UserDefaults.standard.bool(forKey: "hasCompletedOnboarding"),
            minpakuModeEnabled: UserDefaults.standard.bool(forKey: "minpakuModeEnabled"),
            backedUpAt: Date()
        )

        if let data = try? JSONEncoder().encode(backup) {
            save(key: "app_backup", data: data)
        }
    }

    static func restoreIfNeeded(context: ModelContext) -> Bool {
        let existingHomes = (try? context.fetch(FetchDescriptor<Home>())) ?? []
        guard existingHomes.isEmpty else { return false }

        guard let data = load(key: "app_backup"),
              let backup = try? JSONDecoder().decode(AppBackupData.self, from: data)
        else { return false }

        for bh in backup.homes {
            let home = Home(name: bh.name, sortOrder: bh.sortOrder)
            home.id = bh.id
            home.address = bh.address
            home.doorCode = bh.doorCode
            home.wifiPassword = bh.wifiPassword
            home.switchBotToken = bh.switchBotToken
            home.switchBotSecret = bh.switchBotSecret
            home.hueBridgeIP = bh.hueBridgeIP
            home.hueUsername = bh.hueUsername
            home.sesameApiKey = bh.sesameApiKey
            home.sesameDeviceUUIDs = bh.sesameDeviceUUIDs
            home.qrioApiKey = bh.qrioApiKey
            home.qrioDeviceIds = bh.qrioDeviceIds
            home.autolockEnabled = bh.autolockEnabled
            home.autolockBotDeviceId = bh.autolockBotDeviceId
            home.autolockRoomNumber = bh.autolockRoomNumber
            home.latitude = bh.latitude
            home.longitude = bh.longitude
            home.geofenceRadius = bh.geofenceRadius
            home.geofenceEnabled = bh.geofenceEnabled
            home.businessType = bh.businessType
            home.beds24ApiKey = bh.beds24ApiKey
            home.beds24RefreshToken = bh.beds24RefreshToken
            home.minpakuNumber = bh.minpakuNumber
            home.minpakuNights = bh.minpakuNights
            context.insert(home)
        }
        try? context.save()

        UserDefaults.standard.set(backup.activeHomeId, forKey: "activeHomeId")
        UserDefaults.standard.set(backup.hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
        UserDefaults.standard.set(backup.minpakuModeEnabled, forKey: "minpakuModeEnabled")

        if let activeHome = backup.homes.first(where: { $0.id == backup.activeHomeId }) {
            UserDefaults.standard.set(activeHome.name, forKey: "facilityName")
        }

        return true
    }
}
