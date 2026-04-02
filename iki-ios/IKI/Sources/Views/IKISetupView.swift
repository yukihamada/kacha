import SwiftUI
import UserNotifications

// MARK: - IKISetupView
// IKIデバイスの初期設定ビュー
// QRコードスキャンまたは手動入力で家族トークンを設定

struct IKISetupView: View {

    @Binding var familyToken: String
    var onComplete: ((String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var inputToken = ""
    @State private var showQRScanner = false
    @State private var showNotificationPrompt = false
    @State private var notificationsGranted = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 28) {
                    headerSection
                    tokenInputSection
                    notificationSection
                    completeButton
                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle("IKI 初期設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
        .onAppear {
            inputToken = familyToken
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.iki.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "figure.and.child.holdinghands")
                    .font(.system(size: 44))
                    .foregroundColor(.iki)
            }

            Text("家族の安否をリアルタイムで確認")
                .font(.headline)

            Text("IKIデバイスの「家族トークン」を入力してください。\nトークンはデバイスの設定アプリで確認できます。")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var tokenInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("家族トークン")
                .font(.subheadline)
                .fontWeight(.medium)

            HStack {
                TextField("例: FAM-XXXXXXXX", text: $inputToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)

                Button {
                    showQRScanner = true
                } label: {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.title2)
                        .foregroundColor(.iki)
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Text("QRコードはIKIデバイスのNFCタグまたはデバイス設定画面から読み取れます")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("プッシュ通知")
                .font(.subheadline)
                .fontWeight(.medium)

            HStack(spacing: 14) {
                Image(systemName: notificationsGranted ? "bell.badge.fill" : "bell.slash.fill")
                    .font(.title2)
                    .foregroundColor(notificationsGranted ? .iki : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(notificationsGranted ? "通知が有効です" : "通知を有効にする")
                        .font(.callout)
                        .fontWeight(.medium)

                    Text("警報や要確認アラートを即座に受け取れます")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !notificationsGranted {
                    Button("許可する") {
                        requestNotificationPermission()
                    }
                    .font(.callout)
                    .foregroundColor(.iki)
                }
            }
            .padding(14)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
        .onAppear {
            checkNotificationPermission()
        }
    }

    private var completeButton: some View {
        Button {
            saveAndDismiss()
        } label: {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text("設定を保存")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(inputToken.isEmpty ? Color.gray : Color.iki)
            .foregroundColor(.white)
            .cornerRadius(14)
        }
        .disabled(inputToken.isEmpty)
    }

    // MARK: - Helpers

    private func saveAndDismiss() {
        let trimmed = inputToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "家族トークンを入力してください"
            return
        }
        familyToken = trimmed
        onComplete?(trimmed)
        dismiss()
    }

    private func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationsGranted = settings.authorizationStatus == .authorized
            }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge, .criticalAlert]
        ) { granted, _ in
            DispatchQueue.main.async {
                notificationsGranted = granted
            }
        }
    }
}

#Preview {
    IKISetupView(familyToken: .constant(""))
}
