import Foundation
import Combine
import UserNotifications

// MARK: - KAGIService
// KAGI APIクライアント + 定期ポーリングマネージャー
// ベースURL: https://kacha-server.fly.dev (環境変数 KAGI_BASE_URL でオーバーライド可能)

@MainActor
final class KAGIService: ObservableObject {

    // MARK: - Published State

    /// 監視中のKAGIデバイス一覧 (家族グループ内の全デバイス)
    @Published var devices: [KAGIDevice] = []

    /// API通信中フラグ
    @Published var isLoading = false

    /// 直近のエラーメッセージ (nilなら正常)
    @Published var errorMessage: String?

    // MARK: - Internal

    /// ポーリング用タイマーのキャンセラブルハンドル
    private var pollingTask: Task<Void, Never>?

    /// ポーリング間隔: 30秒
    private let pollingInterval: TimeInterval = 30

    /// APIベースURL (環境変数またはデフォルト値)
    private let baseURL: String = {
        // INFO.plistまたは環境変数でオーバーライド可能
        if let url = ProcessInfo.processInfo.environment["IKI_BASE_URL"] {
            return url
        }
        return "https://kacha-server.fly.dev"
    }()

    // MARK: - Public API

    /// 家族グループのステータスを取得
    /// GET /api/v1/family/{family_token}/status
    func fetchStatus(familyToken: String) async throws -> KAGIDevice {
        let urlString = "\(baseURL)/api/v1/family/\(familyToken)/status"
        guard let url = URL(string: urlString) else {
            throw KAGIError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw KAGIError.unexpectedResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw KAGIError.unauthorized
        case 404:
            throw KAGIError.deviceNotFound(familyToken)
        default:
            throw KAGIError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let device = try decoder.decode(KAGIDevice.self, from: data)
        return device
    }

    /// APNsプッシュトークンをサーバーに登録
    /// POST /api/v1/family/{family_token}/push_token
    func registerPushToken(_ token: String, familyToken: String) async throws {
        let urlString = "\(baseURL)/api/v1/family/\(familyToken)/push_token"
        guard let url = URL(string: urlString) else {
            throw KAGIError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        // プッシュトークンとプラットフォーム情報を送信
        let body: [String: String] = [
            "push_token": token,
            "platform": "apns",
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw KAGIError.pushRegistrationFailed
        }

        #if DEBUG
        print("[KAGIService] プッシュトークン登録完了: \(familyToken)")
        #endif
    }

    // MARK: - ポーリング制御

    /// 定期ポーリングを開始 (30秒間隔)
    /// 既存のポーリングが動いている場合は一度停止してから再開する
    func startPolling(familyToken: String) {
        stopPolling()

        pollingTask = Task {
            // 即座に初回フェッチ
            await fetchAndUpdate(familyToken: familyToken)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await fetchAndUpdate(familyToken: familyToken)
            }
        }

        #if DEBUG
        print("[KAGIService] ポーリング開始: \(familyToken), 間隔=\(Int(pollingInterval))秒")
        #endif
    }

    /// ポーリングを停止
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        #if DEBUG
        print("[KAGIService] ポーリング停止")
        #endif
    }

    // MARK: - Private Helpers

    /// ステータス取得してdevices配列を更新
    private func fetchAndUpdate(familyToken: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let device = try await fetchStatus(familyToken: familyToken)

            // 既存デバイスを更新、なければ追加
            if let index = devices.firstIndex(where: { $0.id == device.id }) {
                // ステータスが悪化した場合はローカル通知を送信
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
            print("[KAGIService] フェッチエラー: \(error)")
            #endif
        }

        isLoading = false
    }

    /// ステータスが悪化したかどうかを判定
    private func statusWorsened(from old: KAGIDevice.DeviceStatus, to new: KAGIDevice.DeviceStatus) -> Bool {
        let order: [KAGIDevice.DeviceStatus] = [.active, .quiet, .check, .alert]
        guard let oldIndex = order.firstIndex(of: old),
              let newIndex = order.firstIndex(of: new) else { return false }
        return newIndex > oldIndex
    }

    /// ステータス悪化時のローカル通知をスケジュール
    private func scheduleLocalNotification(device: KAGIDevice) {
        let content = UNMutableNotificationContent()
        content.title = "IKI 安否確認"
        content.body = device.status.label + " - " + device.status.description
        content.sound = device.status == .alert ? .defaultCritical : .default
        content.categoryIdentifier = "kagi_safety"

        let request = UNNotificationRequest(
            identifier: "kagi_status_\(device.id)",
            content: content,
            trigger: nil  // 即座に通知
        )

        UNUserNotificationCenter.current().add(request) { error in
            #if DEBUG
            if let error { print("[KAGIService] 通知エラー: \(error)") }
            #endif
        }
    }
}

// MARK: - KAGIError
// APIエラー種別

enum KAGIError: LocalizedError {
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
