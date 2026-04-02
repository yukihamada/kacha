import Foundation
import Combine
import UserNotifications

// MARK: - IKIService
// IKI APIクライアント + 定期ポーリングマネージャー
// ベースURL: https://kacha-server.fly.dev

@MainActor
final class IKIService: ObservableObject {

    // MARK: - Published State

    /// 監視中のIKIデバイス一覧
    @Published var devices: [IKIDeviceData] = []

    /// API通信中フラグ
    @Published var isLoading = false

    /// 直近のエラーメッセージ
    @Published var errorMessage: String?

    // MARK: - Internal

    private var pollingTask: Task<Void, Never>?
    private let pollingInterval: TimeInterval = 30

    private let baseURL: String = {
        if let url = ProcessInfo.processInfo.environment["IKI_BASE_URL"] {
            return url
        }
        return "https://kacha-server.fly.dev"
    }()

    // MARK: - Public API

    /// 家族グループのステータスを取得
    /// GET /api/v1/family/{family_token}/status
    @discardableResult
    func fetchStatus(familyToken: String) async throws -> IKIDeviceData {
        let urlString = "\(baseURL)/api/v1/family/\(familyToken)/status"
        guard let url = URL(string: urlString) else {
            throw IKIError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw IKIError.unexpectedResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw IKIError.unauthorized
        case 404:
            throw IKIError.deviceNotFound(familyToken)
        default:
            throw IKIError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let device = try decoder.decode(IKIDeviceData.self, from: data)
        return device
    }

    /// APNsプッシュトークンをサーバーに登録
    /// POST /api/v1/family/{family_token}/push_token
    func registerPushToken(_ token: String, familyToken: String) async throws {
        let urlString = "\(baseURL)/api/v1/family/\(familyToken)/push_token"
        guard let url = URL(string: urlString) else {
            throw IKIError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: String] = [
            "push_token": token,
            "platform": "apns",
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw IKIError.pushRegistrationFailed
        }

        #if DEBUG
        print("[IKIService] プッシュトークン登録完了: \(familyToken)")
        #endif
    }

    // MARK: - ポーリング制御

    func startPolling(familyToken: String) {
        stopPolling()

        pollingTask = Task {
            await fetchAndUpdate(familyToken: familyToken)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await fetchAndUpdate(familyToken: familyToken)
            }
        }

        #if DEBUG
        print("[IKIService] ポーリング開始: \(familyToken), 間隔=\(Int(pollingInterval))秒")
        #endif
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        #if DEBUG
        print("[IKIService] ポーリング停止")
        #endif
    }

    // MARK: - Private Helpers

    private func fetchAndUpdate(familyToken: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let device = try await fetchStatus(familyToken: familyToken)

            if let index = devices.firstIndex(where: { $0.id == device.id }) {
                let previousStatus = devices[index].status
                if statusWorsened(from: previousStatus, to: device.status) {
                    scheduleLocalNotification(device: device)
                }
                devices[index] = device
            } else {
                devices.append(device)
            }
        } catch {
            errorMessage = error.localizedDescription
            #if DEBUG
            print("[IKIService] フェッチエラー: \(error)")
            #endif
        }

        isLoading = false
    }

    private func statusWorsened(from old: DeviceStatus, to new: DeviceStatus) -> Bool {
        let order: [DeviceStatus] = [.active, .quiet, .check, .alert]
        guard let oldIndex = order.firstIndex(of: old),
              let newIndex = order.firstIndex(of: new) else { return false }
        return newIndex > oldIndex
    }

    private func scheduleLocalNotification(device: IKIDeviceData) {
        let content = UNMutableNotificationContent()
        content.title = "IKI 安否確認"
        content.body = device.status.label + " - " + device.status.description
        content.sound = device.status == .alert ? .defaultCritical : .default
        content.categoryIdentifier = "iki_safety"

        let request = UNNotificationRequest(
            identifier: "iki_status_\(device.id)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            #if DEBUG
            if let error { print("[IKIService] 通知エラー: \(error)") }
            #endif
        }
    }
}

// MARK: - IKIError

enum IKIError: LocalizedError {
    case invalidURL(String)
    case unexpectedResponse
    case unauthorized
    case deviceNotFound(String)
    case serverError(Int)
    case pushRegistrationFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):       return "無効なURL: \(url)"
        case .unexpectedResponse:        return "予期しないレスポンス形式"
        case .unauthorized:              return "認証エラー: family_tokenを確認してください"
        case .deviceNotFound(let token): return "デバイスが見つかりません: \(token)"
        case .serverError(let code):     return "サーバーエラー: HTTP \(code)"
        case .pushRegistrationFailed:    return "プッシュ通知の登録に失敗しました"
        }
    }
}
