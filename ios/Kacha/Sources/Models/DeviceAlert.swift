import Foundation
import SwiftData

// MARK: - DeviceAlert
// スマートデバイス異常検知アラートのSwiftDataモデル

@Model
final class DeviceAlert {
    var id: String
    var homeId: String
    var deviceName: String
    var alertType: String       // AlertType.rawValue
    var message: String
    var severity: String        // "warning" | "critical"
    var createdAt: Date
    var resolvedAt: Date?
    var isResolved: Bool

    init(
        id: String = UUID().uuidString,
        homeId: String,
        deviceName: String,
        alertType: String,
        message: String,
        severity: String,
        createdAt: Date = Date(),
        resolvedAt: Date? = nil,
        isResolved: Bool = false
    ) {
        self.id = id
        self.homeId = homeId
        self.deviceName = deviceName
        self.alertType = alertType
        self.message = message
        self.severity = severity
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
        self.isResolved = isResolved
    }
}

// MARK: - AlertType

enum AlertType: String, CaseIterable {
    case lowBattery      = "low_battery"
    case unlockAfterCheckout = "unlock_after_checkout"
    case highTemperature = "high_temperature"
    case lowTemperature  = "low_temperature"
    case highHumidity    = "high_humidity"
    case lightLeftOn     = "light_left_on"
    case deviceOffline   = "device_offline"

    var title: String {
        switch self {
        case .lowBattery:           return "電池残量低下"
        case .unlockAfterCheckout:  return "チェックアウト後未施錠"
        case .highTemperature:      return "高温警告"
        case .lowTemperature:       return "低温警告"
        case .highHumidity:         return "高湿度警告"
        case .lightLeftOn:          return "照明つけっぱなし"
        case .deviceOffline:        return "デバイス接続エラー"
        }
    }

    var icon: String {
        switch self {
        case .lowBattery:           return "battery.25percent"
        case .unlockAfterCheckout:  return "lock.open.trianglebadge.exclamationmark.fill"
        case .highTemperature:      return "thermometer.high"
        case .lowTemperature:       return "thermometer.low"
        case .highHumidity:         return "humidity.fill"
        case .lightLeftOn:          return "lightbulb.slash.fill"
        case .deviceOffline:        return "wifi.exclamationmark"
        }
    }

    var defaultSeverity: String {
        switch self {
        case .unlockAfterCheckout:  return "critical"
        case .deviceOffline:        return "critical"
        default:                    return "warning"
        }
    }

    var notificationIdentifierPrefix: String {
        "device_alert_\(rawValue)"
    }
}
