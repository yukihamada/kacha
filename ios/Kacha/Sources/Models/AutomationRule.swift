import Foundation
import SwiftData

// MARK: - AutomationRule (SwiftData model)

@Model
final class AutomationRule {
    var id: String
    var homeId: String
    var sceneName: String
    var triggerRaw: String       // AutomationTrigger raw value
    var actionsJSON: String      // JSON-encoded [AutomationAction]
    var isEnabled: Bool
    var lastExecutedAt: Date?
    var createdAt: Date

    init(
        homeId: String,
        sceneName: String,
        trigger: AutomationTrigger,
        actions: [AutomationAction],
        isEnabled: Bool = true
    ) {
        self.id = UUID().uuidString
        self.homeId = homeId
        self.sceneName = sceneName
        self.triggerRaw = trigger.rawValue
        self.actionsJSON = (try? JSONEncoder().encode(actions)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        self.isEnabled = isEnabled
        self.lastExecutedAt = nil
        self.createdAt = Date()
    }

    var trigger: AutomationTrigger {
        AutomationTrigger(rawValue: triggerRaw) ?? .manual
    }

    var actions: [AutomationAction] {
        guard let data = actionsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([AutomationAction].self, from: data)
        else { return [] }
        return decoded
    }

    func updateActions(_ actions: [AutomationAction]) {
        actionsJSON = (try? JSONEncoder().encode(actions)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    func updateTrigger(_ trigger: AutomationTrigger) {
        triggerRaw = trigger.rawValue
    }

    // MARK: - Preset generation

    static func presets(homeId: String) -> [AutomationRule] {
        [
            AutomationRule(
                homeId: homeId,
                sceneName: "ウェルカム",
                trigger: .checkIn,
                actions: [
                    .lightsOn(brightness: 70, colorTemp: 2700),
                    .setAC(temp: 24, mode: "cool")
                ]
            ),
            AutomationRule(
                homeId: homeId,
                sceneName: "チェックアウト",
                trigger: .checkOut,
                actions: [
                    .lightsOff,
                    .lockDoor,
                    .setAC(temp: 26, mode: "off")
                ]
            ),
            AutomationRule(
                homeId: homeId,
                sceneName: "おやすみ",
                trigger: .manual,
                actions: [
                    .lightsOn(brightness: 10, colorTemp: 2200),
                    .lockDoor
                ]
            ),
            AutomationRule(
                homeId: homeId,
                sceneName: "お出かけ",
                trigger: .manual,
                actions: [
                    .allOff,
                    .lockDoor
                ]
            ),
            AutomationRule(
                homeId: homeId,
                sceneName: "パーティー",
                trigger: .manual,
                actions: [
                    .lightsOn(brightness: 100, colorTemp: 4000)
                ]
            )
        ]
    }
}
