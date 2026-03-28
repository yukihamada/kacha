import Foundation
import WatchConnectivity
import Combine

/// Watch側のWatchConnectivityManager
/// iPhoneからactiveHomeの情報を受け取り、施錠/解錠コマンドをiPhoneに送信する
final class WatchConnectivityManager: NSObject, ObservableObject {

    static let shared = WatchConnectivityManager()

    // MARK: - Published State

    @Published var homeName: String = ""
    @Published var homeAddress: String = ""
    @Published var isLocked: Bool = true
    @Published var isConnected: Bool = false
    @Published var isSending: Bool = false
    @Published var lastError: String?
    @Published var lights: [WatchLightInfo] = []
    @Published var todayCheckIns: [WatchCheckInInfo] = []
    @Published var propertyStatus: String = "" // "vacant" / "occupied" / "cleaning"

    // MARK: - Init

    private override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // MARK: - Commands

    /// 解錠コマンドをiPhoneに送信
    func sendUnlock() {
        sendCommand("unlock")
    }

    /// 施錠コマンドをiPhoneに送信
    func sendLock() {
        sendCommand("lock")
    }

    /// 照明トグルコマンドをiPhoneに送信
    func sendToggleLight(deviceId: String, isOn: Bool) {
        guard WCSession.default.isReachable else {
            lastError = "iPhoneに接続できません"
            return
        }
        let message: [String: Any] = [
            "action": "toggleLight",
            "deviceId": deviceId,
            "isOn": isOn
        ]
        isSending = true
        lastError = nil
        WCSession.default.sendMessage(message, replyHandler: { [weak self] reply in
            DispatchQueue.main.async {
                self?.isSending = false
            }
        }, errorHandler: { [weak self] error in
            DispatchQueue.main.async {
                self?.isSending = false
                self?.lastError = error.localizedDescription
            }
        })
    }

    // MARK: - Private

    private func sendCommand(_ action: String) {
        guard WCSession.default.isReachable else {
            lastError = "iPhoneに接続できません"
            return
        }
        let message: [String: Any] = ["action": action]
        isSending = true
        lastError = nil
        WCSession.default.sendMessage(message, replyHandler: { [weak self] reply in
            DispatchQueue.main.async {
                self?.isSending = false
                if let locked = reply["isLocked"] as? Bool {
                    self?.isLocked = locked
                }
            }
        }, errorHandler: { [weak self] error in
            DispatchQueue.main.async {
                self?.isSending = false
                self?.lastError = error.localizedDescription
            }
        })
    }

    private func applyContext(_ context: [String: Any]) {
        if let name = context["homeName"] as? String {
            homeName = name
        }
        if let address = context["homeAddress"] as? String {
            homeAddress = address
        }
        if let locked = context["isLocked"] as? Bool {
            isLocked = locked
        }
        if let rawLights = context["lights"] as? [[String: Any]] {
            lights = rawLights.compactMap { dict -> WatchLightInfo? in
                guard let id = dict["deviceId"] as? String,
                      let name = dict["name"] as? String,
                      let isOn = dict["isOn"] as? Bool else { return nil }
                return WatchLightInfo(deviceId: id, name: name, isOn: isOn)
            }
        }
        if let rawCheckIns = context["todayCheckIns"] as? [[String: Any]] {
            todayCheckIns = rawCheckIns.compactMap { dict -> WatchCheckInInfo? in
                guard let name = dict["guestName"] as? String,
                      let time = dict["timeLabel"] as? String else { return nil }
                return WatchCheckInInfo(guestName: name, timeLabel: time)
            }
        }
        if let status = context["propertyStatus"] as? String {
            propertyStatus = status
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isConnected = activationState == .activated
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async {
            self.applyContext(applicationContext)
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async {
            self.applyContext(message)
        }
    }
}

// MARK: - Supporting Types

struct WatchLightInfo: Identifiable {
    let deviceId: String
    let name: String
    let isOn: Bool
    var id: String { deviceId }
}

struct WatchCheckInInfo: Identifiable {
    let guestName: String
    let timeLabel: String
    var id: String { "\(guestName)-\(timeLabel)" }
}
