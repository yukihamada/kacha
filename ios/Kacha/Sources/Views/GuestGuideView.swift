import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - Multi-language Guest Guide Generator

struct GuestGuideView: View {
    let home: Home
    @State private var selectedLanguage = "ja"
    @State private var showShareSheet = false
    @State private var generatedGuide = ""

    private var languages: [(code: String, label: String, flag: String)] {
        [("ja", "日本語", "🇯🇵"), ("en", "English", "🇺🇸"), ("zh", "中文", "🇨🇳"), ("ko", "한국어", "🇰🇷")]
    }

    private var guide: String {
        generateGuide(language: selectedLanguage)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        // Language picker
                        HStack(spacing: 8) {
                            ForEach(languages, id: \.code) { lang in
                                Button {
                                    withAnimation { selectedLanguage = lang.code }
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(lang.flag).font(.title2)
                                        Text(lang.label).font(.system(size: 10, weight: .medium))
                                            .foregroundColor(selectedLanguage == lang.code ? .kacha : .secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(selectedLanguage == lang.code ? Color.kacha.opacity(0.12) : Color.kachaCard)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(selectedLanguage == lang.code ? Color.kacha.opacity(0.4) : Color.clear, lineWidth: 1)
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 16)

                        // WiFi QR Code
                        if !home.wifiPassword.isEmpty {
                            KachaCard {
                                VStack(spacing: 12) {
                                    if let qr = generateWiFiQR() {
                                        Image(uiImage: UIImage(cgImage: qr))
                                            .interpolation(.none)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 160, height: 160)
                                            .padding(12)
                                            .background(Color.white)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                    Text(localizedLabel("wifi_scan", selectedLanguage))
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity)
                            }
                            .padding(.horizontal, 16)
                        }

                        // Guide content
                        KachaCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: "book.fill").foregroundColor(.kacha)
                                    Text(localizedLabel("house_manual", selectedLanguage))
                                        .font(.subheadline).bold().foregroundColor(.white)
                                }

                                Text(guide)
                                    .font(.system(.caption, design: .default))
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                                    .lineSpacing(4)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 16)

                        // Actions
                        HStack(spacing: 10) {
                            ShareLink(item: guide) {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("送信").bold()
                                }
                                .font(.subheadline).foregroundColor(.black)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(Color.kacha)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }

                            Button {
                                UIPasteboard.general.string = guide
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.on.doc")
                                    Text("コピー").bold()
                                }
                                .font(.subheadline).foregroundColor(.kacha)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(Color.kacha.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("ゲストガイド")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Guide Generation

    private func generateGuide(language: String) -> String {
        let l = language
        var sections: [String] = []

        // Welcome
        sections.append(localizedSection("welcome", l, [
            "{homeName}": home.name,
            "{address}": home.address,
        ]))

        // Door code
        if !home.doorCode.isEmpty {
            sections.append(localizedSection("door", l, [
                "{doorCode}": home.doorCode,
                "{roomNumber}": home.autolockRoomNumber,
            ]))
        }

        // WiFi
        if !home.wifiPassword.isEmpty {
            sections.append(localizedSection("wifi", l, [
                "{wifiPassword}": home.wifiPassword,
            ]))
        }

        // House rules
        sections.append(localizedSection("rules", l, [:]))

        // Emergency
        sections.append(localizedSection("emergency", l, [:]))

        // Checkout
        sections.append(localizedSection("checkout", l, [:]))

        return sections.joined(separator: "\n\n")
    }

    private func localizedSection(_ key: String, _ lang: String, _ vars: [String: String]) -> String {
        var text = sections[key]?[lang] ?? sections[key]?["ja"] ?? ""
        for (k, v) in vars { text = text.replacingOccurrences(of: k, with: v) }
        return text
    }

    private func localizedLabel(_ key: String, _ lang: String) -> String {
        labels[key]?[lang] ?? labels[key]?["ja"] ?? key
    }

    // MARK: - WiFi QR

    private func generateWiFiQR() -> CGImage? {
        let wifiString = "WIFI:T:WPA;S:\(home.name);P:\(home.wifiPassword);;"
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(wifiString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        return context.createCGImage(scaled, from: scaled.extent)
    }

    // MARK: - Localized Content

    private let labels: [String: [String: String]] = [
        "wifi_scan": ["ja": "QRコードをスキャンしてWi-Fiに接続", "en": "Scan to connect to Wi-Fi", "zh": "扫码连接Wi-Fi", "ko": "QR코드를 스캔하여 Wi-Fi 연결"],
        "house_manual": ["ja": "ハウスマニュアル", "en": "House Manual", "zh": "房屋指南", "ko": "하우스 매뉴얼"],
    ]

    private let sections: [String: [String: String]] = [
        "welcome": [
            "ja": "🏠 ようこそ {homeName} へ\n\n住所: {address}\n\nご滞在をお楽しみください。",
            "en": "🏠 Welcome to {homeName}\n\nAddress: {address}\n\nEnjoy your stay!",
            "zh": "🏠 欢迎来到 {homeName}\n\n地址：{address}\n\n祝您住宿愉快！",
            "ko": "🏠 {homeName}에 오신 것을 환영합니다\n\n주소: {address}\n\n즐거운 숙박 되세요!",
        ],
        "door": [
            "ja": "🔑 入室方法\n\nドアコード: {doorCode}\n部屋番号: {roomNumber}\n\nドアのテンキーにコードを入力してください。",
            "en": "🔑 How to Enter\n\nDoor Code: {doorCode}\nRoom: {roomNumber}\n\nEnter the code on the door keypad.",
            "zh": "🔑 入住方式\n\n门锁密码：{doorCode}\n房间号：{roomNumber}\n\n在门上的键盘输入密码即可。",
            "ko": "🔑 입실 방법\n\n도어 코드: {doorCode}\n호실: {roomNumber}\n\n도어 키패드에 코드를 입력하세요.",
        ],
        "wifi": [
            "ja": "📶 Wi-Fi\n\nパスワード: {wifiPassword}\n\n上のQRコードをスマホで読み取ると自動接続できます。",
            "en": "📶 Wi-Fi\n\nPassword: {wifiPassword}\n\nScan the QR code above to connect automatically.",
            "zh": "📶 Wi-Fi\n\n密码：{wifiPassword}\n\n扫描上方二维码可自动连接。",
            "ko": "📶 Wi-Fi\n\n비밀번호: {wifiPassword}\n\n위의 QR코드를 스캔하면 자동 연결됩니다.",
        ],
        "rules": [
            "ja": "📋 ハウスルール\n\n• 22:00以降はお静かにお願いします\n• 室内禁煙（ベランダ・屋外喫煙可）\n• ゴミは分別してゴミ箱へ\n• パーティー・大人数の集まりはご遠慮ください",
            "en": "📋 House Rules\n\n• Please be quiet after 10:00 PM\n• No smoking indoors (balcony/outdoor OK)\n• Please separate garbage into designated bins\n• No parties or large gatherings",
            "zh": "📋 房屋规则\n\n• 晚上10点后请保持安静\n• 室内禁止吸烟（阳台/室外可以）\n• 垃圾请分类投放\n• 禁止举办派对或大型聚会",
            "ko": "📋 하우스 규칙\n\n• 밤 10시 이후 조용히 해주세요\n• 실내 금연 (발코니/야외 흡연 가능)\n• 쓰레기는 분리수거해 주세요\n• 파티 및 대규모 모임 금지",
        ],
        "emergency": [
            "ja": "🆘 緊急連絡先\n\n• 警察: 110\n• 救急・消防: 119\n• 近くの病院は Google Maps で「病院」と検索\n• ホストへの連絡はメッセージでお願いします",
            "en": "🆘 Emergency Contacts\n\n• Police: 110\n• Ambulance/Fire: 119\n• Search \"hospital\" on Google Maps for nearby\n• Contact host via message for non-emergencies",
            "zh": "🆘 紧急联系方式\n\n• 警察：110\n• 急救/消防：119\n• 在Google Maps搜索\"医院\"查找附近医院\n• 非紧急情况请通过消息联系房东",
            "ko": "🆘 긴급 연락처\n\n• 경찰: 110\n• 구급/소방: 119\n• Google Maps에서 \"병원\"을 검색하세요\n• 긴급하지 않은 경우 메시지로 연락해주세요",
        ],
        "checkout": [
            "ja": "🚪 チェックアウト\n\n• 鍵をドア内側に置いてください\n• 照明・エアコンをお切りください\n• 窓を閉めてください\n• ゴミはまとめてゴミ箱へ\n\nありがとうございました！またのお越しをお待ちしております。",
            "en": "🚪 Check-out\n\n• Leave the key inside the door\n• Turn off all lights and AC\n• Close all windows\n• Collect garbage into bins\n\nThank you for staying! We hope to see you again.",
            "zh": "🚪 退房\n\n• 请将钥匙放在门内\n• 关闭所有灯光和空调\n• 关好所有窗户\n• 垃圾收集到垃圾桶\n\n感谢您的入住！期待再次见到您。",
            "ko": "🚪 체크아웃\n\n• 열쇠를 문 안쪽에 놓아주세요\n• 모든 조명과 에어컨을 꺼주세요\n• 창문을 닫아주세요\n• 쓰레기를 쓰레기통에 모아주세요\n\n숙박해 주셔서 감사합니다! 다시 뵙기를 기대합니다.",
        ],
    ]
}
