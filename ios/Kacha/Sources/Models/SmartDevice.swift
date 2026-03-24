import Foundation
import SwiftData

@Model
final class SmartDevice {
    var id: String
    var deviceId: String
    var name: String
    var type: String      // "lock" | "light" | "switch" | "hub"
    var platform: String  // "switchbot" | "hue" | "sesame" | "qrio" | "nuki" | "igloohome"
    var homeId: String = ""
    var roomId: String
    var isOn: Bool
    var isLocked: Bool
    var brightness: Int   // 0-100 for lights
    var colorTemp: Int    // 2000-6500K
    var lastSeen: Date

    init(
        id: String = UUID().uuidString,
        deviceId: String,
        name: String,
        type: String,
        platform: String,
        homeId: String = "",
        roomId: String = "",
        isOn: Bool = false,
        isLocked: Bool = true,
        brightness: Int = 100,
        colorTemp: Int = 4000,
        lastSeen: Date = Date()
    ) {
        self.id = id
        self.deviceId = deviceId
        self.name = name
        self.type = type
        self.platform = platform
        self.homeId = homeId
        self.roomId = roomId
        self.isOn = isOn
        self.isLocked = isLocked
        self.brightness = brightness
        self.colorTemp = colorTemp
        self.lastSeen = lastSeen
    }

    var typeIcon: String {
        switch type {
        case "lock": return "lock.fill"
        case "light": return "lightbulb.fill"
        case "switch": return "switch.2"
        case "hub": return "hub"
        default: return "dot.radiowaves.left.and.right"
        }
    }

    var platformLabel: String {
        switch platform {
        case "switchbot":  return "SwitchBot"
        case "hue":        return "Philips Hue"
        case "sesame":     return "Sesame"
        case "qrio":       return "Qrio Lock"
        case "nuki":       return "Nuki"
        case "igloohome":  return "igloohome"
        default:           return platform
        }
    }
}
