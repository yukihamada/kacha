import Foundation

// MARK: - LINE Messaging API Client
// LINE Notify は 2025年3月に廃止。LINE Messaging API (Push) を使用。

struct LINEMessagingClient {

    enum LINEError: LocalizedError {
        case invalidToken
        case invalidRecipient
        case httpError(Int, String)
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .invalidToken: return "LINEチャネルアクセストークンが設定されていません"
            case .invalidRecipient: return "LINE送信先IDが設定されていません"
            case .httpError(let code, let msg): return "LINE API エラー (\(code)): \(msg)"
            case .networkError(let err): return "通信エラー: \(err.localizedDescription)"
            }
        }
    }

    /// LINE Messaging API でテキストメッセージを送信
    /// - Parameters:
    ///   - message: 送信するテキスト
    ///   - to: 送信先のユーザーID or グループID
    ///   - token: LINE Bot チャネルアクセストークン
    static func send(message: String, to recipientId: String, token: String) async throws {
        guard !token.isEmpty else { throw LINEError.invalidToken }
        guard !recipientId.isEmpty else { throw LINEError.invalidRecipient }

        let url = URL(string: "https://api.line.me/v2/bot/message/push")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "to": recipientId,
            "messages": [
                ["type": "text", "text": message]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

            guard statusCode == 200 else {
                let msg = String(data: data, encoding: .utf8) ?? "不明なエラー"
                throw LINEError.httpError(statusCode, msg)
            }
        } catch let error as LINEError {
            throw error
        } catch {
            throw LINEError.networkError(error)
        }
    }

    /// 清掃依頼メッセージを構築して送信
    static func sendCleaningRequest(home: Home, booking: Booking) async throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        let message = """
        🏠 清掃依頼
        物件: \(home.name)
        ゲスト: \(booking.guestName)
        チェックアウト: \(formatter.string(from: booking.checkOut))
        清掃をお願いします。
        """

        try await send(
            message: message,
            to: home.lineGroupId,
            token: home.lineChannelToken
        )
    }
}
