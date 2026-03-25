import Foundation
import CryptoKit

// MARK: - IntentExecutor
// App IntentsはSwiftDataのModelContextに直接アクセスできないため、
// IntentHomeStoreのUserDefaultsキャッシュから認証情報を取得してAPIを呼び出す。
// 各関数はnon-throwing: エラーはResult.messageに含めてSiriに読み上げさせる。

enum IntentExecutor {

    struct Result {
        let success: Bool
        let message: String
    }

    // MARK: - Lock / Unlock

    static func unlock(summary: IntentHomeStore.HomeSummary?) async -> Result {
        guard let s = summary else {
            return Result(success: false, message: "物件が設定されていません。カチャアプリから物件を登録してください。")
        }
        // SwitchBot優先、次にSesame
        if !s.switchBotToken.isEmpty && !s.switchBotSecret.isEmpty {
            return await switchBotLock(action: .unlock, token: s.switchBotToken, secret: s.switchBotSecret, homeName: s.name)
        }
        if !s.sesameApiKey.isEmpty && !s.sesameDeviceUUIDs.isEmpty {
            return await sesameLock(action: .unlock, apiKey: s.sesameApiKey, uuids: s.sesameDeviceUUIDs, homeName: s.name)
        }
        return Result(success: false, message: "\(s.name)のスマートロックが設定されていません。カチャアプリから設定してください。")
    }

    static func lock(summary: IntentHomeStore.HomeSummary?) async -> Result {
        guard let s = summary else {
            return Result(success: false, message: "物件が設定されていません。カチャアプリから物件を登録してください。")
        }
        if !s.switchBotToken.isEmpty && !s.switchBotSecret.isEmpty {
            return await switchBotLock(action: .lock, token: s.switchBotToken, secret: s.switchBotSecret, homeName: s.name)
        }
        if !s.sesameApiKey.isEmpty && !s.sesameDeviceUUIDs.isEmpty {
            return await sesameLock(action: .lock, apiKey: s.sesameApiKey, uuids: s.sesameDeviceUUIDs, homeName: s.name)
        }
        return Result(success: false, message: "\(s.name)のスマートロックが設定されていません。カチャアプリから設定してください。")
    }

    // MARK: - Lights

    static func lightsOn(summary: IntentHomeStore.HomeSummary?) async -> Result {
        guard let s = summary else {
            return Result(success: false, message: "物件が設定されていません。")
        }
        // Hue優先
        if !s.hueBridgeIP.isEmpty && !s.hueUsername.isEmpty {
            return await hueLights(on: true, bridgeIP: s.hueBridgeIP, username: s.hueUsername, homeName: s.name)
        }
        // SwitchBot照明デバイスにフォールバック（turnOn）
        if !s.switchBotToken.isEmpty && !s.switchBotSecret.isEmpty {
            return await switchBotAllLights(on: true, token: s.switchBotToken, secret: s.switchBotSecret, homeName: s.name)
        }
        return Result(success: false, message: "\(s.name)の照明が設定されていません。カチャアプリから設定してください。")
    }

    static func lightsOff(summary: IntentHomeStore.HomeSummary?) async -> Result {
        guard let s = summary else {
            return Result(success: false, message: "物件が設定されていません。")
        }
        if !s.hueBridgeIP.isEmpty && !s.hueUsername.isEmpty {
            return await hueLights(on: false, bridgeIP: s.hueBridgeIP, username: s.hueUsername, homeName: s.name)
        }
        if !s.switchBotToken.isEmpty && !s.switchBotSecret.isEmpty {
            return await switchBotAllLights(on: false, token: s.switchBotToken, secret: s.switchBotSecret, homeName: s.name)
        }
        return Result(success: false, message: "\(s.name)の照明が設定されていません。カチャアプリから設定してください。")
    }

    // MARK: - Check-in Prepare
    // 照明ON → (SwitchBot照明ON) → ドアコード読み上げ の順に実行

    static func checkInPrepare(summary: IntentHomeStore.HomeSummary?) async -> Result {
        guard let s = summary else {
            return Result(success: false, message: "物件が設定されていません。")
        }
        var steps: [String] = []
        var errors: [String] = []

        // Step 1: 照明ON
        let lightsResult = await lightsOn(summary: s)
        if lightsResult.success {
            steps.append("照明をオンにしました")
        } else {
            errors.append("照明: \(lightsResult.message)")
        }

        // Step 2: ドアコード案内（音声で読み上げ）
        if !s.doorCode.isEmpty {
            steps.append("ドアコードは \(s.doorCode) です")
        }

        if steps.isEmpty {
            let errorSummary = errors.joined(separator: "、")
            return Result(success: false, message: "\(s.name)のチェックイン準備でエラーが発生しました。\(errorSummary)")
        }

        let summary_msg = steps.joined(separator: "。")
        let suffix = errors.isEmpty ? "" : "（一部エラー: \(errors.joined(separator: "、"))）"
        return Result(success: true, message: "\(s.name)のチェックイン準備完了。\(summary_msg)\(suffix)")
    }

    // MARK: - Device Status

    static func getDeviceStatus(summary: IntentHomeStore.HomeSummary?) async -> Result {
        guard let s = summary else {
            return Result(success: false, message: "物件が設定されていません。")
        }
        // SwitchBotの施錠状態と電池残量を取得
        if !s.switchBotToken.isEmpty && !s.switchBotSecret.isEmpty {
            return await switchBotStatus(token: s.switchBotToken, secret: s.switchBotSecret, homeName: s.name)
        }
        if !s.sesameApiKey.isEmpty && !s.sesameDeviceUUIDs.isEmpty {
            return await sesameStatus(apiKey: s.sesameApiKey, uuids: s.sesameDeviceUUIDs, homeName: s.name)
        }
        return Result(success: false, message: "\(s.name)のデバイスが設定されていません。")
    }
}

// MARK: - SwitchBot helpers (no @MainActor dependency)

private extension IntentExecutor {

    enum LockAction { case lock, unlock }

    static func makeHeaders(token: String, secret: String) -> [String: String] {
        let nonce = UUID().uuidString
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let stringToSign = token + timestamp + nonce
        let hmac = HMAC<SHA256>.authenticationCode(
            for: Data(stringToSign.utf8),
            using: SymmetricKey(data: Data(secret.utf8))
        )
        let sign = Data(hmac).base64EncodedString().uppercased()
        return [
            "Authorization": token,
            "sign": sign,
            "nonce": nonce,
            "t": timestamp,
            "Content-Type": "application/json"
        ]
    }

    static func switchBotLock(action: LockAction, token: String, secret: String, homeName: String) async -> Result {
        let baseURL = "https://api.switch-bot.com/v1.1"
        // デバイス一覧を取得してロック系デバイスを抽出
        guard let devices = try? await fetchSwitchBotDevices(baseURL: baseURL, token: token, secret: secret) else {
            return Result(success: false, message: "SwitchBotデバイス一覧の取得に失敗しました。ネットワーク接続を確認してください。")
        }
        let lockDevices = devices.filter { isLockType($0.deviceType) }
        if lockDevices.isEmpty {
            return Result(success: false, message: "\(homeName)にSwitchBotロックデバイスが見つかりません。")
        }
        let command = action == .lock ? "lock" : "unlock"
        let actionLabel = action == .lock ? "施錠" : "解錠"
        var failed = 0
        for device in lockDevices {
            do {
                try await sendSwitchBotCommand(
                    baseURL: baseURL,
                    deviceId: device.deviceId,
                    command: command,
                    token: token,
                    secret: secret
                )
            } catch {
                failed += 1
            }
        }
        if failed == lockDevices.count {
            return Result(success: false, message: "\(homeName)の\(actionLabel)に失敗しました。デバイスの状態を確認してください。")
        }
        let count = lockDevices.count - failed
        return Result(success: true, message: "\(homeName)を\(actionLabel)しました（\(count)台）。")
    }

    static func switchBotAllLights(on: Bool, token: String, secret: String, homeName: String) async -> Result {
        let baseURL = "https://api.switch-bot.com/v1.1"
        guard let devices = try? await fetchSwitchBotDevices(baseURL: baseURL, token: token, secret: secret) else {
            return Result(success: false, message: "SwitchBotデバイス一覧の取得に失敗しました。")
        }
        let lightDevices = devices.filter { isLightType($0.deviceType) }
        if lightDevices.isEmpty {
            return Result(success: false, message: "\(homeName)にSwitchBot照明デバイスが見つかりません。")
        }
        let command = on ? "turnOn" : "turnOff"
        let label = on ? "オン" : "オフ"
        var succeeded = 0
        for device in lightDevices {
            if let _ = try? await sendSwitchBotCommand(
                baseURL: baseURL,
                deviceId: device.deviceId,
                command: command,
                token: token,
                secret: secret
            ) {
                succeeded += 1
            }
        }
        guard succeeded > 0 else {
            return Result(success: false, message: "\(homeName)の照明\(label)に失敗しました。")
        }
        return Result(success: true, message: "\(homeName)の照明を\(label)にしました（\(succeeded)台）。")
    }

    static func switchBotStatus(token: String, secret: String, homeName: String) async -> Result {
        let baseURL = "https://api.switch-bot.com/v1.1"
        guard let devices = try? await fetchSwitchBotDevices(baseURL: baseURL, token: token, secret: secret) else {
            return Result(success: false, message: "デバイス情報の取得に失敗しました。")
        }
        let lockDevices = devices.filter { isLockType($0.deviceType) }
        if lockDevices.isEmpty {
            return Result(success: false, message: "\(homeName)にロックデバイスが見つかりません。")
        }
        var parts: [String] = []
        for device in lockDevices {
            guard let status = try? await fetchSwitchBotStatus(
                baseURL: baseURL,
                deviceId: device.deviceId,
                token: token,
                secret: secret
            ) else { continue }
            let lockLabel = (status.lockState ?? "").lowercased() == "locked" ? "施錠中" : "解錠中"
            let batteryLabel = status.battery.map { "電池\($0)%" } ?? ""
            parts.append("\(device.deviceName): \(lockLabel)\(batteryLabel.isEmpty ? "" : "、\(batteryLabel)")")
        }
        if parts.isEmpty {
            return Result(success: false, message: "\(homeName)のデバイス状態を取得できませんでした。")
        }
        return Result(success: true, message: "\(homeName)の状態。\(parts.joined(separator: "。"))")
    }

    // MARK: SwitchBot low-level

    struct SwitchBotDeviceItem: Decodable {
        let deviceId: String
        let deviceName: String
        let deviceType: String
    }

    @discardableResult
    static func sendSwitchBotCommand(
        baseURL: String, deviceId: String, command: String, token: String, secret: String
    ) async throws -> Void {
        guard let url = URL(string: "\(baseURL)/devices/\(deviceId)/commands") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        makeHeaders(token: token, secret: secret).forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let body: [String: Any] = ["command": command, "parameter": "default", "commandType": "command"]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    }

    static func fetchSwitchBotDevices(baseURL: String, token: String, secret: String) async throws -> [SwitchBotDeviceItem] {
        guard let url = URL(string: "\(baseURL)/devices") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        makeHeaders(token: token, secret: secret).forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, _) = try await URLSession.shared.data(for: request)
        struct Resp: Decodable {
            struct Body: Decodable { let deviceList: [SwitchBotDeviceItem] }
            let body: Body?
        }
        return (try JSONDecoder().decode(Resp.self, from: data)).body?.deviceList ?? []
    }

    struct SwitchBotStatusItem: Decodable {
        let lockState: String?
        let battery: Int?
    }

    static func fetchSwitchBotStatus(baseURL: String, deviceId: String, token: String, secret: String) async throws -> SwitchBotStatusItem {
        guard let url = URL(string: "\(baseURL)/devices/\(deviceId)/status") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        makeHeaders(token: token, secret: secret).forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, _) = try await URLSession.shared.data(for: request)
        struct Resp: Decodable {
            let body: SwitchBotStatusItem?
        }
        guard let body = (try JSONDecoder().decode(Resp.self, from: data)).body else {
            throw URLError(.badServerResponse)
        }
        return body
    }

    static func isLockType(_ type: String) -> Bool {
        let t = type.lowercased()
        return t.contains("lock") || t == "bot"
    }

    static func isLightType(_ type: String) -> Bool {
        let t = type.lowercased()
        return t.contains("light") || t.contains("bulb") || t.contains("strip") || t.contains("ceiling")
    }
}

// MARK: - Sesame helpers

private extension IntentExecutor {

    static func sesameLock(action: LockAction, apiKey: String, uuids: String, homeName: String) async -> Result {
        let uuidList = uuids.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let cmdCode = action == .lock ? 82 : 83
        let label = action == .lock ? "施錠" : "解錠"
        var succeeded = 0
        for uuid in uuidList {
            guard let sesameURL = URL(string: "https://app.candyhouse.co/api/sesame2/\(uuid)") else { continue }
            var req = URLRequest(url: sesameURL)
            req.httpMethod = "POST"
            req.addValue(apiKey, forHTTPHeaderField: "x-api-key")
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["cmd": cmdCode, "history": "カチャSiri"])
            req.timeoutInterval = 10
            if let (_, res) = try? await URLSession.shared.data(for: req),
               (200...299).contains((res as? HTTPURLResponse)?.statusCode ?? 0) {
                succeeded += 1
            }
        }
        guard succeeded > 0 else {
            return Result(success: false, message: "\(homeName)のSesame\(label)に失敗しました。")
        }
        return Result(success: true, message: "\(homeName)を\(label)しました（Sesame \(succeeded)台）。")
    }

    static func sesameStatus(apiKey: String, uuids: String, homeName: String) async -> Result {
        let uuidList = uuids.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        struct SesameStatus: Decodable {
            let batteryPercentage: Int?
            let isInLockRange: Bool?
        }
        var parts: [String] = []
        for (i, uuid) in uuidList.enumerated() {
            guard let sesameURL = URL(string: "https://app.candyhouse.co/api/sesame2/\(uuid)") else { continue }
            var req = URLRequest(url: sesameURL)
            req.addValue(apiKey, forHTTPHeaderField: "x-api-key")
            req.timeoutInterval = 10
            guard let (data, _) = try? await URLSession.shared.data(for: req),
                  let status = try? JSONDecoder().decode(SesameStatus.self, from: data) else { continue }
            let lockLabel = (status.isInLockRange ?? true) ? "施錠中" : "解錠中"
            let battery = status.batteryPercentage.map { "電池\($0)%" } ?? ""
            parts.append("Sesame\(i + 1): \(lockLabel)\(battery.isEmpty ? "" : "、\(battery)")")
        }
        if parts.isEmpty {
            return Result(success: false, message: "\(homeName)のSesame状態を取得できませんでした。")
        }
        return Result(success: true, message: "\(homeName)の状態。\(parts.joined(separator: "。"))")
    }
}

// MARK: - Hue helpers

private extension IntentExecutor {

    static func hueLights(on: Bool, bridgeIP: String, username: String, homeName: String) async -> Result {
        // ライト一覧取得
        guard let url = URL(string: "http://\(bridgeIP)/api/\(username)/lights"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]]
        else {
            return Result(success: false, message: "Hueブリッジへの接続に失敗しました。ローカルネットワークを確認してください。")
        }
        let label = on ? "オン" : "オフ"
        var succeeded = 0
        for lightId in dict.keys {
            guard let stateURL = URL(string: "http://\(bridgeIP)/api/\(username)/lights/\(lightId)/state") else { continue }
            var req = URLRequest(url: stateURL)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["on": on])
            if let _ = try? await URLSession.shared.data(for: req) {
                succeeded += 1
            }
        }
        guard succeeded > 0 else {
            return Result(success: false, message: "\(homeName)のHue照明\(label)に失敗しました。")
        }
        return Result(success: true, message: "\(homeName)の照明を\(label)にしました（Hue \(succeeded)台）。")
    }
}

// MARK: - HomeSummary convenience init from IntentHomeStore.HomeSummary
// checkInPrepareでlightsOnに渡すために必要

private extension IntentExecutor {
    static func lightsOn(summary: IntentHomeStore.HomeSummary) async -> Result {
        let wrapped = summary
        if !wrapped.hueBridgeIP.isEmpty && !wrapped.hueUsername.isEmpty {
            return await hueLights(on: true, bridgeIP: wrapped.hueBridgeIP, username: wrapped.hueUsername, homeName: wrapped.name)
        }
        if !wrapped.switchBotToken.isEmpty && !wrapped.switchBotSecret.isEmpty {
            return await switchBotAllLights(on: true, token: wrapped.switchBotToken, secret: wrapped.switchBotSecret, homeName: wrapped.name)
        }
        return Result(success: false, message: "\(wrapped.name)の照明が設定されていません。")
    }
}
