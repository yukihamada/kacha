import Foundation
import WatchConnectivity
import SwiftData

/// iPhone側のWatchConnectivityManager
/// activeHomeの施錠状態・照明情報をWatchに転送し、
/// Watchからの施錠/解錠コマンドをSwitchBotClient経由で実行する
@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {

    static let shared = WatchConnectivityManager()

    // MARK: - State

    @Published var isWatchReachable: Bool = false

    /// 外部からモデルコンテキストを注入してもらう
    var modelContainer: ModelContainer?

    // MARK: - Init

    private override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // MARK: - Public: Push state to Watch

    /// activeHomeの情報をWatchに送信する（ビューが更新されるたびに呼ぶ）
    func updateWatch(home: Home, devices: [SmartDevice]) {
        guard WCSession.default.activationState == .activated else { return }

        let lockDevices = devices.filter { $0.type == "lock" }
        let isLocked = lockDevices.first?.isLocked ?? true

        let lightInfos: [[String: Any]] = devices
            .filter { $0.type == "light" }
            .map { ["deviceId": $0.deviceId, "name": $0.name, "isOn": $0.isOn] }

        let context: [String: Any] = [
            "homeName": home.name,
            "homeAddress": home.address,
            "isLocked": isLocked,
            "lights": lightInfos
        ]

        do {
            try WCSession.default.updateApplicationContext(context)
        } catch {
            // updateApplicationContextが失敗した場合はsendMessageにフォールバック
            if WCSession.default.isReachable {
                WCSession.default.sendMessage(context, replyHandler: nil, errorHandler: nil)
            }
        }
    }

    // MARK: - Private: Command Execution

    private func executeLockCommand(_ action: String, replyHandler: @escaping ([String: Any]) -> Void) {
        guard let container = modelContainer else {
            replyHandler(["error": "container unavailable"])
            return
        }
        Task {
            let context = container.mainContext
            guard let activeHomeId = UserDefaults.standard.string(forKey: "activeHomeId"),
                  let home = (try? context.fetch(FetchDescriptor<Home>()))?.first(where: { $0.id == activeHomeId }),
                  !home.switchBotToken.isEmpty else {
                await MainActor.run { replyHandler(["error": "home not configured"]) }
                return
            }

            let devices = (try? context.fetch(FetchDescriptor<SmartDevice>())) ?? []
            let lockDevices = devices.filter {
                $0.homeId == activeHomeId && $0.type == "lock" && $0.platform == "switchbot"
            }
            guard let lockDevice = lockDevices.first else {
                await MainActor.run { replyHandler(["error": "no lock device"]) }
                return
            }

            do {
                let client = SwitchBotClient.shared
                if action == "unlock" {
                    try await client.unlock(
                        deviceId: lockDevice.deviceId,
                        token: home.switchBotToken,
                        secret: home.switchBotSecret
                    )
                    lockDevice.isLocked = false
                } else {
                    try await client.lock(
                        deviceId: lockDevice.deviceId,
                        token: home.switchBotToken,
                        secret: home.switchBotSecret
                    )
                    lockDevice.isLocked = true
                }
                try? context.save()
                let newState = lockDevice.isLocked
                await MainActor.run {
                    replyHandler(["isLocked": newState])
                    // Watchのコンテキストを最新状態に更新
                    self.updateWatch(home: home, devices: devices)
                }
            } catch {
                await MainActor.run {
                    replyHandler(["error": error.localizedDescription])
                }
            }
        }
    }

    private func executeLightCommand(deviceId: String, isOn: Bool, replyHandler: @escaping ([String: Any]) -> Void) {
        guard let container = modelContainer else {
            replyHandler(["error": "container unavailable"])
            return
        }
        Task {
            let context = container.mainContext
            guard let activeHomeId = UserDefaults.standard.string(forKey: "activeHomeId"),
                  let home = (try? context.fetch(FetchDescriptor<Home>()))?.first(where: { $0.id == activeHomeId }),
                  !home.switchBotToken.isEmpty else {
                await MainActor.run { replyHandler(["error": "home not configured"]) }
                return
            }

            do {
                let client = SwitchBotClient.shared
                if isOn {
                    try await client.turnOn(deviceId: deviceId, token: home.switchBotToken, secret: home.switchBotSecret)
                } else {
                    try await client.turnOff(deviceId: deviceId, token: home.switchBotToken, secret: home.switchBotSecret)
                }
                // ローカルのSmartDeviceも更新
                let devices = (try? context.fetch(FetchDescriptor<SmartDevice>())) ?? []
                if let device = devices.first(where: { $0.deviceId == deviceId }) {
                    device.isOn = isOn
                    try? context.save()
                }
                await MainActor.run { replyHandler(["success": true]) }
            } catch {
                await MainActor.run { replyHandler(["error": error.localizedDescription]) }
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.isWatchReachable = activationState == .activated && session.isWatchAppInstalled
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isWatchReachable = session.isWatchAppInstalled && session.activationState == .activated
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard let action = message["action"] as? String else {
            replyHandler(["error": "unknown action"])
            return
        }
        Task { @MainActor in
            switch action {
            case "lock", "unlock":
                self.executeLockCommand(action, replyHandler: replyHandler)
            case "toggleLight":
                let deviceId = message["deviceId"] as? String ?? ""
                let isOn = message["isOn"] as? Bool ?? false
                self.executeLightCommand(deviceId: deviceId, isOn: isOn, replyHandler: replyHandler)
            default:
                replyHandler(["error": "unknown action: \(action)"])
            }
        }
    }
}
