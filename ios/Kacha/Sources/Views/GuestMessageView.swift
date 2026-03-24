import SwiftUI
import UIKit  // needed for UIApplication.shared.open and UIActivityViewController

// MARK: - Message Template Model

struct MessageTemplate: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let color: Color
    let body: String
}

// MARK: - GuestMessageView

struct GuestMessageView: View {
    let booking: Booking

    @AppStorage("facilityDoorCode") private var doorCode = ""
    @AppStorage("facilityWifiPassword") private var wifiPassword = ""
    @AppStorage("facilityAddress") private var facilityAddress = ""

    @State private var selectedTemplate: MessageTemplate? = nil
    @State private var editedMessage = ""
    @State private var showShareSheet = false
    @Environment(\.dismiss) private var dismiss

    private var templates: [MessageTemplate] {
        [
            MessageTemplate(
                title: "チェックイン案内",
                icon: "door.left.hand.open",
                color: .kachaSuccess,
                body: """
                \(booking.guestName) 様

                この度はご予約いただきありがとうございます。
                チェックインのご案内をお送りします。

                【チェックイン日】{checkIn}
                【チェックアウト日】{checkOut}
                【宿泊数】{nights}泊

                【住所】{address}

                【ドアコード】{doorCode}
                ドアの番号パッドに上記コードを入力して解錠してください。

                ご不明な点がございましたら、お気軽にご連絡ください。
                どうぞ良いご滞在を。
                """
            ),
            MessageTemplate(
                title: "ウェルカムメッセージ",
                icon: "party.popper.fill",
                color: .kacha,
                body: """
                {guestName} 様

                ようこそ！ご到着をお待ちしておりました。

                【Wi-Fi情報】
                パスワード: {wifiPassword}

                何かお困りのことがあればいつでもご連絡ください。
                素晴らしい滞在になりますよう願っています！
                """
            ),
            MessageTemplate(
                title: "チェックアウト案内",
                icon: "arrow.left.square.fill",
                color: .kachaAccent,
                body: """
                {guestName} 様

                ご滞在ありがとうございました。

                チェックアウトは {checkOut} です。
                お帰りの際は以下をお願いします：

                ・ドアを施錠してください
                ・ゴミは所定の場所に捨ててください
                ・鍵・忘れ物の確認をお願いします

                またのご利用を心よりお待ちしております。
                """
            ),
            MessageTemplate(
                title: "請求確認",
                icon: "yensign.circle.fill",
                color: .kachaWarn,
                body: """
                {guestName} 様

                ご宿泊のご請求確認です。

                【宿泊期間】{checkIn} ～ {checkOut}（{nights}泊）

                ご確認のほどよろしくお願いします。
                """
            )
        ]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()

                if selectedTemplate == nil {
                    templatePickerView
                } else {
                    messageEditorView
                }
            }
            .navigationTitle("メッセージを送る")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.kachaBg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundColor(.kacha)
                }
                if selectedTemplate != nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            selectedTemplate = nil
                            editedMessage = ""
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("テンプレート")
                            }
                            .foregroundColor(.kacha)
                        }
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ActivityView(text: editedMessage)
            }
        }
    }

    // MARK: - Template Picker

    private var templatePickerView: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("テンプレートを選択")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                ForEach(templates) { template in
                    Button {
                        selectedTemplate = template
                        editedMessage = fillVariables(template.body)
                    } label: {
                        KachaCard {
                            HStack(spacing: 14) {
                                Image(systemName: template.icon)
                                    .font(.title2)
                                    .foregroundColor(template.color)
                                    .frame(width: 40)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(template.title)
                                        .font(.subheadline).bold()
                                        .foregroundColor(.white)
                                    Text(previewText(template.body))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(14)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                Spacer(minLength: 40)
            }
        }
    }

    // MARK: - Message Editor

    private var messageEditorView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    // Recipient info
                    KachaCard {
                        HStack(spacing: 12) {
                            Image(systemName: "person.fill")
                                .foregroundColor(.kacha)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(booking.guestName)
                                    .font(.subheadline).bold()
                                    .foregroundColor(.white)
                                if !booking.guestEmail.isEmpty {
                                    Text(booking.guestEmail)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                if !booking.guestPhone.isEmpty {
                                    Text(booking.guestPhone)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(14)
                    }
                    .padding(.horizontal, 16)

                    // Text editor
                    KachaCard {
                        TextEditor(text: $editedMessage)
                            .foregroundColor(.white)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .font(.subheadline)
                            .frame(minHeight: 280)
                            .padding(12)
                    }
                    .padding(.horizontal, 16)

                    Spacer(minLength: 80)
                }
                .padding(.top, 8)
            }

            // Action buttons
            VStack(spacing: 10) {
                Divider().background(Color.kachaCardBorder)

                HStack(spacing: 12) {
                    if !booking.guestPhone.isEmpty {
                        Button {
                            openSMS()
                        } label: {
                            HStack {
                                Image(systemName: "message.fill")
                                Text("SMS")
                            }
                            .font(.subheadline).bold()
                            .foregroundColor(.kachaSuccess)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.kachaSuccess.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    Button {
                        showShareSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("共有")
                        }
                        .font(.subheadline).bold()
                        .foregroundColor(.kacha)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.kacha.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .background(Color.kachaBg)
        }
    }

    // MARK: - Helpers

    private func fillVariables(_ template: String) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ja_JP")
        fmt.dateStyle = .medium
        fmt.timeStyle = .none

        return template
            .replacingOccurrences(of: "{guestName}", with: booking.guestName)
            .replacingOccurrences(of: "{checkIn}", with: fmt.string(from: booking.checkIn))
            .replacingOccurrences(of: "{checkOut}", with: fmt.string(from: booking.checkOut))
            .replacingOccurrences(of: "{nights}", with: "\(booking.nights)")
            .replacingOccurrences(of: "{doorCode}", with: doorCode.isEmpty ? "（ドアコードを設定してください）" : doorCode)
            .replacingOccurrences(of: "{wifiPassword}", with: wifiPassword.isEmpty ? "（Wi-Fiパスワードを設定してください）" : wifiPassword)
            .replacingOccurrences(of: "{address}", with: facilityAddress.isEmpty ? "（住所を設定してください）" : facilityAddress)
    }

    private func previewText(_ body: String) -> String {
        let first = body.components(separatedBy: "\n").first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        return first.trimmingCharacters(in: .whitespaces)
    }

    private func openSMS() {
        let encoded = editedMessage.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let phone = booking.guestPhone.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        if let url = URL(string: "sms:\(phone)&body=\(encoded)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - UIActivityViewController wrapper

struct ActivityView: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
