import Foundation
import SwiftData

@Model
final class ActivityLog {
    var id: String
    var homeId: String
    var action: String       // "lock", "unlock", "light_on", "light_off", "scene", "share_create", "share_revoke", etc.
    var detail: String       // human-readable description
    var actor: String        // "オーナー", guest name, or "システム"
    var deviceName: String   // which device was affected
    var timestamp: Date

    init(homeId: String, action: String, detail: String, actor: String = "オーナー", deviceName: String = "") {
        self.id = UUID().uuidString
        self.homeId = homeId
        self.action = action
        self.detail = detail
        self.actor = actor
        self.deviceName = deviceName
        self.timestamp = Date()
    }

    var icon: String {
        switch action {
        case "lock":          return "lock.fill"
        case "unlock":        return "lock.open.fill"
        case "light_on":      return "lightbulb.fill"
        case "light_off":     return "lightbulb.slash"
        case "scene":         return "theatermasks.fill"
        case "share_create":  return "person.badge.plus"
        case "share_revoke":  return "person.badge.minus"
        case "checklist":     return "checklist"
        case "maintenance":   return "wrench.and.screwdriver"
        default:              return "note.text"
        }
    }

    var iconColor: String {
        switch action {
        case "lock":          return "EF4444"
        case "unlock":        return "10B981"
        case "light_on":      return "F59E0B"
        case "light_off":     return "7a7a95"
        case "scene":         return "E8A838"
        case "share_create":  return "3B9FE8"
        case "share_revoke":  return "EF4444"
        default:              return "7a7a95"
        }
    }
}

// MARK: - Logger helper

struct ActivityLogger {
    static func log(
        context: ModelContext,
        homeId: String,
        action: String,
        detail: String,
        actor: String = "オーナー",
        deviceName: String = ""
    ) {
        let entry = ActivityLog(
            homeId: homeId,
            action: action,
            detail: detail,
            actor: actor,
            deviceName: deviceName
        )
        context.insert(entry)
    }
}
