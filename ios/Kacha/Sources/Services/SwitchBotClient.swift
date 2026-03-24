import Foundation
import CryptoKit

@MainActor
class SwitchBotClient: ObservableObject {
    static let shared = SwitchBotClient()

    @Published var devices: [SwitchBotDevice] = []
    @Published var isLoading = false
    @Published var lastError: String?

    private let baseURL = "https://api.switch-bot.com/v1.1"

    struct SwitchBotDevice: Codable, Identifiable {
        let deviceId: String
        let deviceName: String
        let deviceType: String
        let hubDeviceId: String?
        var id: String { deviceId }
    }

    private struct APIResponse: Codable {
        let statusCode: Int
        let body: DeviceBody?
        let message: String?

        struct DeviceBody: Codable {
            let deviceList: [SwitchBotDevice]
        }
    }

    private func makeHeaders(token: String, secret: String) -> [String: String] {
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

    func fetchDevices(token: String, secret: String) async throws -> [SwitchBotDevice] {
        isLoading = true
        defer { isLoading = false }

        let url = URL(string: "\(baseURL)/devices")!
        var request = URLRequest(url: url)
        makeHeaders(token: token, secret: secret).forEach {
            request.setValue($1, forHTTPHeaderField: $0)
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(APIResponse.self, from: data)
        let list = response.body?.deviceList ?? []
        self.devices = list
        return list
    }

    func sendCommand(
        deviceId: String,
        command: String,
        parameter: String = "default",
        token: String,
        secret: String
    ) async throws {
        let url = URL(string: "\(baseURL)/devices/\(deviceId)/commands")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        makeHeaders(token: token, secret: secret).forEach {
            request.setValue($1, forHTTPHeaderField: $0)
        }
        let body: [String: Any] = [
            "command": command,
            "parameter": parameter,
            "commandType": "command"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }

    func lock(deviceId: String, token: String, secret: String) async throws {
        try await sendCommand(deviceId: deviceId, command: "lock", token: token, secret: secret)
    }

    func unlock(deviceId: String, token: String, secret: String) async throws {
        try await sendCommand(deviceId: deviceId, command: "unlock", token: token, secret: secret)
    }

    func turnOn(deviceId: String, token: String, secret: String) async throws {
        try await sendCommand(deviceId: deviceId, command: "turnOn", token: token, secret: secret)
    }

    func turnOff(deviceId: String, token: String, secret: String) async throws {
        try await sendCommand(deviceId: deviceId, command: "turnOff", token: token, secret: secret)
    }
}
