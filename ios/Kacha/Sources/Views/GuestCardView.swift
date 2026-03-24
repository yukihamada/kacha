import SwiftUI
import SwiftData
import CoreImage.CIFilterBuiltins

// MARK: - Guest Card — WiFi QR + door code + nearby places + emergency info

struct GuestCardView: View {
    let home: Home
    @Query private var allPlaces: [NearbyPlace]
    @Environment(\.dismiss) private var dismiss
    @State private var showWifiPassword = false
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

    private var places: [NearbyPlace] { allPlaces.filter { $0.homeId == home.id } }

    private var wifiQR: Image? {
        // iOS standard WiFi QR: WIFI:T:WPA;S:<SSID>;P:<password>;;
        guard !home.wifiPassword.isEmpty else { return nil }
        let ssid = home.name // use home name as SSID hint
        let payload = "WIFI:T:WPA;S:\(ssid);P:\(home.wifiPassword);;"
        guard let cgImage = generateQR(from: payload) else { return nil }
        return Image(uiImage: UIImage(cgImage: cgImage))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // Language picker
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(languages, id: \.0) { code, label in
                                    Button { withAnimation { selectedLang = code } } label: {
                                        Text(label).font(.caption).bold()
                                            .padding(.horizontal, 12).padding(.vertical, 6)
                                            .background(selectedLang == code ? Color.kacha : Color.kacha.opacity(0.1))
                                            .foregroundColor(selectedLang == code ? .black : .kacha)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                        // Welcome
                        VStack(spacing: 4) {
                            Text(t("ようこそ", "Welcome", "欢迎", "환영합니다"))
                                .font(.caption).foregroundColor(.secondary)
                            Text(home.name).font(.title).bold().foregroundColor(.white)
                            if !home.address.isEmpty {
                                Text(home.address).font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .padding(.top, 8)

                        // WiFi QR
                        if !home.wifiPassword.isEmpty {
                            KachaCard {
                                VStack(spacing: 12) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "wifi").foregroundColor(.kachaAccent)
                                        Text("Wi-Fi").font(.subheadline).bold().foregroundColor(.white)
                                        Spacer()
                                        Button { withAnimation { showWifiPassword.toggle() } } label: {
                                            Image(systemName: showWifiPassword ? "eye.slash" : "eye")
                                                .font(.caption).foregroundColor(.secondary)
                                        }
                                    }
                                    if let qr = wifiQR {
                                        qr.interpolation(.none).resizable().scaledToFit()
                                            .frame(width: 180, height: 180)
                                            .padding(12).background(Color.white)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                    Text(t("カメラでスキャンして接続", "Scan to connect", "扫描连接", "스캔하여 연결"))
                                        .font(.caption).foregroundColor(.secondary)
                                    if showWifiPassword {
                                        HStack {
                                            Text("パスワード:").font(.caption).foregroundColor(.secondary)
                                            Text(home.wifiPassword).font(.caption).bold().foregroundColor(.white)
                                                .textSelection(.enabled)
                                        }
                                    }
                                }
                                .padding(16)
                            }
                        }

                        // Door code
                        if !home.doorCode.isEmpty {
                            KachaCard {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(Color.kacha.opacity(0.15)).frame(width: 44, height: 44)
                                        Image(systemName: "keypad.rectangle.fill").font(.system(size: 20)).foregroundColor(.kacha)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(t("ドアコード", "Door Code", "门禁密码", "도어코드"))
                                            .font(.caption).foregroundColor(.secondary)
                                        Text(home.doorCode).font(.title2).bold().foregroundColor(.white)
                                            .textSelection(.enabled)
                                    }
                                    Spacer()
                                }
                                .padding(16)
                            }
                        }

                        // Nearby places
                        if !places.isEmpty {
                            KachaCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "mappin.and.ellipse").foregroundColor(.kachaSuccess)
                                        Text(t("近くの施設", "Nearby", "附近设施", "주변 시설"))
                                            .font(.subheadline).bold().foregroundColor(.white)
                                    }
                                    ForEach(places) { place in
                                        let info = NearbyPlace.categoryInfo.first { $0.key == place.category }
                                        HStack(spacing: 10) {
                                            Image(systemName: info?.icon ?? "mappin").font(.caption)
                                                .foregroundColor(.kacha).frame(width: 20)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(place.name).font(.subheadline).foregroundColor(.white)
                                                if !place.note.isEmpty {
                                                    Text(place.note).font(.caption2).foregroundColor(.secondary)
                                                }
                                            }
                                            Spacer()
                                        }
                                        if place.id != places.last?.id {
                                            Divider().background(Color.kachaCardBorder)
                                        }
                                    }
                                }
                                .padding(16)
                            }
                        }

                        // Emergency
                        KachaCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.kachaWarn)
                                    Text(t("緊急連絡先", "Emergency", "紧急联系", "긴급 연락처"))
                                        .font(.subheadline).bold().foregroundColor(.white)
                                }
                                emergencyRow("110", t("警察", "Police", "警察", "경찰"))
                                emergencyRow("119", t("消防・救急", "Fire/Ambulance", "消防/急救", "소방/구급"))
                            }
                            .padding(16)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("ゲストカード")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }.foregroundStyle(.secondary)
                }
            }
        }
    }

    private func emergencyRow(_ number: String, _ label: String) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.caption).foregroundColor(.secondary).frame(width: 60, alignment: .leading)
            Link(number, destination: URL(string: "tel:\(number)")!)
                .font(.subheadline).bold().foregroundColor(.kachaAccent)
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
