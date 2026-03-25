import Foundation
import SwiftData
import UserNotifications

// MARK: - AutomationTrigger

enum AutomationTrigger: String, Codable, CaseIterable {
    case checkIn   = "checkIn"
    case checkOut  = "checkOut"
    case manual    = "manual"
    case schedule  = "schedule"

    var displayName: String {
        switch self {
        case .checkIn:  return "チェックイン時"
        case .checkOut: return "チェックアウト時"
        case .manual:   return "手動実行"
        case .schedule: return "スケジュール"
        }
    }

    var icon: String {
        switch self {
        case .checkIn:  return "arrow.right.square.fill"
        case .checkOut: return "arrow.left.square.fill"
        case .manual:   return "hand.tap.fill"
        case .schedule: return "clock.fill"
        }
    }
}

// MARK: - AutomationAction

enum AutomationAction: Codable, Equatable {
    case lightsOn(brightness: Int, colorTemp: Int)
    case lightsOff
    case lockDoor
    case unlockDoor
    case setAC(temp: Int, mode: String)
    case allOff

    // CodingKeys for associated value encoding
    private enum CodingKeys: String, CodingKey {
        case type, brightness, colorTemp, temp, mode
    }

    private enum ActionType: String, Codable {
        case lightsOn, lightsOff, lockDoor, unlockDoor, setAC, allOff
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .lightsOn(let bri, let ct):
            try container.encode(ActionType.lightsOn, forKey: .type)
            try container.encode(bri, forKey: .brightness)
            try container.encode(ct, forKey: .colorTemp)
        case .lightsOff:
            try container.encode(ActionType.lightsOff, forKey: .type)
        case .lockDoor:
            try container.encode(ActionType.lockDoor, forKey: .type)
        case .unlockDoor:
            try container.encode(ActionType.unlockDoor, forKey: .type)
        case .setAC(let t, let m):
            try container.encode(ActionType.setAC, forKey: .type)
            try container.encode(t, forKey: .temp)
            try container.encode(m, forKey: .mode)
        case .allOff:
            try container.encode(ActionType.allOff, forKey: .type)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ActionType.self, forKey: .type)
        switch type {
        case .lightsOn:
            let bri = try container.decode(Int.self, forKey: .brightness)
            let ct  = try container.decode(Int.self, forKey: .colorTemp)
            self = .lightsOn(brightness: bri, colorTemp: ct)
        case .lightsOff:
            self = .lightsOff
        case .lockDoor:
            self = .lockDoor
        case .unlockDoor:
            self = .unlockDoor
        case .setAC:
            let t = try container.decode(Int.self, forKey: .temp)
            let m = try container.decode(String.self, forKey: .mode)
            self = .setAC(temp: t, mode: m)
        case .allOff:
            self = .allOff
        }
    }

    var displayName: String {
        switch self {
        case .lightsOn(let bri, let ct): return "照明オン \(bri)% / \(ct)K"
        case .lightsOff:                 return "照明オフ"
        case .lockDoor:                  return "ドア施錠"
        case .unlockDoor:                return "ドア解錠"
        case .setAC(let t, let m):       return "エアコン \(t)℃ (\(m))"
        case .allOff:                    return "全デバイスOFF"
        }
    }

    var icon: String {
        switch self {
        case .lightsOn:   return "lightbulb.fill"
        case .lightsOff:  return "lightbulb.slash.fill"
        case .lockDoor:   return "lock.fill"
        case .unlockDoor: return "lock.open.fill"
        case .setAC:      return "air.conditioner.horizontal.fill"
        case .allOff:     return "power.circle.fill"
        }
    }
}

// MARK: - AutomationScene (value type for UI / presets)

struct AutomationScene: Identifiable {
    let id: String
    let name: String
    let icon: String
    let color: SceneColor
    let trigger: AutomationTrigger
    var actions: [AutomationAction]
    var isEnabled: Bool

    enum SceneColor: String {
        case amber, teal, indigo, rose, purple

        var gradient: [String] { // CSS-style color names, resolved in SwiftUI extension
            switch self {
            case .amber:  return ["#F59E0B", "#92400E"]
            case .teal:   return ["#14B8A6", "#0F4C40"]
            case .indigo: return ["#6366F1", "#1E1B4B"]
            case .rose:   return ["#F43F5E", "#4C0519"]
            case .purple: return ["#A855F7", "#3B0764"]
            }
        }
    }

    static let presets: [AutomationScene] = [
        AutomationScene(
            id: "welcome",
            name: "ウェルカム",
            icon: "figure.walk.arrival",
            color: .amber,
            trigger: .checkIn,
            actions: [
                .lightsOn(brightness: 70, colorTemp: 2700),
                .setAC(temp: 24, mode: "cool")
            ],
            isEnabled: true
        ),
        AutomationScene(
            id: "checkout",
            name: "チェックアウト",
            icon: "figure.walk.departure",
            color: .teal,
            trigger: .checkOut,
            actions: [.lightsOff, .lockDoor, .setAC(temp: 26, mode: "off")],
            isEnabled: true
        ),
        AutomationScene(
            id: "sleep",
            name: "おやすみ",
            icon: "moon.stars.fill",
            color: .indigo,
            trigger: .manual,
            actions: [.lightsOn(brightness: 10, colorTemp: 2200), .lockDoor],
            isEnabled: true
        ),
        AutomationScene(
            id: "outing",
            name: "お出かけ",
            icon: "car.fill",
            color: .rose,
            trigger: .manual,
            actions: [.allOff, .lockDoor],
            isEnabled: true
        ),
        AutomationScene(
            id: "party",
            name: "パーティー",
            icon: "party.popper.fill",
            color: .purple,
            trigger: .manual,
            actions: [.lightsOn(brightness: 100, colorTemp: 4000)],
            isEnabled: true
        )
    ]
}

// MARK: - AutomationExecutionRecord

struct AutomationExecutionRecord: Identifiable {
    let id: UUID
    let sceneName: String
    let executedAt: Date
    let success: Bool
    let errorMessage: String?
}

// MARK: - AutomationEngine

@MainActor
final class AutomationEngine: ObservableObject {
    static let shared = AutomationEngine()

    @Published var executionHistory: [AutomationExecutionRecord] = []
    @Published var isExecuting: Set<String> = []   // scene IDs currently running

    // MARK: - Scene Execution

    func executeScene(
        _ scene: AutomationScene,
        switchBotToken: String,
        switchBotSecret: String,
        hueBridgeIP: String,
        hueUsername: String,
        sesameUUIDs: [String],
        sesameApiKey: String
    ) async {
        guard !isExecuting.contains(scene.id) else { return }
        isExecuting.insert(scene.id)
        defer { isExecuting.remove(scene.id) }

        var errors: [String] = []

        for action in scene.actions {
            do {
                try await executeAction(
                    action,
                    switchBotToken: switchBotToken,
                    switchBotSecret: switchBotSecret,
                    hueBridgeIP: hueBridgeIP,
                    hueUsername: hueUsername,
                    sesameUUIDs: sesameUUIDs,
                    sesameApiKey: sesameApiKey
                )
            } catch {
                errors.append("\(action.displayName): \(error.localizedDescription)")
            }
        }

        let record = AutomationExecutionRecord(
            id: UUID(),
            sceneName: scene.name,
            executedAt: Date(),
            success: errors.isEmpty,
            errorMessage: errors.isEmpty ? nil : errors.joined(separator: "\n")
        )
        executionHistory.insert(record, at: 0)
        if executionHistory.count > 50 { executionHistory.removeLast() }
    }

    // MARK: - Action dispatch

    private func executeAction(
        _ action: AutomationAction,
        switchBotToken: String,
        switchBotSecret: String,
        hueBridgeIP: String,
        hueUsername: String,
        sesameUUIDs: [String],
        sesameApiKey: String
    ) async throws {
        let hue = HueClient.shared
        let sb  = SwitchBotClient.shared

        switch action {
        case .lightsOn(let brightness, let colorTemp):
            guard !hueBridgeIP.isEmpty else { return }
            // Ensure lights list is populated
            if hue.lights.isEmpty {
                _ = try await hue.fetchLights(bridgeIP: hueBridgeIP, username: hueUsername)
            }
            // ct in Mired: 1_000_000 / K
            let ct = max(153, min(500, 1_000_000 / max(1, colorTemp)))
            let bri = max(1, min(254, Int(Double(brightness) / 100.0 * 254)))
            for light in hue.lights {
                try await hue.setState(
                    lightId: light.id,
                    on: true,
                    bri: bri,
                    ct: ct,
                    bridgeIP: hueBridgeIP,
                    username: hueUsername
                )
            }

        case .lightsOff:
            guard !hueBridgeIP.isEmpty else { return }
            if hue.lights.isEmpty {
                _ = try? await hue.fetchLights(bridgeIP: hueBridgeIP, username: hueUsername)
            }
            try await hue.allOff(bridgeIP: hueBridgeIP, username: hueUsername)

        case .allOff:
            // Lights off
            if !hueBridgeIP.isEmpty {
                if hue.lights.isEmpty {
                    _ = try? await hue.fetchLights(bridgeIP: hueBridgeIP, username: hueUsername)
                }
                try? await hue.allOff(bridgeIP: hueBridgeIP, username: hueUsername)
            }
            // SwitchBot plugs/bots off
            if !switchBotToken.isEmpty {
                if sb.devices.isEmpty {
                    _ = try? await sb.fetchDevices(token: switchBotToken, secret: switchBotSecret)
                }
                let plugs = sb.devices.filter {
                    let t = $0.deviceType.lowercased()
                    return t.contains("plug") || t.contains("bot") || t.contains("switch")
                }
                for d in plugs {
                    try? await sb.sendCommand(deviceId: d.deviceId, command: "turnOff",
                                              token: switchBotToken, secret: switchBotSecret)
                }
            }

        case .lockDoor:
            if !sesameApiKey.isEmpty {
                for uuid in sesameUUIDs {
                    try? await SesameClient.shared.lock(uuid: uuid, apiKey: sesameApiKey)
                }
            }
            if !switchBotToken.isEmpty {
                if sb.devices.isEmpty {
                    _ = try? await sb.fetchDevices(token: switchBotToken, secret: switchBotSecret)
                }
                let locks = sb.devices.filter { $0.deviceType.lowercased().contains("lock") }
                for d in locks {
                    try await sb.lock(deviceId: d.deviceId, token: switchBotToken, secret: switchBotSecret)
                }
            }

        case .unlockDoor:
            if !sesameApiKey.isEmpty {
                for uuid in sesameUUIDs {
                    try? await SesameClient.shared.unlock(uuid: uuid, apiKey: sesameApiKey)
                }
            }
            if !switchBotToken.isEmpty {
                if sb.devices.isEmpty {
                    _ = try? await sb.fetchDevices(token: switchBotToken, secret: switchBotSecret)
                }
                let locks = sb.devices.filter { $0.deviceType.lowercased().contains("lock") }
                for d in locks {
                    try await sb.unlock(deviceId: d.deviceId, token: switchBotToken, secret: switchBotSecret)
                }
            }

        case .setAC(let temp, let mode):
            // NatureRemo / SwitchBot Hub IR — send via SwitchBot infrared command
            // Payload format: "<temp>,<mode>,1,0" (SwitchBot AC command)
            guard !switchBotToken.isEmpty else { return }
            if sb.devices.isEmpty {
                _ = try? await sb.fetchDevices(token: switchBotToken, secret: switchBotSecret)
            }
            let acs = sb.devices.filter {
                let t = $0.deviceType.lowercased()
                return t.contains("air") || t.contains("ac") || t.contains("conditioner")
            }
            for d in acs {
                let modeNum: String
                switch mode.lowercased() {
                case "cool": modeNum = "2"
                case "heat": modeNum = "4"
                case "dry":  modeNum = "3"
                case "fan":  modeNum = "6"
                default:     modeNum = "1" // auto / off treated as auto
                }
                // "temperature,mode,fanSpeed,power" — power 0=on,1=off for setAll
                let parameter = "\(temp),\(modeNum),1,0"
                try? await sb.sendCommand(deviceId: d.deviceId, command: "setAll",
                                          parameter: parameter,
                                          token: switchBotToken, secret: switchBotSecret)
            }
        }
    }

    // MARK: - Check-in pre-trigger (call from BackgroundRefresh)

    /// チェックイン30分前に「ウェルカム」シーンを実行する。
    /// BackgroundRefreshから呼び出す。
    func runPreCheckInIfNeeded(
        bookings: [Booking],
        switchBotToken: String,
        switchBotSecret: String,
        hueBridgeIP: String,
        hueUsername: String,
        sesameUUIDs: [String],
        sesameApiKey: String
    ) async {
        let now = Date()
        let threshold: TimeInterval = 30 * 60   // 30 minutes

        let upcoming = bookings.filter { booking in
            guard booking.status == "upcoming" else { return false }
            let diff = booking.checkIn.timeIntervalSince(now)
            return diff > 0 && diff <= threshold
        }

        guard !upcoming.isEmpty else { return }

        if let welcomeScene = AutomationScene.presets.first(where: { $0.id == "welcome" }) {
            await executeScene(
                welcomeScene,
                switchBotToken: switchBotToken,
                switchBotSecret: switchBotSecret,
                hueBridgeIP: hueBridgeIP,
                hueUsername: hueUsername,
                sesameUUIDs: sesameUUIDs,
                sesameApiKey: sesameApiKey
            )
        }
    }
}
