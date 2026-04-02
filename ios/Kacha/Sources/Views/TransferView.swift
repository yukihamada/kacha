import SwiftUI
import SwiftData
import CryptoKit

/// KAGI → ChatWeb ワンタイム鍵転送
///
/// Flow:
/// 1. iPhone: keys を 6桁コードの SHA256 で AES-256-GCM 暗号化
/// 2. iPhone: サーバーに暗号化blob + コードを送信
/// 3. iPhone: 画面に6桁コードを表示 (30秒で期限切れ)
/// 4. ChatWeb: ユーザーがコード入力 → サーバーからblob取得 → SHA256(code)で復号
///
/// サーバーは暗号化blobとコードの両方を持つが、30秒で削除される。
/// 実用上のセキュリティは「30秒 + 単一使用」で担保。
struct TransferView: View {
    let items: [SecureItem]
    @Environment(\.dismiss) private var dismiss
    @State private var code: String?
    @State private var sending = false
    @State private var errorMsg: String?
    @State private var countdown = 30
    @State private var timer: Timer?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                if let code {
                    codeDisplay(code)
                } else {
                    confirmView
                }

                if let errorMsg {
                    Text(errorMsg).font(.caption).foregroundColor(.red)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("ChatWebに送信")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { timer?.invalidate(); dismiss() }
                }
            }
        }
    }

    // MARK: - Code Display

    private func codeDisplay(_ code: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48)).foregroundColor(.green)
            Text("ChatWebでこのコードを入力")
                .font(.headline)
            Text(code)
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .tracking(8)
                .foregroundColor(.orange)
            HStack(spacing: 4) {
                Image(systemName: "clock").font(.caption)
                Text("\(countdown)秒で期限切れ")
            }
            .font(.caption).foregroundColor(countdown <= 10 ? .red : .secondary)
            Text("\(items.count)件の鍵")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    // MARK: - Confirm

    private var confirmView: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 48)).foregroundColor(.orange)
            Text("ChatWebに鍵を送信").font(.headline)
            Text("6桁コードで暗号化して転送\n30秒で自動削除・1回限り")
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(items.prefix(8)) { item in
                    HStack(spacing: 8) {
                        Image(systemName: "key.fill").font(.caption2).foregroundColor(.orange)
                        Text(item.title).font(.caption)
                        Spacer()
                    }
                }
                if items.count > 8 {
                    Text("他 \(items.count - 8) 件").font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Button { Task { await send() } } label: {
                Group {
                    if sending { ProgressView().tint(.black) }
                    else { Text("送信する").bold() }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Color.orange).foregroundColor(.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(sending)
        }
    }

    // MARK: - Send

    private func send() async {
        sending = true; errorMsg = nil

        // 1. Generate 6-digit code
        let pin = String(format: "%06d", Int.random(in: 0...999999))

        // 2. Serialize keys
        let keys: [[String: String]] = items.map {
            ["name": $0.title, "value": VaultEncryption.decrypt($0.encryptedValue), "category": $0.category]
        }
        guard let json = try? JSONSerialization.data(withJSONObject: keys) else {
            errorMsg = "データ準備失敗"; sending = false; return
        }

        // 3. Encrypt with SHA256(code)
        let key = SymmetricKey(data: SHA256.hash(data: Data(pin.utf8)))
        guard let sealed = try? AES.GCM.seal(json, using: key),
              let combined = sealed.combined else {
            errorMsg = "暗号化失敗"; sending = false; return
        }

        // 4. POST to server (send code + encrypted blob)
        let body: [String: String] = ["code": pin, "encrypted_data": combined.base64EncodedString()]
        guard let url = URL(string: "https://kagi-server.fly.dev/api/v1/transfer/create") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                errorMsg = "サーバーエラー"; sending = false; return
            }
            // Show code to user
            code = pin
            sending = false
            startCountdown()
        } catch {
            errorMsg = error.localizedDescription; sending = false
        }
    }

    private func startCountdown() {
        countdown = 30
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            countdown -= 1
            if countdown <= 0 { timer?.invalidate(); dismiss() }
        }
    }
}
