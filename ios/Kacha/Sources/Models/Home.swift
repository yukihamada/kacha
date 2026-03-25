import Foundation
import SwiftData

@Model
final class Home {
    var id: String
    var name: String
    var address: String
    var sortOrder: Int
    var createdAt: Date

    // Door & Guest info
    var doorCode: String
    var wifiPassword: String

    // SwitchBot
    var switchBotToken: String
    var switchBotSecret: String

    // Philips Hue
    var hueBridgeIP: String
    var hueUsername: String

    // Sesame (CANDY HOUSE)
    var sesameApiKey: String
    var sesameDeviceUUIDs: String   // comma-separated

    // Qrio Lock
    var qrioApiKey: String
    var qrioDeviceIds: String       // comma-separated

    // Beds24
    var beds24ApiKey: String
    var beds24RefreshToken: String

    // iCal (民泊モード)
    var airbnbICalURL: String
    var jalanICalURL: String
    var icalLastSync: Double

    // Auto-lock (building entrance)
    var autolockEnabled: Bool        // master toggle
    var autolockBotDeviceId: String  // SwitchBot Bot device ID for intercom unlock
    var autolockRoomNumber: String   // room number to display in guide

    // Geofence
    var latitude: Double
    var longitude: Double
    var geofenceRadius: Double       // meters, 0 = disabled
    var geofenceEnabled: Bool

    // Business type: "none", "minpaku", "ryokan"
    var businessType: String
    var minpakuNumber: String
    var minpakuNights: Int

    init(name: String, sortOrder: Int = 0) {
        self.id = UUID().uuidString
        self.name = name
        self.address = ""
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.doorCode = ""
        self.wifiPassword = ""
        self.switchBotToken = ""
        self.switchBotSecret = ""
        self.hueBridgeIP = ""
        self.hueUsername = ""
        self.sesameApiKey = ""
        self.sesameDeviceUUIDs = ""
        self.qrioApiKey = ""
        self.qrioDeviceIds = ""
        self.autolockEnabled = false
        self.autolockBotDeviceId = ""
        self.autolockRoomNumber = ""
        self.latitude = 0
        self.longitude = 0
        self.geofenceRadius = 200
        self.geofenceEnabled = false
        self.beds24ApiKey = ""
        self.beds24RefreshToken = ""
        self.airbnbICalURL = ""
        self.jalanICalURL = ""
        self.icalLastSync = 0
        self.businessType = "none"
        self.minpakuNumber = ""
        self.minpakuNights = 0
    }

    /// ホーム切替時にAppStorageへ同期（DeviceView等が引き続き動作するよう）
    func syncToAppStorage() {
        // Only non-sensitive data in UserDefaults
        // API keys/tokens/passwords are in SwiftData + Keychain backup only
        let d = UserDefaults.standard
        d.set(name,            forKey: "facilityName")
        d.set(address,         forKey: "facilityAddress")
        d.set(minpakuNumber,   forKey: "minpakuNumber")
        d.set(minpakuNights,   forKey: "minpakuNights")
    }
}
