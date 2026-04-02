import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - Guest Clip View (App Clip main UI)

struct GuestClipView: View {
    let viewModel: GuestClipViewModel
    @State private var showWifiPassword = false
    @State private var copiedDoorCode = false
    @State private var selectedLang = "ja"

    private let languages = [
        ("ja", "日本語"),
        ("en", "English"),
        ("zh", "中文"),
        ("ko", "한국어"),
    ]

    private func t(_ ja: String, _ en: String, _ zh: String, _ ko: String) -> String {
        switch selectedLang {
        case "en": return en
        case "zh": return zh
        case "ko": return ko
        default: return ja
        }
    }

    var body: some View {
        ZStack {
            Color.clipBg.ignoresSafeArea()

            switch viewModel.state {
            case .idle:
                idleView
            case .loading:
                loadingView
            case .loaded(let data):
                guestInfoView(data)
            case .error(let message):
                errorView(message)
            }
        }
    }

    // MARK: - Idle (no URL yet)

    private var idleView: some View {
        VStack(spacing: 16) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 60))
                .foregroundColor(.clipGold)
            Text(t("QRコードからアクセスしてください",
                    "Please open from a QR code",
                    "请通过二维码访问",
                    "QR 코드로 접속해 주세요"))
                .font(.headline)
                .foregroundColor(.white)
            Text(t("ホストから共有されたリンクを使用してください",
                    "Use the link shared by your host",
                    "请使用房东分享的链接",
                    "호스트가 공유한 링크를 사용해 주세요"))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(.clipGold)
            Text(t("情報を取得中...", "Loading...", "加载中...", "불러오는 중..."))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.clipWarn)
            Text(message)
                .font(.headline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text(t("リンクが無効か、期限切れの可能性があります",
                    "The link may be invalid or expired",
                    "链接可能无效或已过期",
                    "링크가 유효하지 않거나 만료되었을 수 있습니다"))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    // MARK: - Guest Info

    private func guestInfoView(_ data: GuestData) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Language picker
                languagePicker

                // Welcome header
                welcomeHeader(data)

                // Check-in / Check-out times
                checkTimesCard

                // WiFi card
                if !data.wifiPassword.isEmpty {
                    wifiCard(data)
                }

                // Door code card
                if !data.doorCode.isEmpty {
                    doorCodeCard(data)
                }

                // Emergency contacts
                emergencyCard

                // Download full app CTA
                downloadBanner
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Sub-views

    private var languagePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(languages, id: \.0) { code, label in
                    Button { withAnimation { selectedLang = code } } label: {
                        Text(label).font(.caption).bold()
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(selectedLang == code ? Color.clipGold : Color.clipGold.opacity(0.1))
                            .foregroundColor(selectedLang == code ? .black : .clipGold)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func welcomeHeader(_ data: GuestData) -> some View {
        VStack(spacing: 6) {
            Text(t("ようこそ", "Welcome", "欢迎", "환영합니다"))
                .font(.caption)
                .foregroundColor(.secondary)
            Text(data.name)
                .font(.title).bold()
                .foregroundColor(.white)
            if !data.address.isEmpty {
                Text(data.address)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 12)
    }

    private var checkTimesCard: some View {
        ClipCard {
            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3)
                        .foregroundColor(.clipSuccess)
                    Text(t("チェックイン", "Check-in", "入住", "체크인"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("15:00")
                        .font(.title3).bold()
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 1, height: 50)

                VStack(spacing: 4) {
                    Image(systemName: "arrow.left.circle.fill")
                        .font(.title3)
                        .foregroundColor(.clipWarn)
                    Text(t("チェックアウト", "Check-out", "退房", "체크아웃"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("10:00")
                        .font(.title3).bold()
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
    }

    private func wifiCard(_ data: GuestData) -> some View {
        ClipCard {
            VStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "wifi")
                        .foregroundColor(.clipAccent)
                    Text("Wi-Fi")
                        .font(.subheadline).bold()
                        .foregroundColor(.white)
                    Spacer()
                    Button {
                        withAnimation { showWifiPassword.toggle() }
                    } label: {
                        Image(systemName: showWifiPassword ? "eye.slash" : "eye")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let qr = wifiQRImage(ssid: data.name, password: data.wifiPassword) {
                    qr
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 180, height: 180)
                        .padding(12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Text(t("カメラでスキャンして接続",
                        "Scan to connect",
                        "扫描连接",
                        "스캔하여 연결"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                if showWifiPassword {
                    HStack {
                        Text(t("パスワード:", "Password:", "密码:", "비밀번호:"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(data.wifiPassword)
                            .font(.caption).bold()
                            .foregroundColor(.white)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(16)
        }
    }

    private func doorCodeCard(_ data: GuestData) -> some View {
        ClipCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.clipGold.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "keypad.rectangle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.clipGold)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(t("ドアコード", "Door Code", "门禁密码", "도어코드"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(data.doorCode)
                        .font(.title2).bold()
                        .foregroundColor(.white)
                }

                Spacer()

                Button {
                    UIPasteboard.general.string = data.doorCode
                    withAnimation { copiedDoorCode = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { copiedDoorCode = false }
                    }
                } label: {
                    Image(systemName: copiedDoorCode ? "checkmark" : "doc.on.doc")
                        .font(.body)
                        .foregroundColor(copiedDoorCode ? .clipSuccess : .clipGold)
                        .frame(width: 36, height: 36)
                        .background(Color.clipGold.opacity(0.1))
                        .clipShape(Circle())
                }
            }
            .padding(16)
        }
    }

    private var emergencyCard: some View {
        ClipCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.clipWarn)
                    Text(t("緊急連絡先", "Emergency", "紧急联系", "긴급 연락처"))
                        .font(.subheadline).bold()
                        .foregroundColor(.white)
                }
                emergencyRow("110", t("警察", "Police", "警察", "경찰"))
                emergencyRow("119", t("消防・救急", "Fire/Ambulance", "消防/急救", "소방/구급"))
            }
            .padding(16)
        }
    }

    private func emergencyRow(_ number: String, _ label: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
            if let telURL = URL(string: "tel:\(number)") {
                Link(number, destination: telURL)
                    .font(.subheadline).bold()
                    .foregroundColor(.clipAccent)
            }
        }
    }

    private var downloadBanner: some View {
        ClipCard {
            VStack(spacing: 8) {
                Text(t("もっと便利に使うなら",
                        "Get the full experience",
                        "获取完整体验",
                        "더 편리하게 사용하기"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button {
                    // App Store link for KAGI
                    if let url = URL(string: "https://apps.apple.com/app/id6760736346") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.app.fill")
                        Text(t("KAGIをダウンロード",
                                "Download KAGI",
                                "下载 KAGI",
                                "KAGI 다운로드"))
                            .bold()
                    }
                    .font(.subheadline)
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.clipGold)
                    .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(16)
        }
    }

    // MARK: - QR Code Generator

    private func wifiQRImage(ssid: String, password: String) -> Image? {
        let payload = "WIFI:T:WPA;S:\(ssid);P:\(password);;"
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return Image(uiImage: UIImage(cgImage: cgImage))
    }
}

// MARK: - Theme Colors (standalone, no dependency on main app)

extension Color {
    static let clipBg         = Color(red: 10/255, green: 10/255, blue: 18/255)   // #0A0A12
    static let clipGold       = Color(red: 232/255, green: 168/255, blue: 56/255)  // #E8A838
    static let clipAccent     = Color(red: 59/255, green: 159/255, blue: 232/255)  // #3B9FE8
    static let clipSuccess    = Color(red: 16/255, green: 185/255, blue: 129/255)  // #10B981
    static let clipWarn       = Color(red: 245/255, green: 158/255, blue: 11/255)  // #F59E0B
    static let clipCard       = Color(white: 1, opacity: 0.06)
    static let clipCardBorder = Color(white: 1, opacity: 0.10)
}

// MARK: - Glass Card Component

struct ClipCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(Color.clipCard)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.clipCardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
