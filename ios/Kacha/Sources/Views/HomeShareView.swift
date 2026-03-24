import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - HomeShareView
// ホームの認証情報をQRコード＋ディープリンクで友達に共有する
// 受け取った側: kacha://join?d=BASE64 を開くと自動でホームが追加される

struct HomeShareView: View {
    let home: Home
    @Environment(\.dismiss) private var dismiss
    @State private var showCopied = false

    private var shareData: HomeShareData {
        HomeShareData(
            name: home.name,
            address: home.address,
            switchBotToken: home.switchBotToken,
            switchBotSecret: home.switchBotSecret,
            hueBridgeIP: home.hueBridgeIP,
            hueUsername: home.hueUsername,
            sesameApiKey: home.sesameApiKey,
            sesameDeviceUUIDs: home.sesameDeviceUUIDs,
            qrioApiKey: home.qrioApiKey,
            qrioDeviceIds: home.qrioDeviceIds,
            doorCode: home.doorCode,
            wifiPassword: home.wifiPassword
        )
    }

    private var deepLink: String {
        guard let json = try? JSONEncoder().encode(shareData),
              let b64 = String(data: json.base64EncodedData(), encoding: .utf8)?
                  .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return "kacha://join" }
        return "kacha://join?d=\(b64)"
    }

    private var qrImage: Image? {
        guard let cgImage = generateQR(from: deepLink) else { return nil }
        return Image(uiImage: UIImage(cgImage: cgImage))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 8) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 44))
                                .foregroundColor(.kacha)
                            Text("「\(home.name)」をシェア")
                                .font(.title3).bold().foregroundColor(.white)
                            Text("QRコードを読んでもらうか、リンクを送ってください\n相手がカチャをインストールしていない場合はApp Storeに誘導されます")
                                .font(.caption).foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.top, 8)

                        // QR Code
                        if let qr = qrImage {
                            qr
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 220, height: 220)
                                .padding(16)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }

                        // What's included
                        KachaCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.shield.fill").foregroundColor(.kachaSuccess)
                                    Text("共有される情報").font(.subheadline).bold().foregroundColor(.white)
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    shareRow("house.fill",           "ホーム名・住所")
                                    if !home.switchBotToken.isEmpty {
                                        shareRow("lock.shield.fill", "SwitchBot認証情報")
                                    }
                                    if !home.sesameApiKey.isEmpty {
                                        shareRow("key.fill",         "Sesame APIキー・UUID")
                                    }
                                    if !home.hueBridgeIP.isEmpty {
                                        shareRow("lightbulb.fill",   "Philips Hue ブリッジ情報")
                                    }
                                    if !home.doorCode.isEmpty {
                                        shareRow("keypad.rectangle.fill", "ドアコード")
                                    }
                                    if !home.wifiPassword.isEmpty {
                                        shareRow("wifi",             "Wi-Fiパスワード")
                                    }
                                }
                            }
                            .padding(16)
                        }

                        // Action buttons
                        VStack(spacing: 10) {
                            // Copy link
                            Button {
                                UIPasteboard.general.string = deepLink
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation { showCopied = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    withAnimation { showCopied = false }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: showCopied ? "checkmark.circle.fill" : "link")
                                    Text(showCopied ? "コピーしました！" : "リンクをコピー")
                                        .bold()
                                }
                                .foregroundColor(showCopied ? .kachaSuccess : .kacha)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background((showCopied ? Color.kachaSuccess : Color.kacha).opacity(0.12))
                                .overlay(RoundedRectangle(cornerRadius: 13)
                                    .stroke((showCopied ? Color.kachaSuccess : Color.kacha).opacity(0.3)))
                                .clipShape(RoundedRectangle(cornerRadius: 13))
                            }

                            // Share sheet
                            ShareLink(item: deepLink, subject: Text("カチャ - ホームをシェア"),
                                      message: Text("「\(home.name)」のスマートホームを一緒に操作しよう！\nカチャアプリでこのリンクを開いてください。")) {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("送信する").bold()
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Color.kacha)
                                .clipShape(RoundedRectangle(cornerRadius: 13))
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("ホームをシェア")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }.foregroundStyle(.secondary)
                }
            }
        }
    }

    private func shareRow(_ icon: String, _ label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.caption).foregroundColor(.kacha).frame(width: 16)
            Text(label).font(.caption).foregroundColor(.secondary)
        }
    }

    private func generateQR(from string: String) -> CGImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        return context.createCGImage(scaled, from: scaled.extent)
    }
}

// MARK: - Share Payload

struct HomeShareData: Codable {
    let name: String
    let address: String
    let switchBotToken: String
    let switchBotSecret: String
    let hueBridgeIP: String
    let hueUsername: String
    let sesameApiKey: String
    let sesameDeviceUUIDs: String
    let qrioApiKey: String
    let qrioDeviceIds: String
    let doorCode: String
    let wifiPassword: String
}
