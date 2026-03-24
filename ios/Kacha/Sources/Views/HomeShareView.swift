import SwiftUI
import SwiftData
import CoreImage.CIFilterBuiltins

// MARK: - HomeShareView

struct HomeShareView: View {
    let home: Home
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
    @State private var noExpiry = false
    @State private var isCreating = false
    @State private var createdLink: String?
    @State private var showCopied = false
    @State private var errorMessage: String?

    private var sharePayload: HomeShareData {
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

    private var qrImage: Image? {
        guard let link = createdLink, let cgImage = generateQR(from: link) else { return nil }
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
                            Text("E2E暗号化で安全にシェアされます\nサーバーには暗号化データのみ保存されます")
                                .font(.caption).foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.top, 8)

                        // Period picker
                        KachaCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 6) {
                                    Image(systemName: "calendar.badge.clock").foregroundColor(.kacha)
                                    Text("アクセス期間").font(.subheadline).bold().foregroundColor(.white)
                                    Spacer()
                                    Toggle("無期限", isOn: $noExpiry)
                                        .toggleStyle(.switch)
                                        .tint(.kacha)
                                        .labelsHidden()
                                    Text("無期限").font(.caption2).foregroundColor(.secondary)
                                }

                                if !noExpiry {
                                    VStack(spacing: 8) {
                                        HStack {
                                            Text("開始").font(.caption).foregroundColor(.secondary).frame(width: 36)
                                            DatePicker("", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                                                .labelsHidden().tint(.kacha)
                                        }
                                        HStack {
                                            Text("終了").font(.caption).foregroundColor(.secondary).frame(width: 36)
                                            DatePicker("", selection: $endDate, in: startDate..., displayedComponents: [.date, .hourAndMinute])
                                                .labelsHidden().tint(.kacha)
                                        }
                                    }

                                    // Quick presets
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach([(1, "1日"), (3, "3日"), (7, "1週間"), (30, "1ヶ月")], id: \.0) { days, label in
                                                Button {
                                                    withAnimation {
                                                        startDate = Date()
                                                        endDate = Calendar.current.date(byAdding: .day, value: days, to: Date())!
                                                    }
                                                } label: {
                                                    Text(label).font(.caption2).bold()
                                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                                        .background(Color.kacha.opacity(0.1))
                                                        .foregroundColor(.kacha)
                                                        .clipShape(Capsule())
                                                }
                                            }
                                        }
                                    }

                                    let duration = endDate.timeIntervalSince(startDate)
                                    let days = Int(duration / 86400)
                                    let hours = Int((duration.truncatingRemainder(dividingBy: 86400)) / 3600)
                                    Text(days > 0 ? "\(days)日\(hours > 0 ? "\(hours)時間" : "")" : "\(hours)時間")
                                        .font(.caption2).foregroundColor(.secondary)
                                } else {
                                    Text("リンクは無期限で有効です（非推奨）")
                                        .font(.caption2).foregroundColor(.kachaWarn)
                                }
                            }
                            .padding(16)
                        }

                        // Security info
                        KachaCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 6) {
                                    Image(systemName: "lock.shield.fill").foregroundColor(.kachaSuccess)
                                    Text("セキュリティ").font(.subheadline).bold().foregroundColor(.white)
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    securityRow("lock.fill", "AES-256-GCM E2E暗号化")
                                    securityRow("server.rack", "サーバーに平文データは保存されません")
                                    securityRow("clock.badge.xmark", "期限切れで自動無効化")
                                    securityRow("xmark.circle", "いつでもシェア管理画面から取り消し可能")
                                }
                            }
                            .padding(16)
                        }

                        // What's shared
                        KachaCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.shield.fill").foregroundColor(.kachaSuccess)
                                    Text("共有される情報").font(.subheadline).bold().foregroundColor(.white)
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    shareRow("house.fill", "ホーム名・住所")
                                    if !home.switchBotToken.isEmpty { shareRow("lock.shield.fill", "SwitchBot認証情報") }
                                    if !home.sesameApiKey.isEmpty { shareRow("key.fill", "Sesame APIキー・UUID") }
                                    if !home.hueBridgeIP.isEmpty { shareRow("lightbulb.fill", "Philips Hue ブリッジ情報") }
                                    if !home.doorCode.isEmpty { shareRow("keypad.rectangle.fill", "ドアコード") }
                                    if !home.wifiPassword.isEmpty { shareRow("wifi", "Wi-Fiパスワード") }
                                }
                            }
                            .padding(16)
                        }

                        if let error = errorMessage {
                            Text(error).font(.caption).foregroundColor(.kachaDanger)
                        }

                        // Action: Create or Show result
                        if let link = createdLink {
                            // QR Code
                            if let qr = qrImage {
                                qr.interpolation(.none).resizable().scaledToFit()
                                    .frame(width: 220, height: 220)
                                    .padding(16).background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            }

                            VStack(spacing: 10) {
                                Button {
                                    UIPasteboard.general.string = link
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    withAnimation { showCopied = true }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        withAnimation { showCopied = false }
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: showCopied ? "checkmark.circle.fill" : "link")
                                        Text(showCopied ? "コピーしました！" : "リンクをコピー").bold()
                                    }
                                    .foregroundColor(showCopied ? .kachaSuccess : .kacha)
                                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                                    .background((showCopied ? Color.kachaSuccess : Color.kacha).opacity(0.12))
                                    .overlay(RoundedRectangle(cornerRadius: 13)
                                        .stroke((showCopied ? Color.kachaSuccess : Color.kacha).opacity(0.3)))
                                    .clipShape(RoundedRectangle(cornerRadius: 13))
                                }

                                ShareLink(item: link, subject: Text("カチャ - ホームをシェア"),
                                          message: Text("「\(home.name)」のスマートホームを一緒に操作しよう！")) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "square.and.arrow.up")
                                        Text("送信する").bold()
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                                    .background(Color.kacha)
                                    .clipShape(RoundedRectangle(cornerRadius: 13))
                                }

                                Button { dismiss() } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "calendar")
                                        Text("カレンダーで確認").bold()
                                    }
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                                }
                            }
                            .padding(.horizontal)
                        } else {
                            Button { Task { await createShare() } } label: {
                                HStack(spacing: 8) {
                                    if isCreating {
                                        ProgressView().tint(.black)
                                    } else {
                                        Image(systemName: "lock.shield.fill")
                                    }
                                    Text("暗号化してシェアリンクを作成").bold()
                                }
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Color.kacha)
                                .clipShape(RoundedRectangle(cornerRadius: 13))
                            }
                            .disabled(isCreating)
                            .padding(.horizontal)
                        }
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

    // MARK: - Create E2E Share

    private func createShare() async {
        isCreating = true
        errorMessage = nil
        do {
            let ownerToken = UUID().uuidString
            let validFrom = noExpiry ? nil : startDate
            let expiresAt = noExpiry ? nil : endDate

            let result = try await ShareClient.createShare(
                data: sharePayload,
                validFrom: validFrom,
                expiresAt: expiresAt,
                ownerToken: ownerToken
            )

            // Save record locally
            let record = ShareRecord(
                homeId: home.id,
                homeName: home.name,
                token: result.token,
                ownerToken: ownerToken,
                validFrom: validFrom ?? Date.distantPast,
                expiresAt: expiresAt ?? Date.distantFuture
            )
            context.insert(record)
            try? context.save()

            // Universal Link: https://kacha.pasha.run/join?t=TOKEN#KEY
            // The #fragment is never sent to the server
            let key = result.encryptionKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? result.encryptionKey
            createdLink = "https://kacha.pasha.run/join?t=\(result.token)#\(key)"

            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } catch {
            errorMessage = error.localizedDescription
        }
        isCreating = false
    }

    // MARK: - Helpers

    private func shareRow(_ icon: String, _ label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.caption).foregroundColor(.kacha).frame(width: 16)
            Text(label).font(.caption).foregroundColor(.secondary)
        }
    }

    private func securityRow(_ icon: String, _ label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.caption).foregroundColor(.kachaAccent).frame(width: 16)
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

// MARK: - Share Payload (encrypted, never stored in plaintext on server)

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

// MARK: - Key Rotation View

struct KeyRotationView: View {
    @Bindable var home: Home
    @Environment(\.dismiss) private var dismiss
    @State private var hueRotating = false
    @State private var hueSuccess = false
    @State private var hueError: String?
    @State private var showConfirm = false

    private var services: [(icon: String, name: String, hasKey: Bool, portalURL: String?)] {
        [
            ("lock.shield.fill", "SwitchBot", !home.switchBotToken.isEmpty,
             "https://app.switch-bot.com"),
            ("key.fill", "Sesame", !home.sesameApiKey.isEmpty,
             "https://partners.candyhouse.co"),
            ("lightbulb.fill", "Philips Hue", !home.hueBridgeIP.isEmpty, nil),
            ("lock.fill", "Nuki", false,
             "https://web.nuki.io"),
        ]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 8) {
                            Image(systemName: "key.rotate")
                                .font(.system(size: 44))
                                .foregroundColor(.kachaWarn)
                            Text("APIキーを入れ替え")
                                .font(.title3).bold().foregroundColor(.white)
                            Text("共有を終了した後、古いキーを無効化して\n新しいキーに入れ替えることでセキュリティを確保します")
                                .font(.caption).foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 8)

                        if !home.hueBridgeIP.isEmpty {
                            KachaCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "lightbulb.fill").foregroundColor(.kacha)
                                        Text("Philips Hue").font(.subheadline).bold().foregroundColor(.white)
                                        Spacer()
                                        if hueSuccess {
                                            Label("完了", systemImage: "checkmark.circle.fill")
                                                .font(.caption).foregroundColor(.kachaSuccess)
                                        }
                                    }
                                    Text("Hueブリッジのリンクボタンを押してから\n「新しいキーを発行」をタップしてください")
                                        .font(.caption).foregroundColor(.secondary)
                                    if let err = hueError {
                                        Text(err).font(.caption2).foregroundColor(.kachaDanger)
                                    }
                                    Button {
                                        Task { await rotateHueKey() }
                                    } label: {
                                        HStack(spacing: 6) {
                                            if hueRotating { ProgressView().tint(.black) }
                                            else { Image(systemName: "arrow.triangle.2.circlepath") }
                                            Text("新しいキーを発行").bold()
                                        }
                                        .font(.caption).foregroundColor(.black)
                                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                                        .background(Color.kacha)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    .disabled(hueRotating)
                                }
                                .padding(16)
                            }
                        }

                        ForEach(services.filter({ $0.hasKey && $0.portalURL != nil }), id: \.name) { svc in
                            KachaCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(spacing: 8) {
                                        Image(systemName: svc.icon).foregroundColor(.kacha)
                                        Text(svc.name).font(.subheadline).bold().foregroundColor(.white)
                                    }
                                    Text("開発者ポータルでAPIキーを再発行し、\n古いキーを削除してください")
                                        .font(.caption).foregroundColor(.secondary)
                                    HStack(spacing: 10) {
                                        if let url = svc.portalURL, let link = URL(string: url) {
                                            Link(destination: link) {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "arrow.up.right.square")
                                                    Text("ポータルを開く").bold()
                                                }
                                                .font(.caption).foregroundColor(.kacha)
                                                .padding(.horizontal, 16).padding(.vertical, 10)
                                                .background(Color.kacha.opacity(0.12))
                                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                            }
                                        }
                                        Button { showConfirm = true } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "pencil")
                                                Text("キーを更新").bold()
                                            }
                                            .font(.caption).foregroundColor(.black)
                                            .padding(.horizontal, 16).padding(.vertical, 10)
                                            .background(Color.kacha)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                        }
                                    }
                                }
                                .padding(16)
                            }
                        }

                        if !home.doorCode.isEmpty || !home.wifiPassword.isEmpty {
                            KachaCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "rectangle.and.pencil.and.ellipsis").foregroundColor(.kacha)
                                        Text("コード・パスワード").font(.subheadline).bold().foregroundColor(.white)
                                    }
                                    Text("ドアコードやWi-Fiパスワードを変更した場合は\n設定画面から新しい値を入力してください")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                .padding(16)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("キーの入れ替え")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }.foregroundStyle(.secondary)
                }
            }
            .alert("新しいAPIキーを入力", isPresented: $showConfirm) {
                Button("設定画面へ") { dismiss() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("ポータルで新しいキーを発行した後、設定画面の各サービス欄に貼り付けてください。")
            }
        }
    }

    private func rotateHueKey() async {
        hueRotating = true
        hueError = nil
        do {
            let newUsername = try await HueClient.shared.register(bridgeIP: home.hueBridgeIP)
            if !home.hueUsername.isEmpty {
                let deleteURL = URL(string: "http://\(home.hueBridgeIP)/api/\(home.hueUsername)/config/whitelist/\(home.hueUsername)")!
                var req = URLRequest(url: deleteURL)
                req.httpMethod = "DELETE"
                _ = try? await URLSession.shared.data(for: req)
            }
            home.hueUsername = newUsername
            home.syncToAppStorage()
            hueSuccess = true
        } catch {
            hueError = "ブリッジのリンクボタンを押してから再試行してください"
        }
        hueRotating = false
    }
}
