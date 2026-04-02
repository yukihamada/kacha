import SwiftUI
import SwiftData

/// ChatWeb との Vault 同期シート
/// APIキーカテゴリのアイテムを暗号化したまま ChatWeb サーバーに送信
struct ChatWebSyncSheet: View {
    let items: [SecureItem]
    @Binding var syncStatus: String
    @Environment(\.dismiss) private var dismiss
    @State private var sessionToken = ""
    @State private var isSyncing = false
    @State private var syncResult: SyncResult?
    @State private var remoteKeys: [VaultKeyInfo] = []

    private var apiKeys: [SecureItem] {
        items.filter { $0.category == "apikey" }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 36))
                                .foregroundStyle(.linearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                            Text("ChatWeb 同期")
                                .font(.title3).bold()
                            Text("APIキーを ChatWeb に同期して\nブラウザから使えるようにします")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)

                        // Session token input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ChatWeb セッショントークン")
                                .font(.caption).foregroundColor(.secondary)
                            TextField("トークンを入力", text: $sessionToken)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            Text("chatweb.ai の設定画面からコピーできます")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        .padding(.horizontal)

                        // API Keys to sync
                        VStack(alignment: .leading, spacing: 8) {
                            Text("同期するAPIキー (\(apiKeys.count)件)")
                                .font(.caption).foregroundColor(.secondary)
                                .padding(.horizontal)

                            if apiKeys.isEmpty {
                                HStack {
                                    Spacer()
                                    VStack(spacing: 8) {
                                        Image(systemName: "key.slash")
                                            .font(.title2).foregroundColor(.secondary)
                                        Text("APIキーがありません")
                                            .font(.caption).foregroundColor(.secondary)
                                        Text("パスワード管理で「APIキー」カテゴリで追加してください")
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 20)
                            } else {
                                ForEach(apiKeys) { item in
                                    HStack(spacing: 12) {
                                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.purple)
                                            .frame(width: 24)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.title)
                                                .font(.subheadline).bold()
                                            Text("••••••••")
                                                .font(.caption).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .opacity(syncResult != nil ? 1 : 0.3)
                                    }
                                    .padding(12)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .padding(.horizontal)
                                }
                            }
                        }

                        // Sync button
                        Button {
                            Task { await syncToServer() }
                        } label: {
                            HStack(spacing: 8) {
                                if isSyncing {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "arrow.up.circle.fill")
                                }
                                Text(isSyncing ? "同期中..." : "ChatWebに同期")
                                    .bold()
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(colors: [.purple, .blue],
                                             startPoint: .leading, endPoint: .trailing)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(sessionToken.isEmpty || apiKeys.isEmpty || isSyncing)
                        .padding(.horizontal)

                        // Result
                        if let result = syncResult {
                            HStack(spacing: 8) {
                                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(result.success ? .green : .red)
                                Text(result.message)
                                    .font(.caption)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(result.success ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func syncToServer() async {
        isSyncing = true
        syncResult = nil
        do {
            let itemsData = apiKeys.map { item in
                SecureItemData(
                    keyName: item.title.uppercased().replacingOccurrences(of: " ", with: "_"),
                    encryptedValue: item.encryptedValue,  // Send encrypted — server never sees plaintext
                    category: "apikey"
                )
            }
            let count = try await ChatWebVaultSync.syncAllAPIKeys(
                items: itemsData, sessionToken: sessionToken
            )
            syncResult = SyncResult(success: true, message: "\(count)件のAPIキーを同期しました")
            syncStatus = "synced"
        } catch {
            syncResult = SyncResult(success: false, message: error.localizedDescription)
        }
        isSyncing = false
    }
}

struct SyncResult {
    let success: Bool
    let message: String
}
