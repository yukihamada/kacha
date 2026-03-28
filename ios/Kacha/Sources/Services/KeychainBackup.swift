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
        // kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly でデバイスリセットまで保持
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        #if DEBUG
        if status != errSecSuccess {
            print("[KeychainBackup] save failed: \(status)")
        }
        #endif
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
        guard status == errSecSuccess else {
            #if DEBUG
            if status != errSecItemNotFound {
                print("[KeychainBackup] load failed: \(status)")
            }
            #endif
            return nil
        }
        return result as? Data
    }

    // MARK: - Backup Data Structures

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
        let airbnbICalURL: String?
        let jalanICalURL: String?
        // v3 fields (optional for backward compatibility)
        var sharedRole: String?
        var backgroundImageURL: String?
        var permitProgress: String?
    }

    struct DeviceBackupData: Codable {
        let id: String
        let deviceId: String
        let name: String
        let type: String
        let platform: String
        let homeId: String
        let roomId: String
    }

    struct BookingBackupData: Codable {
        let id: String
        let guestName: String
        let platform: String
        let homeId: String
        let checkIn: Date
        let checkOut: Date
        let status: String
        let totalAmount: Int
        let notes: String
        // v3 fields (optional for backward compatibility)
        var guestEmail: String?
        var guestPhone: String?
        var externalId: String?
        var roomCount: Int?
        var numAdults: Int?
        var numChildren: Int?
        var roomId: String?
        var commission: Int?
        var guestNotes: String?
        var autoUnlock: Bool?
        var autoLight: Bool?
        var cleaningDone: Bool?
    }

    struct ChecklistBackupData: Codable {
        let id: String
        let homeId: String
        let title: String
        let category: String
        let sortOrder: Int
    }

    struct AppBackupData: Codable {
        let version: Int  // バックアップバージョン（将来の互換性用）
        let homes: [HomeBackupData]
        let devices: [DeviceBackupData]
        let bookings: [BookingBackupData]
        let checklists: [ChecklistBackupData]
        let activeHomeId: String
        let hasCompletedOnboarding: Bool
        let minpakuModeEnabled: Bool
        let backedUpAt: Date
    }

    // MARK: - Backup（全データ）

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
                minpakuNumber: h.minpakuNumber, minpakuNights: h.minpakuNights,
                airbnbICalURL: h.airbnbICalURL, jalanICalURL: h.jalanICalURL,
                sharedRole: h.sharedRole, backgroundImageURL: h.backgroundImageURL,
                permitProgress: h.permitProgress
            )
        }

        // デバイス
        let devices = (try? context.fetch(FetchDescriptor<SmartDevice>())) ?? []
        let backupDevices = devices.map { d in
            DeviceBackupData(
                id: d.id, deviceId: d.deviceId, name: d.name,
                type: d.type, platform: d.platform,
                homeId: d.homeId, roomId: d.roomId
            )
        }

        // 予約（直近3ヶ月分のみ）
        let threeMonthsAgo = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
        var bookingDesc = FetchDescriptor<Booking>()
        bookingDesc.predicate = #Predicate { $0.checkOut > threeMonthsAgo }
        let bookings = (try? context.fetch(bookingDesc)) ?? []
        let backupBookings = bookings.map { b in
            BookingBackupData(
                id: b.id, guestName: b.guestName, platform: b.platform,
                homeId: b.homeId, checkIn: b.checkIn, checkOut: b.checkOut,
                status: b.status, totalAmount: b.totalAmount, notes: b.notes,
                guestEmail: b.guestEmail, guestPhone: b.guestPhone,
                externalId: b.externalId, roomCount: b.roomCount,
                numAdults: b.numAdults, numChildren: b.numChildren,
                roomId: b.roomId, commission: b.commission, guestNotes: b.guestNotes,
                autoUnlock: b.autoUnlock, autoLight: b.autoLight, cleaningDone: b.cleaningDone
            )
        }

        // チェックリスト
        let checklists = (try? context.fetch(FetchDescriptor<ChecklistItem>())) ?? []
        let backupChecklists = checklists.map { c in
            ChecklistBackupData(
                id: c.id, homeId: c.homeId, title: c.title,
                category: c.category, sortOrder: c.sortOrder
            )
        }

        let backup = AppBackupData(
            version: 2,
            homes: backupHomes,
            devices: backupDevices,
            bookings: backupBookings,
            checklists: backupChecklists,
            activeHomeId: UserDefaults.standard.string(forKey: "activeHomeId") ?? "",
            hasCompletedOnboarding: UserDefaults.standard.bool(forKey: "hasCompletedOnboarding"),
            minpakuModeEnabled: UserDefaults.standard.bool(forKey: "minpakuModeEnabled"),
            backedUpAt: Date()
        )

        if let data = try? JSONEncoder().encode(backup) {
            save(key: "app_backup", data: data)
            #if DEBUG
            print("[KeychainBackup] saved: \(homes.count) homes, \(devices.count) devices, \(bookings.count) bookings, \(checklists.count) checklists (\(data.count) bytes)")
            #endif
        }
    }

    // MARK: - Restore（再インストール時の自動復元）

    static func restoreIfNeeded(context: ModelContext) -> Bool {
        let existingHomes = (try? context.fetch(FetchDescriptor<Home>())) ?? []
        guard existingHomes.isEmpty else { return false }

        guard let data = load(key: "app_backup") else {
            #if DEBUG
            print("[KeychainBackup] no backup found in Keychain")
            #endif
            return false
        }

        // v2形式を試行、失敗したらv1（旧形式）にフォールバック
        if let backup = try? JSONDecoder().decode(AppBackupData.self, from: data) {
            return restoreV2(backup: backup, context: context)
        }

        // v1 フォールバック（homes + settings のみ）
        struct LegacyBackup: Codable {
            let homes: [HomeBackupData]
            let activeHomeId: String
            let hasCompletedOnboarding: Bool
            let minpakuModeEnabled: Bool
            let backedUpAt: Date
        }
        if let legacy = try? JSONDecoder().decode(LegacyBackup.self, from: data) {
            let v2 = AppBackupData(
                version: 1, homes: legacy.homes,
                devices: [], bookings: [], checklists: [],
                activeHomeId: legacy.activeHomeId,
                hasCompletedOnboarding: legacy.hasCompletedOnboarding,
                minpakuModeEnabled: legacy.minpakuModeEnabled,
                backedUpAt: legacy.backedUpAt
            )
            return restoreV2(backup: v2, context: context)
        }

        #if DEBUG
        print("[KeychainBackup] failed to decode backup data")
        #endif
        return false
    }

    private static func restoreV2(backup: AppBackupData, context: ModelContext) -> Bool {
        // Homes
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
            if let url = bh.airbnbICalURL { home.airbnbICalURL = url }
            if let url = bh.jalanICalURL { home.jalanICalURL = url }
            if let role = bh.sharedRole { home.sharedRole = role }
            if let bgURL = bh.backgroundImageURL { home.backgroundImageURL = bgURL }
            if let pp = bh.permitProgress { home.permitProgress = pp }
            context.insert(home)
        }

        // Devices
        for bd in backup.devices {
            let device = SmartDevice(deviceId: bd.deviceId, name: bd.name, type: bd.type, platform: bd.platform, homeId: bd.homeId)
            device.id = bd.id
            device.roomId = bd.roomId
            context.insert(device)
        }

        // Bookings
        for bb in backup.bookings {
            let booking = Booking(guestName: bb.guestName, homeId: bb.homeId, checkIn: bb.checkIn, checkOut: bb.checkOut)
            booking.id = bb.id
            booking.platform = bb.platform
            booking.status = bb.status
            booking.totalAmount = bb.totalAmount
            booking.notes = bb.notes
            booking.guestEmail = bb.guestEmail ?? ""
            booking.guestPhone = bb.guestPhone ?? ""
            booking.externalId = bb.externalId ?? ""
            booking.roomCount = bb.roomCount ?? 1
            booking.numAdults = bb.numAdults ?? 1
            booking.numChildren = bb.numChildren ?? 0
            booking.roomId = bb.roomId ?? ""
            booking.commission = bb.commission ?? 0
            booking.guestNotes = bb.guestNotes ?? ""
            booking.autoUnlock = bb.autoUnlock ?? true
            booking.autoLight = bb.autoLight ?? true
            booking.cleaningDone = bb.cleaningDone ?? false
            context.insert(booking)
        }

        // Checklists
        for bc in backup.checklists {
            let item = ChecklistItem(homeId: bc.homeId, title: bc.title, category: bc.category, sortOrder: bc.sortOrder)
            item.id = bc.id
            context.insert(item)
        }

        try? context.save()

        // Settings
        UserDefaults.standard.set(backup.activeHomeId, forKey: "activeHomeId")
        UserDefaults.standard.set(backup.hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
        UserDefaults.standard.set(backup.minpakuModeEnabled, forKey: "minpakuModeEnabled")

        if let activeHome = backup.homes.first(where: { $0.id == backup.activeHomeId }) {
            UserDefaults.standard.set(activeHome.name, forKey: "facilityName")
        }

        #if DEBUG
        print("[KeychainBackup] restored: \(backup.homes.count) homes, \(backup.devices.count) devices, \(backup.bookings.count) bookings, \(backup.checklists.count) checklists")
        #endif

        return true
    }

    // MARK: - バックアップ日時取得

    static func lastBackupDate() -> Date? {
        guard let data = load(key: "app_backup"),
              let backup = try? JSONDecoder().decode(AppBackupData.self, from: data)
        else { return nil }
        return backup.backedUpAt
    }
}
