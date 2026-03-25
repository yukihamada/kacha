import SwiftUI
import SwiftData

// MARK: - Cloud Sync View

struct CloudSyncView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var sync = CloudSyncService.shared

    @State private var email = ""
    @State private var code = ""
    @State private var phase: AuthPhase = .email
    @State private var passphrase = ""
    @State private var passphraseConfirm = ""
    @State private var showPassphraseInput = false
    @State private var isLoading = false
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var showLogoutConfirm = false
    @State private var showRestoreConfirm = false
    @State private var restoredCount = 0

    enum AuthPhase { case email, code, done }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        headerSection

                        if sync.isLoggedIn {
                            syncStatusSection
                            keyMethodSection
                            syncActionsSection
                            logoutSection
                        } else {
                            authSection
                        }

                        securityInfoSection
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("クラウド同期")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.kachaBg, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }.foregroundStyle(.secondary)
                }
            }
            .alert(alertMessage, isPresented: $showAlert) { Button("OK") {} }
            .alert("ログアウト", isPresented: $showLogoutConfirm) {
                Button("ログアウト", role: .destructive) { sync.logout() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("暗号鍵は端末に残ります。再ログイン時にデータを復元できます。")
            }
            .alert("クラウドから復元", isPresented: $showRestoreConfirm) {
                Button("復元", role: .destructive) { restoreFromCloud() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("クラウドのバックアップからデータを復元します。既存データと重複しないデータのみ追加されます。")
            }
            .sheet(isPresented: $showPassphraseInput) { passphraseSheet }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        KachaCard {
            VStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.kachaAccent.opacity(0.12)).frame(width: 72, height: 72)
                    Image(systemName: "icloud.and.arrow.up.fill")
                        .font(.system(size: 32)).foregroundColor(.kachaAccent)
                }
                Text("E2E暗号化クラウド同期")
                    .font(.headline).foregroundColor(.white)
                Text("データはAES-256-GCMで暗号化され、サーバーに平文は保存されません。")
                    .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
        }
    }

    // MARK: - Auth Section

    private var authSection: some View {
        KachaCard {
            VStack(spacing: 16) {
                SettingsHeader(icon: "person.crop.circle.fill", title: "ログイン", color: .kacha)

                if phase == .email {
                    VStack(spacing: 12) {
                        TextField("メールアドレス", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .foregroundColor(.white)
                            .padding(14)
                            .background(Color.kachaCard)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.kachaCardBorder))

                        Button { sendMagicLink() } label: {
                            HStack {
                                if isLoading {
                                    ProgressView().tint(.black)
                                } else {
                                    Text("確認コードを送信")
                                }
                            }
                            .font(.subheadline).bold()
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.kacha)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(email.isEmpty || !email.contains("@") || isLoading)
                        .opacity(email.isEmpty || !email.contains("@") ? 0.5 : 1)
                    }
                } else if phase == .code {
                    VStack(spacing: 12) {
                        Text("\(email) に6桁のコードを送信しました")
                            .font(.caption).foregroundColor(.secondary)

                        TextField("6桁の確認コード", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .foregroundColor(.white)
                            .padding(14)
                            .background(Color.kachaCard)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.kachaCardBorder))
                            .multilineTextAlignment(.center)
                            .font(.title2.monospaced())

                        Button { verifyCode() } label: {
                            HStack {
                                if isLoading {
                                    ProgressView().tint(.black)
                                } else {
                                    Text("確認")
                                }
                            }
                            .font(.subheadline).bold()
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.kacha)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(code.count != 6 || isLoading)

                        // Resend button
                        Button {
                            code = ""
                            sendMagicLink()
                        } label: {
                            HStack {
                                if isLoading {
                                    ProgressView().tint(.kacha)
                                } else {
                                    Text("コードを再送信")
                                }
                            }
                            .font(.subheadline)
                            .foregroundColor(.kacha)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.kacha.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(isLoading)

                        // Help text for missing email
                        VStack(alignment: .leading, spacing: 4) {
                            Text("メールが届かない場合")
                                .font(.caption).bold().foregroundColor(.secondary)
                            Text("• 迷惑メール（スパム）フォルダをご確認ください")
                                .font(.caption2).foregroundColor(.secondary)
                            Text("• 送信元: noreply@enablerdao.com")
                                .font(.caption2).foregroundColor(.secondary)
                            Text("• 数分経っても届かない場合は「コードを再送信」をタップしてください")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.kachaCard.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        Button("メールアドレスを変更") {
                            phase = .email; code = ""
                        }
                        .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Sync Status

    private var syncStatusSection: some View {
        KachaCard {
            VStack(spacing: 12) {
                SettingsHeader(icon: "checkmark.circle.fill", title: "アカウント", color: .kachaSuccess)

                HStack {
                    Image(systemName: "envelope.fill").foregroundColor(.kacha).frame(width: 20)
                    Text(sync.userEmail).font(.subheadline).foregroundColor(.white)
                    Spacer()
                }

                if let date = sync.lastSyncDate {
                    HStack {
                        Image(systemName: "clock.fill").foregroundColor(.secondary).frame(width: 20)
                        Text("最終同期: \(date.formatted(.relative(presentation: .named)))")
                            .font(.caption).foregroundColor(.secondary)
                        Spacer()
                    }
                }

                if case .syncing = sync.syncState {
                    HStack {
                        ProgressView().tint(.kacha)
                        Text("同期中...").font(.caption).foregroundColor(.kacha)
                        Spacer()
                    }
                } else if case .error(let msg) = sync.syncState {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.kachaDanger)
                        Text(msg).font(.caption).foregroundColor(.kachaDanger)
                        Spacer()
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Key Method Selection

    private var keyMethodSection: some View {
        KachaCard {
            VStack(spacing: 12) {
                SettingsHeader(icon: "key.fill", title: "暗号鍵の管理方法", color: .kacha)

                ForEach(CloudSyncService.KeyMethod.allCases, id: \.rawValue) { method in
                    Button {
                        selectKeyMethod(method)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(sync.keyMethod == method ? Color.kacha.opacity(0.15) : Color.clear)
                                    .frame(width: 36, height: 36)
                                Image(systemName: method.icon)
                                    .foregroundColor(sync.keyMethod == method ? .kacha : .secondary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(method.title)
                                    .font(.subheadline).bold()
                                    .foregroundColor(sync.keyMethod == method ? .white : .secondary)
                                Text(method.description)
                                    .font(.caption2).foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            if sync.keyMethod == method {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.kacha)
                            }
                        }
                        .padding(10)
                        .background(sync.keyMethod == method ? Color.kacha.opacity(0.05) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Sync Actions

    private var syncActionsSection: some View {
        KachaCard {
            VStack(spacing: 12) {
                SettingsHeader(icon: "arrow.triangle.2.circlepath", title: "同期", color: .kachaAccent)

                Button { backupToCloud() } label: {
                    HStack {
                        Image(systemName: "icloud.and.arrow.up").frame(width: 20)
                        Text("クラウドにバックアップ")
                        Spacer()
                        if case .syncing = sync.syncState {
                            ProgressView().tint(.kacha)
                        }
                    }
                    .actionButtonStyle(.kacha)
                }
                .disabled(sync.syncState == .syncing)

                Button { showRestoreConfirm = true } label: {
                    HStack {
                        Image(systemName: "icloud.and.arrow.down").frame(width: 20)
                        Text("クラウドから復元")
                        Spacer()
                    }
                    .actionButtonStyle(.kachaAccent)
                }
                .disabled(sync.syncState == .syncing)
            }
            .padding(16)
        }
    }

    // MARK: - Logout

    private var logoutSection: some View {
        KachaCard {
            Button { showLogoutConfirm = true } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.forward").frame(width: 20)
                    Text("ログアウト")
                    Spacer()
                }
                .actionButtonStyle(.kachaDanger)
            }
            .padding(16)
        }
    }

    // MARK: - Security Info

    private var securityInfoSection: some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 10) {
                SettingsHeader(icon: "lock.shield.fill", title: "セキュリティ", color: .kachaSuccess)

                securityRow(icon: "lock.fill", text: "AES-256-GCM E2E暗号化")
                securityRow(icon: "server.rack", text: "サーバーに平文データは保存されません")
                securityRow(icon: "key.fill", text: "暗号鍵はあなたの端末にのみ保存")
                securityRow(icon: "icloud", text: "iCloudキーチェーン: Apple端末間で鍵を自動共有")
                securityRow(icon: "textformat.abc", text: "パスフレーズ: 自分だけが知る言葉で暗号化")
            }
            .padding(16)
        }
    }

    private func securityRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.caption).foregroundColor(.kachaSuccess).frame(width: 16)
            Text(text).font(.caption).foregroundColor(.secondary)
        }
    }

    // MARK: - Passphrase Sheet

    private var passphraseSheet: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                VStack(spacing: 20) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 48)).foregroundColor(.kacha).padding(.top, 32)

                    Text("パスフレーズを設定")
                        .font(.headline).foregroundColor(.white)

                    Text("このパスフレーズでデータを暗号化します。\n忘れるとデータを復元できません。")
                        .font(.caption).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    SecureField("パスフレーズ（8文字以上）", text: $passphrase)
                        .foregroundColor(.white).padding(14)
                        .background(Color.kachaCard)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.kachaCardBorder))
                        .padding(.horizontal, 24)

                    SecureField("パスフレーズ（確認）", text: $passphraseConfirm)
                        .foregroundColor(.white).padding(14)
                        .background(Color.kachaCard)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.kachaCardBorder))
                        .padding(.horizontal, 24)

                    if !passphrase.isEmpty && passphrase.count < 8 {
                        Text("8文字以上にしてください")
                            .font(.caption).foregroundColor(.kachaDanger)
                    }

                    if !passphraseConfirm.isEmpty && passphrase != passphraseConfirm {
                        Text("パスフレーズが一致しません")
                            .font(.caption).foregroundColor(.kachaDanger)
                    }

                    Spacer()
                }
            }
            .navigationTitle("パスフレーズ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        showPassphraseInput = false
                        passphrase = ""; passphraseConfirm = ""
                    }
                    .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("設定") { applyPassphrase() }
                        .foregroundColor(.kacha)
                        .disabled(passphrase.count < 8 || passphrase != passphraseConfirm)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Actions

    private func sendMagicLink() {
        isLoading = true
        Task {
            do {
                try await sync.requestMagicLink(email: email.trimmingCharacters(in: .whitespaces).lowercased())
                await MainActor.run { phase = .code; isLoading = false }
            } catch {
                await MainActor.run {
                    alertMessage = error.localizedDescription
                    showAlert = true
                    isLoading = false
                }
            }
        }
    }

    private func verifyCode() {
        isLoading = true
        Task {
            do {
                try await sync.verifyCode(
                    email: email.trimmingCharacters(in: .whitespaces).lowercased(),
                    code: code.trimmingCharacters(in: .whitespaces)
                )
                await MainActor.run { phase = .done; isLoading = false }
            } catch {
                await MainActor.run {
                    alertMessage = error.localizedDescription
                    showAlert = true
                    isLoading = false
                }
            }
        }
    }

    private func selectKeyMethod(_ method: CloudSyncService.KeyMethod) {
        if method == .passphrase {
            showPassphraseInput = true
        } else {
            try? sync.setKeyMethod(.icloudKeychain)
        }
    }

    private func applyPassphrase() {
        try? sync.setKeyMethod(.passphrase, passphrase: passphrase)
        passphrase = ""; passphraseConfirm = ""
        showPassphraseInput = false
    }

    private func backupToCloud() {
        Task { await sync.backup(context: modelContext) }
    }

    private func restoreFromCloud() {
        Task {
            do {
                let count = try await sync.restore(context: modelContext)
                await MainActor.run {
                    restoredCount = count
                    alertMessage = "\(count)件のデータを復元しました"
                    showAlert = true
                }
            } catch let error as SyncError where error == .keyNotFound {
                // パスフレーズが必要
                await MainActor.run { showPassphraseInput = true }
            } catch {
                await MainActor.run {
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
            }
        }
    }
}

// SyncError Equatable for keyNotFound check
extension SyncError: Equatable {
    static func == (lhs: SyncError, rhs: SyncError) -> Bool {
        switch (lhs, rhs) {
        case (.keyNotFound, .keyNotFound): return true
        default: return lhs.localizedDescription == rhs.localizedDescription
        }
    }
}
