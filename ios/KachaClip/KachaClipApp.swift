import SwiftUI
import CryptoKit

// MARK: - App Clip Entry Point
// URL: https://kacha.pasha.run/guest?t=TOKEN#ENCRYPTION_KEY

@main
struct KachaClipApp: App {
    @State private var viewModel = GuestClipViewModel()

    var body: some Scene {
        WindowGroup {
            GuestClipView(viewModel: viewModel)
                .preferredColorScheme(.dark)
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL {
                        handleURL(url)
                    }
                }
                .onOpenURL { url in
                    handleURL(url)
                }
        }
    }

    private func handleURL(_ url: URL) {
        // Support both:
        //   https://kacha.pasha.run/guest?t=TOKEN#KEY
        //   kacha://guest?t=TOKEN#KEY
        let isUniversal = url.scheme == "https" && url.host == "kacha.pasha.run"
            && (url.path == "/guest" || url.path == "/join")
        let isCustom = url.scheme == "kacha" && (url.host == "guest" || url.host == "join")
        guard isUniversal || isCustom else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let token = components?.queryItems?.first(where: { $0.name == "t" })?.value,
              let fragment = url.fragment?.removingPercentEncoding, !fragment.isEmpty else { return }

        viewModel.load(token: token, encryptionKey: fragment)
    }
}

// MARK: - ViewModel

@Observable
final class GuestClipViewModel {
    var state: LoadState = .idle

    enum LoadState {
        case idle
        case loading
        case loaded(GuestData)
        case error(String)
    }

    func load(token: String, encryptionKey: String) {
        state = .loading

        Task {
            do {
                let data = try await ClipShareClient.fetchShare(token: token, encryptionKey: encryptionKey)
                await MainActor.run { state = .loaded(data) }
            } catch let err as ClipShareError {
                await MainActor.run { state = .error(err.localizedDescription) }
            } catch {
                await MainActor.run { state = .error("接続エラー: \(error.localizedDescription)") }
            }
        }
    }
}

// MARK: - Lightweight Share Client (E2E decryption only)

struct GuestData: Codable {
    let name: String
    let address: String
    let role: String
    let doorCode: String
    let wifiPassword: String
    // Fields below exist in HomeShareData but unused in clip
    let switchBotToken: String?
    let switchBotSecret: String?
    let hueBridgeIP: String?
    let hueUsername: String?
    let sesameApiKey: String?
    let sesameDeviceUUIDs: String?
    let qrioApiKey: String?
    let qrioDeviceIds: String?
    let beds24ApiKey: String?
    let beds24RefreshToken: String?

    enum CodingKeys: String, CodingKey {
        case name, address, role, doorCode, wifiPassword
        case switchBotToken, switchBotSecret, hueBridgeIP, hueUsername
        case sesameApiKey, sesameDeviceUUIDs, qrioApiKey, qrioDeviceIds
        case beds24ApiKey, beds24RefreshToken
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? "guest"
        doorCode = try c.decodeIfPresent(String.self, forKey: .doorCode) ?? ""
        wifiPassword = try c.decodeIfPresent(String.self, forKey: .wifiPassword) ?? ""
        switchBotToken = try c.decodeIfPresent(String.self, forKey: .switchBotToken)
        switchBotSecret = try c.decodeIfPresent(String.self, forKey: .switchBotSecret)
        hueBridgeIP = try c.decodeIfPresent(String.self, forKey: .hueBridgeIP)
        hueUsername = try c.decodeIfPresent(String.self, forKey: .hueUsername)
        sesameApiKey = try c.decodeIfPresent(String.self, forKey: .sesameApiKey)
        sesameDeviceUUIDs = try c.decodeIfPresent(String.self, forKey: .sesameDeviceUUIDs)
        qrioApiKey = try c.decodeIfPresent(String.self, forKey: .qrioApiKey)
        qrioDeviceIds = try c.decodeIfPresent(String.self, forKey: .qrioDeviceIds)
        beds24ApiKey = try c.decodeIfPresent(String.self, forKey: .beds24ApiKey)
        beds24RefreshToken = try c.decodeIfPresent(String.self, forKey: .beds24RefreshToken)
    }
}

enum ClipShareError: Error, LocalizedError {
    case networkError, notYetValid, expired, notFound, decryptionFailed

    var errorDescription: String? {
        switch self {
        case .networkError:     return "ネットワークエラー"
        case .notYetValid:      return "このリンクはまだ有効期間前です"
        case .expired:          return "このリンクは期限切れです"
        case .notFound:         return "シェアが見つかりません"
        case .decryptionFailed: return "データの復号に失敗しました"
        }
    }
}

struct ClipShareClient {
    static let baseURL = "https://kacha.pasha.run"

    static func fetchShare(token: String, encryptionKey: String) async throws -> GuestData {
        guard let url = URL(string: "\(baseURL)/api/v1/shares/\(token)") else {
            throw ClipShareError.networkError
        }
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let http = response as? HTTPURLResponse else {
            throw ClipShareError.networkError
        }
        switch http.statusCode {
        case 200: break
        case 403: throw ClipShareError.notYetValid
        case 410: throw ClipShareError.expired
        case 404: throw ClipShareError.notFound
        default:  throw ClipShareError.networkError
        }

        struct ServerResponse: Codable { let encrypted_data: String }
        let result = try JSONDecoder().decode(ServerResponse.self, from: data)

        guard let combinedData = Data(base64Encoded: result.encrypted_data),
              let keyData = Data(base64Encoded: encryptionKey) else {
            throw ClipShareError.decryptionFailed
        }

        let symmetricKey = SymmetricKey(data: keyData)
        let sealedBox = try AES.GCM.SealedBox(combined: combinedData)
        let plaintext = try AES.GCM.open(sealedBox, using: symmetricKey)
        return try JSONDecoder().decode(GuestData.self, from: plaintext)
    }
}
