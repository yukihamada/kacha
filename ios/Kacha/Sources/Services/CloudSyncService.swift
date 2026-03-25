import Foundation
import CryptoKit
import CommonCrypto
import Security
import SwiftData
import UIKit

// MARK: - Cloud Sync Service
// E2E暗号化クラウドバックアップ。サーバーには暗号化データのみ保存。
// 鍵管理: iCloudキーチェーン or パスフレーズ（ユーザー選択）

final class CloudSyncService: ObservableObject {
    static let shared = CloudSyncService()

    private let baseURL = "https://kacha.pasha.run"
    private let keychainService = "com.enablerdao.kacha.cloudsync"
    private let appId = "kacha-ios"

    @Published var isLoggedIn = false
    @Published var userEmail = ""
    @Published var syncState: SyncState = .idle
    @Published var lastSyncDate: Date?
    @Published var keyMethod: KeyMethod = .icloudKeychain

    enum SyncState: Equatable {
        case idle, syncing, success, error(String)
    }

    enum KeyMethod: String, CaseIterable {
        case icloudKeychain = "icloud"
        case passphrase = "passphrase"

        var title: String {
            switch self {
            case .icloudKeychain: return "iCloudキーチェーン"
            case .passphrase: return "パスフレーズ"
            }
        }

        var description: String {
            switch self {
            case .icloudKeychain: return "Apple端末間で自動共有。設定不要。"
            case .passphrase: return "自分で覚えるパスフレーズで暗号化。Android等でも使用可能。"
            }
        }

        var icon: String {
            switch self {
            case .icloudKeychain: return "icloud.and.arrow.up"
            case .passphrase: return "key.fill"
            }
        }
    }

    private var sessionToken: String? {
        get { loadKeychain(key: "session_token") }
        set {
            if let v = newValue { saveKeychain(key: "session_token", value: v) }
            else { deleteKeychain(key: "session_token") }
        }
    }

    private var userId: String? {
        get { loadKeychain(key: "user_id") }
        set {
            if let v = newValue { saveKeychain(key: "user_id", value: v) }
            else { deleteKeychain(key: "user_id") }
        }
    }

    private init() {
        isLoggedIn = sessionToken != nil && userId != nil
        userEmail = loadKeychain(key: "user_email") ?? ""
        if let method = loadKeychain(key: "key_method") {
            keyMethod = KeyMethod(rawValue: method) ?? .icloudKeychain
        }
        if let ts = loadKeychain(key: "last_sync") {
            lastSyncDate = ISO8601DateFormatter().date(from: ts)
        }
    }

    // MARK: - Auth: Magic Link

    func requestMagicLink(email: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/v1/auth/magic-link") else { throw SyncError.network }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["email": email])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SyncError.network }

        struct Resp: Codable { let success: Bool; let message: String }
        let resp = try JSONDecoder().decode(Resp.self, from: data)

        if http.statusCode == 429 { throw SyncError.rateLimited }
        guard resp.success else { throw SyncError.serverError(resp.message) }
    }

    func verifyCode(email: String, code: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/v1/auth/verify") else { throw SyncError.network }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["email": email, "code": code])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SyncError.invalidCode
        }

        struct Resp: Codable { let success: Bool; let user_id: String; let token: String }
        let resp = try JSONDecoder().decode(Resp.self, from: data)

        sessionToken = resp.token
        userId = resp.user_id
        saveKeychain(key: "user_email", value: email)

        await MainActor.run {
            isLoggedIn = true
            userEmail = email
        }
    }

    func logout() {
        sessionToken = nil
        userId = nil
        deleteKeychain(key: "user_email")
        deleteKeychain(key: "last_sync")
        // 暗号鍵は残す（再ログイン時にデータ復元できるよう）

        isLoggedIn = false
        userEmail = ""
        lastSyncDate = nil
        syncState = .idle
    }

    // MARK: - E2E Backup Upload

    func backup(context: ModelContext) async {
        guard let token = sessionToken, let uid = userId else { return }

        await MainActor.run { syncState = .syncing }

        do {
            // 1. Serialize all data
            let backupData = try buildBackupPayload(context: context)

            // 2. Encrypt with E2E key
            let encryptionKey = try getOrCreateEncryptionKey()
            let encrypted = try encrypt(data: backupData, key: encryptionKey)
            let encryptedBase64 = encrypted.base64EncodedString()

            // 3. Upload
            guard let url = URL(string: "\(baseURL)/api/v1/auth/backup") else {
                await MainActor.run { syncState = .error("Invalid URL") }
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 30

            let body: [String: String] = [
                "user_id": uid,
                "app_id": appId,
                "encrypted_data": encryptedBase64,
                "session_token": token,
            ]
            request.httpBody = try JSONEncoder().encode(body)

            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw SyncError.uploadFailed
            }

            let now = Date()
            let ts = ISO8601DateFormatter().string(from: now)
            saveKeychain(key: "last_sync", value: ts)

            await MainActor.run {
                lastSyncDate = now
                syncState = .success
            }
        } catch {
            await MainActor.run {
                syncState = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - E2E Restore Download

    func restore(context: ModelContext, passphrase: String? = nil) async throws -> Int {
        guard let token = sessionToken, let uid = userId else { throw SyncError.notLoggedIn }

        await MainActor.run { syncState = .syncing }

        // 1. Download
        var urlComponents = URLComponents(string: "\(baseURL)/api/v1/auth/backup/\(appId)")!
        urlComponents.queryItems = [
            URLQueryItem(name: "user_id", value: uid),
            URLQueryItem(name: "session_token", value: token),
        ]

        let (data, response) = try await URLSession.shared.data(from: urlComponents.url!)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SyncError.noBackupFound
        }

        struct Resp: Codable { let encrypted_data: String }
        let resp = try JSONDecoder().decode(Resp.self, from: data)

        guard let encryptedData = Data(base64Encoded: resp.encrypted_data) else {
            throw SyncError.decryptionFailed
        }

        // 2. Get decryption key
        let decryptionKey: SymmetricKey
        if let phrase = passphrase {
            decryptionKey = deriveKeyFromPassphrase(phrase)
        } else {
            guard let key = loadEncryptionKey() else {
                throw SyncError.keyNotFound
            }
            decryptionKey = key
        }

        // 3. Decrypt
        let plaintext = try decrypt(data: encryptedData, key: decryptionKey)

        // 4. Import
        let count = try importBackupPayload(plaintext, into: context)

        await MainActor.run { syncState = .success }
        return count
    }

    // MARK: - Key Management

    func setKeyMethod(_ method: KeyMethod, passphrase: String? = nil) throws {
        keyMethod = method
        saveKeychain(key: "key_method", value: method.rawValue)

        if method == .passphrase, let phrase = passphrase, !phrase.isEmpty {
            let derived = deriveKeyFromPassphrase(phrase)
            saveEncryptionKey(derived, sync: false)
        } else if method == .icloudKeychain {
            // Generate or migrate key to iCloud-synced Keychain
            let key = loadEncryptionKey() ?? SymmetricKey(size: .bits256)
            saveEncryptionKey(key, sync: true)
        }
    }

    var hasEncryptionKey: Bool {
        loadEncryptionKey() != nil
    }

    // MARK: - Encryption Key Storage

    private func getOrCreateEncryptionKey() throws -> SymmetricKey {
        if let existing = loadEncryptionKey() { return existing }

        let key = SymmetricKey(size: .bits256)
        let sync = keyMethod == .icloudKeychain
        saveEncryptionKey(key, sync: sync)
        return key
    }

    private func saveEncryptionKey(_ key: SymmetricKey, sync: Bool) {
        let keyData = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(keychainService).enckey",
            kSecAttrAccount as String: "encryption_key",
        ]
        SecItemDelete(query as CFDictionary)

        var add = query
        add[kSecValueData as String] = keyData
        if sync {
            // iCloudキーチェーン同期: kSecAttrSynchronizable = true
            add[kSecAttrSynchronizable as String] = kCFBooleanTrue
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        } else {
            // ローカルのみ
            add[kSecAttrSynchronizable as String] = kCFBooleanFalse
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
        SecItemAdd(add as CFDictionary, nil)
    }

    private func loadEncryptionKey() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(keychainService).enckey",
            kSecAttrAccount as String: "encryption_key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return SymmetricKey(data: data)
    }

    private func deriveKeyFromPassphrase(_ passphrase: String) -> SymmetricKey {
        // PBKDF2-SHA256: パスワードベースの安全な鍵導出（600,000回反復, OWASP推奨）
        let saltInput = "com.enablerdao.kacha.\(userId ?? "default")".data(using: .utf8)!
        let salt = Data(SHA256.hash(data: saltInput))
        let passData = passphrase.data(using: .utf8)!
        var derivedKey = Data(count: 32)
        derivedKey.withUnsafeMutableBytes { derivedBytes in
            passData.withUnsafeBytes { passBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        600_000,
                        derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        32
                    )
                }
            }
        }
        return SymmetricKey(data: derivedKey)
    }

    // MARK: - AES-256-GCM Encrypt/Decrypt

    private func encrypt(data: Data, key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else { throw SyncError.encryptionFailed }
        return combined
    }

    private func decrypt(data: Data, key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }

    // MARK: - Backup Payload
    // ActivityLog は最新1000件のみバックアップ（大量ログによるメモリ過剰を防止）

    private func buildBackupPayload(context: ModelContext) throws -> Data {
        let homes = (try? context.fetch(FetchDescriptor<Home>())) ?? []
        let bookings = (try? context.fetch(FetchDescriptor<Booking>())) ?? []
        let devices = (try? context.fetch(FetchDescriptor<SmartDevice>())) ?? []
        let integrations = (try? context.fetch(FetchDescriptor<DeviceIntegration>())) ?? []
        let checklists = (try? context.fetch(FetchDescriptor<ChecklistItem>())) ?? []
        let maintenance = (try? context.fetch(FetchDescriptor<MaintenanceTask>())) ?? []
        let nearby = (try? context.fetch(FetchDescriptor<NearbyPlace>())) ?? []
        let manuals = (try? context.fetch(FetchDescriptor<HouseManual>())) ?? []
        let secureItems = (try? context.fetch(FetchDescriptor<SecureItem>())) ?? []
        let utilities = (try? context.fetch(FetchDescriptor<UtilityRecord>())) ?? []
        let shares = (try? context.fetch(FetchDescriptor<ShareRecord>())) ?? []

        // ActivityLog は最新1000件のみ（全件取得はメモリ消費が大きい）
        var logDescriptor = FetchDescriptor<ActivityLog>(sortBy: [SortDescriptor(\ActivityLog.timestamp, order: .reverse)])
        logDescriptor.fetchLimit = 1000
        let logs = (try? context.fetch(logDescriptor)) ?? []

        let payload = CloudBackupPayload(
            version: 1,
            createdAt: Date(),
            homes: homes.map { HomePayload(home: $0) },
            bookings: bookings.map { BookingPayload(booking: $0) },
            devices: devices.map { DevicePayload(device: $0) },
            integrations: integrations.map { IntegrationPayload(integration: $0) },
            checklists: checklists.map { ChecklistPayload(item: $0) },
            maintenance: maintenance.map { MaintenancePayload(task: $0) },
            nearby: nearby.map { NearbyPayload(place: $0) },
            activityLogs: logs.map { ActivityPayload(log: $0) },
            manuals: manuals.map { ManualPayload(manual: $0) },
            secureItems: secureItems.map { SecurePayload(item: $0) },
            utilities: utilities.map { UtilityPayload(record: $0) },
            shares: shares.map { SharePayload(record: $0) },
            settings: SettingsPayload(
                activeHomeId: UserDefaults.standard.string(forKey: "activeHomeId") ?? "",
                hasCompletedOnboarding: UserDefaults.standard.bool(forKey: "hasCompletedOnboarding"),
                minpakuModeEnabled: UserDefaults.standard.bool(forKey: "minpakuModeEnabled")
            )
        )

        return try JSONEncoder().encode(payload)
    }

    private func importBackupPayload(_ data: Data, into context: ModelContext) throws -> Int {
        let payload = try JSONDecoder().decode(CloudBackupPayload.self, from: data)
        var imported = 0

        let existingHomes = (try? context.fetch(FetchDescriptor<Home>())) ?? []
        let existingIds = Set(existingHomes.map(\.id))

        for hp in payload.homes where !existingIds.contains(hp.id) {
            let home = Home(name: hp.name, sortOrder: hp.sortOrder)
            home.id = hp.id
            home.address = hp.address
            home.doorCode = hp.doorCode
            home.wifiPassword = hp.wifiPassword
            home.switchBotToken = hp.switchBotToken
            home.switchBotSecret = hp.switchBotSecret
            home.hueBridgeIP = hp.hueBridgeIP
            home.hueUsername = hp.hueUsername
            home.sesameApiKey = hp.sesameApiKey
            home.sesameDeviceUUIDs = hp.sesameDeviceUUIDs
            home.qrioApiKey = hp.qrioApiKey
            home.qrioDeviceIds = hp.qrioDeviceIds
            home.autolockEnabled = hp.autolockEnabled
            home.autolockBotDeviceId = hp.autolockBotDeviceId
            home.autolockRoomNumber = hp.autolockRoomNumber
            home.latitude = hp.latitude
            home.longitude = hp.longitude
            home.geofenceRadius = hp.geofenceRadius
            home.geofenceEnabled = hp.geofenceEnabled
            home.businessType = hp.businessType
            home.beds24ApiKey = hp.beds24ApiKey
            home.beds24RefreshToken = hp.beds24RefreshToken
            home.minpakuNumber = hp.minpakuNumber
            home.minpakuNights = hp.minpakuNights
            home.airbnbICalURL = hp.airbnbICalURL
            home.jalanICalURL = hp.jalanICalURL
            home.backgroundImageURL = hp.backgroundImageURL
            context.insert(home)

            // Auto-download background image from URL
            if !hp.backgroundImageURL.isEmpty, let url = URL(string: hp.backgroundImageURL) {
                Task {
                    if let (data, _) = try? await URLSession.shared.data(from: url),
                       let img = UIImage(data: data),
                       let compressed = img.jpegData(compressionQuality: 0.7) {
                        await MainActor.run {
                            home.backgroundImageData = compressed
                            try? context.save()
                        }
                    }
                }
            }
            imported += 1
        }

        // Bookings
        let existingBookings = Set((try? context.fetch(FetchDescriptor<Booking>()))?.map(\.id) ?? [])
        for bp in payload.bookings where !existingBookings.contains(bp.id) {
            let b = Booking(
                id: bp.id, guestName: bp.guestName, guestEmail: bp.guestEmail,
                guestPhone: bp.guestPhone, platform: bp.platform, homeId: bp.homeId,
                externalId: bp.externalId, checkIn: bp.checkIn, checkOut: bp.checkOut,
                roomCount: bp.roomCount, totalAmount: bp.totalAmount,
                status: bp.status, notes: bp.notes,
                autoUnlock: bp.autoUnlock, autoLight: bp.autoLight,
                cleaningDone: bp.cleaningDone
            )
            context.insert(b)
            imported += 1
        }

        // Settings
        if let s = payload.settings {
            if !s.activeHomeId.isEmpty {
                UserDefaults.standard.set(s.activeHomeId, forKey: "activeHomeId")
            }
            UserDefaults.standard.set(s.hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
            UserDefaults.standard.set(s.minpakuModeEnabled, forKey: "minpakuModeEnabled")
        }

        try? context.save()
        return imported
    }

    // MARK: - Keychain Helpers

    private func saveKeychain(key: String, value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = value.data(using: .utf8)!
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    private func loadKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

enum SyncError: Error, LocalizedError {
    case network, rateLimited, invalidCode, notLoggedIn
    case uploadFailed, noBackupFound, decryptionFailed, encryptionFailed
    case keyNotFound, serverError(String)

    var errorDescription: String? {
        switch self {
        case .network: return "ネットワークエラー"
        case .rateLimited: return "リクエスト制限中です。しばらく待ってください。"
        case .invalidCode: return "確認コードが正しくないか期限切れです"
        case .notLoggedIn: return "ログインしてください"
        case .uploadFailed: return "バックアップの保存に失敗しました"
        case .noBackupFound: return "クラウドにバックアップが見つかりません"
        case .decryptionFailed: return "データの復号に失敗しました。パスフレーズを確認してください。"
        case .encryptionFailed: return "暗号化に失敗しました"
        case .keyNotFound: return "暗号鍵が見つかりません。パスフレーズを入力してください。"
        case .serverError(let msg): return msg
        }
    }
}

// MARK: - Backup Payload Types

struct CloudBackupPayload: Codable {
    let version: Int
    let createdAt: Date
    let homes: [HomePayload]
    let bookings: [BookingPayload]
    let devices: [DevicePayload]
    let integrations: [IntegrationPayload]
    let checklists: [ChecklistPayload]
    let maintenance: [MaintenancePayload]
    let nearby: [NearbyPayload]
    let activityLogs: [ActivityPayload]
    let manuals: [ManualPayload]
    let secureItems: [SecurePayload]
    let utilities: [UtilityPayload]
    let shares: [SharePayload]
    let settings: SettingsPayload?
}

struct HomePayload: Codable {
    let id, name, address: String
    let sortOrder: Int
    let doorCode, wifiPassword: String
    let switchBotToken, switchBotSecret: String
    let hueBridgeIP, hueUsername: String
    let sesameApiKey, sesameDeviceUUIDs: String
    let qrioApiKey, qrioDeviceIds: String
    let autolockEnabled: Bool
    let autolockBotDeviceId, autolockRoomNumber: String
    let latitude, longitude, geofenceRadius: Double
    let geofenceEnabled: Bool
    let businessType: String
    let beds24ApiKey, beds24RefreshToken: String
    let minpakuNumber: String
    let minpakuNights: Int
    let airbnbICalURL, jalanICalURL: String
    let backgroundImageURL: String

    init(home: Home) {
        id = home.id; name = home.name; address = home.address; sortOrder = home.sortOrder
        doorCode = home.doorCode; wifiPassword = home.wifiPassword
        switchBotToken = home.switchBotToken; switchBotSecret = home.switchBotSecret
        hueBridgeIP = home.hueBridgeIP; hueUsername = home.hueUsername
        sesameApiKey = home.sesameApiKey; sesameDeviceUUIDs = home.sesameDeviceUUIDs
        qrioApiKey = home.qrioApiKey; qrioDeviceIds = home.qrioDeviceIds
        autolockEnabled = home.autolockEnabled
        autolockBotDeviceId = home.autolockBotDeviceId; autolockRoomNumber = home.autolockRoomNumber
        latitude = home.latitude; longitude = home.longitude; geofenceRadius = home.geofenceRadius
        geofenceEnabled = home.geofenceEnabled; businessType = home.businessType
        beds24ApiKey = home.beds24ApiKey; beds24RefreshToken = home.beds24RefreshToken
        minpakuNumber = home.minpakuNumber; minpakuNights = home.minpakuNights
        airbnbICalURL = home.airbnbICalURL; jalanICalURL = home.jalanICalURL
        backgroundImageURL = home.backgroundImageURL
    }
}

struct BookingPayload: Codable {
    let id, homeId, guestName, guestEmail, guestPhone: String
    let platform, externalId, status, notes: String
    let checkIn, checkOut: Date
    let roomCount, totalAmount: Int
    let autoUnlock, autoLight, cleaningDone: Bool

    init(booking: Booking) {
        id = booking.id; homeId = booking.homeId; guestName = booking.guestName
        guestEmail = booking.guestEmail; guestPhone = booking.guestPhone
        platform = booking.platform; externalId = booking.externalId
        status = booking.status; notes = booking.notes
        checkIn = booking.checkIn; checkOut = booking.checkOut
        roomCount = booking.roomCount; totalAmount = booking.totalAmount
        autoUnlock = booking.autoUnlock; autoLight = booking.autoLight
        cleaningDone = booking.cleaningDone
    }
}

struct DevicePayload: Codable {
    let id, homeId, name, type, platform, deviceId: String
    init(device: SmartDevice) {
        id = device.id; homeId = device.homeId; name = device.name
        type = device.type; platform = device.platform; deviceId = device.deviceId
    }
}

struct IntegrationPayload: Codable {
    let id, homeId, name, platform, credentialsJSON: String
    let isEnabled: Bool
    init(integration: DeviceIntegration) {
        id = integration.id; homeId = integration.homeId; name = integration.name
        platform = integration.platform; credentialsJSON = integration.credentialsJSON
        isEnabled = integration.isEnabled
    }
}

struct ChecklistPayload: Codable {
    let id, homeId, title, category: String
    let isCompleted: Bool
    init(item: ChecklistItem) {
        id = item.id; homeId = item.homeId; title = item.title
        category = item.category; isCompleted = item.isCompleted
    }
}

struct MaintenancePayload: Codable {
    let id, homeId, title: String
    let intervalDays: Int
    let lastCompletedAt: Date?
    init(task: MaintenanceTask) {
        id = task.id; homeId = task.homeId; title = task.title
        intervalDays = task.intervalDays; lastCompletedAt = task.lastCompletedAt
    }
}

struct NearbyPayload: Codable {
    let id, homeId, name, category, address: String
    init(place: NearbyPlace) {
        id = place.id; homeId = place.homeId; name = place.name
        category = place.category; address = place.address
    }
}

struct ActivityPayload: Codable {
    let id, homeId, action, detail, actor, deviceName: String
    let timestamp: Date
    init(log: ActivityLog) {
        id = log.id; homeId = log.homeId; action = log.action
        detail = log.detail; actor = log.actor; deviceName = log.deviceName
        timestamp = log.timestamp
    }
}

struct ManualPayload: Codable {
    let id, homeId, sections: String
    init(manual: HouseManual) {
        id = manual.id; homeId = manual.homeId; sections = manual.sections
    }
}

struct SecurePayload: Codable {
    let id, homeId, title, category, encryptedValue: String
    init(item: SecureItem) {
        id = item.id; homeId = item.homeId; title = item.title
        category = item.category; encryptedValue = item.encryptedValue
    }
}

struct UtilityPayload: Codable {
    let id, homeId, category: String
    let amount: Int
    let month: String
    init(record: UtilityRecord) {
        id = record.id; homeId = record.homeId; category = record.category
        amount = record.amount; month = record.month
    }
}

struct SharePayload: Codable {
    let id, homeId, recipientName, role, token, ownerToken: String
    let expiresAt: Date?
    let revoked: Bool
    init(record: ShareRecord) {
        id = record.id; homeId = record.homeId; recipientName = record.recipientName
        role = record.role; token = record.token; ownerToken = record.ownerToken
        expiresAt = record.expiresAt; revoked = record.revoked
    }
}

struct SettingsPayload: Codable {
    let activeHomeId: String
    let hasCompletedOnboarding: Bool
    let minpakuModeEnabled: Bool
}
