import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - SettingsView (Home Picker + Active Home Settings)

struct SettingsView: View {
    @Query(sort: \Home.sortOrder) private var homes: [Home]
    @AppStorage("activeHomeId") private var activeHomeId = ""
    @AppStorage("minpakuModeEnabled") private var minpakuModeEnabled = false
    @Environment(\.modelContext) private var modelContext

    @State private var showAddHome = false
    @State private var newHomeName = ""
    @State private var showDeleteAlert = false
    @State private var homeToDelete: Home?

    var activeHome: Home? { homes.first { $0.id == activeHomeId } }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        homesPickerSection
                        if let home = activeHome {
                            HomeSettingsSections(
                                home: home,
                                minpakuModeEnabled: $minpakuModeEnabled,
                                onAlert: nil
                            )
                        } else {
                            emptyState
                        }
                        appInfoSection
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.kachaBg, for: .navigationBar)
            .sheet(isPresented: $showAddHome) { addHomeSheet }
            .alert("ホームを削除", isPresented: $showDeleteAlert) {
                Button("削除", role: .destructive) { deleteHome() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("\(homeToDelete?.name ?? "")を削除しますか？")
            }
        }
    }

    // MARK: - Homes Picker

    private var homesPickerSection: some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SettingsHeader(icon: "house.fill", title: "ホーム", color: .kacha)
                    Spacer()
                    Button {
                        newHomeName = ""; showAddHome = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.kacha)
                            .font(.title3)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(homes) { home in
                            HomeChip(
                                home: home,
                                isActive: home.id == activeHomeId,
                                onSelect: { switchHome(home) },
                                onDelete: { homeToDelete = home; showDeleteAlert = true }
                            )
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var emptyState: some View {
        KachaCard {
            VStack(spacing: 12) {
                Image(systemName: "house.badge.questionmark.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text("ホームを追加してください")
                    .foregroundColor(.secondary)
                Button("ホームを追加") { newHomeName = ""; showAddHome = true }
                    .foregroundColor(.kacha)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
    }

    private var addHomeSheet: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                VStack(spacing: 20) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.kacha)
                        .padding(.top, 40)
                    TextField("家の名前（例: 渋谷の部屋）", text: $newHomeName)
                        .foregroundColor(.white)
                        .padding(14)
                        .background(Color.kachaCard)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.kachaCardBorder))
                        .padding(.horizontal, 24)
                    Spacer()
                }
            }
            .navigationTitle("ホームを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { showAddHome = false }.foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") { addHome() }
                        .foregroundColor(.kacha)
                        .disabled(newHomeName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - App Info

    private var appInfoSection: some View {
        KachaCard {
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "door.left.hand.open").foregroundColor(.kacha)
                    Text("カチャ").font(.subheadline).bold().foregroundColor(.white)
                    Spacer()
                    Text("v1.0.0").font(.caption).foregroundColor(.secondary)
                }
                Text("開いた、ウェルカム。")
                    .font(.caption).foregroundColor(.kacha)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
    }

    // MARK: - Actions

    private func switchHome(_ home: Home) {
        activeHomeId = home.id
        home.syncToAppStorage()
    }

    private func addHome() {
        let name = newHomeName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let home = Home(name: name, sortOrder: homes.count)
        modelContext.insert(home)
        try? modelContext.save()
        switchHome(home)
        showAddHome = false
    }

    private func deleteHome() {
        guard let home = homeToDelete else { return }
        modelContext.delete(home)
        try? modelContext.save()
        if activeHomeId == home.id {
            if let first = homes.first(where: { $0.id != home.id }) {
                switchHome(first)
            } else {
                activeHomeId = ""
            }
        }
    }
}

// MARK: - Home Chip

private struct HomeChip: View {
    let home: Home
    let isActive: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Image(systemName: isActive ? "house.fill" : "house")
                    .font(.caption)
                Text(home.name)
                    .font(.subheadline).fontWeight(isActive ? .bold : .regular)
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                }
            }
            .foregroundColor(isActive ? .kachaBg : .white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(isActive ? Color.kacha : Color.kachaCard)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isActive ? Color.clear : Color.kachaCardBorder))
        }
        .contextMenu {
            Button(role: .destructive) { onDelete() } label: {
                Label("削除", systemImage: "trash")
            }
        }
    }
}

// MARK: - HomeSettingsSections

struct HomeSettingsSections: View {
    @Bindable var home: Home
    @Binding var minpakuModeEnabled: Bool
    var onAlert: ((String, String) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Query private var bookings: [Booking]
    @Query private var allIntegrations: [DeviceIntegration]

    @State private var isDiscoveringBridge = false
    @State private var isRegisteringBridge = false
    @State private var isFetchingSwitchBot = false
    @State private var isTestingSesame = false
    @State private var isSyncingICal = false
    @State private var isSyncingBeds24 = false
    @State private var showHueInstructions = false
    @State private var showICalFileImporter = false
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAddDevice = false

    private var integrations: [DeviceIntegration] { allIntegrations.filter { $0.homeId == home.id } }

    var body: some View {
        Group {
            homeInfoSection
            doorSection
            switchBotSection
            hueSection
            sesameSection
            qrioSection
            deviceIntegrationsSection
            if minpakuModeEnabled {
                beds24Section
                icalSection
                minpakuSection
                sakutsuSection
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
        .fileImporter(
            isPresented: $showICalFileImporter,
            allowedContentTypes: [UTType.calendarEvent, UTType(filenameExtension: "ics") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await importICalFile(url: url) }
            }
        }
        .sheet(isPresented: $showAddDevice) {
            AddDeviceView(homeId: home.id)
        }
    }

    // MARK: - Sections

    private var homeInfoSection: some View {
        KachaCard {
            VStack(spacing: 14) {
                SettingsHeader(icon: "house.fill", title: "ホーム情報", color: .kacha)
                SettingsTextField(label: "家の名前", placeholder: "例: 我が家、渋谷の部屋", text: $home.name)
                    .onChange(of: home.name) { _, val in UserDefaults.standard.set(val, forKey: "facilityName") }
                Divider().background(Color.kachaCardBorder)
                SettingsTextField(label: "住所", placeholder: "東京都渋谷区...", text: $home.address)
                    .onChange(of: home.address) { _, val in UserDefaults.standard.set(val, forKey: "facilityAddress") }
            }
            .padding(16)
        }
    }

    private var doorSection: some View {
        KachaCard {
            VStack(spacing: 14) {
                SettingsHeader(icon: "bubble.left.and.bubble.right.fill", title: "ゲスト案内", color: .kachaSuccess)
                SettingsTextField(label: "ドアコード", placeholder: "例: 1234", text: $home.doorCode)
                    .onChange(of: home.doorCode) { _, val in UserDefaults.standard.set(val, forKey: "facilityDoorCode") }
                Divider().background(Color.kachaCardBorder)
                SettingsTextField(label: "Wi-Fi", placeholder: "パスワード", text: $home.wifiPassword)
                    .onChange(of: home.wifiPassword) { _, val in UserDefaults.standard.set(val, forKey: "facilityWifiPassword") }
            }
            .padding(16)
        }
    }

    // MARK: SwitchBot

    private var switchBotSection: some View {
        KachaCard {
            VStack(spacing: 14) {
                SettingsHeader(icon: "lock.shield.fill", title: "SwitchBot", color: .kachaAccent)
                ApiGuideRow(
                    label: "APIキーの取得",
                    urlString: "https://support.switch-bot.com/hc/ja/articles/12822710195351",
                    note: "SwitchBotアプリ → プロフィール → 開発者向けオプション"
                )
                Divider().background(Color.kachaCardBorder)
                SettingsTextField(label: "APIトークン", placeholder: "SwitchBot APIトークン", text: $home.switchBotToken, isSecure: true)
                    .onChange(of: home.switchBotToken) { _, val in UserDefaults.standard.set(val, forKey: "switchBotToken") }
                Divider().background(Color.kachaCardBorder)
                SettingsTextField(label: "シークレット", placeholder: "クライアントシークレット", text: $home.switchBotSecret, isSecure: true)
                    .onChange(of: home.switchBotSecret) { _, val in UserDefaults.standard.set(val, forKey: "switchBotSecret") }
                Divider().background(Color.kachaCardBorder)
                Button { Task { await testSwitchBot() } } label: {
                    HStack {
                        if isFetchingSwitchBot { ProgressView().tint(.kachaAccent) }
                        else { Image(systemName: "arrow.clockwise") }
                        Text("デバイスを取得")
                    }
                    .actionButtonStyle(.kachaAccent)
                }
                .disabled(isFetchingSwitchBot || home.switchBotToken.isEmpty)
            }
            .padding(16)
        }
    }

    // MARK: Philips Hue

    private var hueSection: some View {
        KachaCard {
            VStack(spacing: 14) {
                SettingsHeader(icon: "lightbulb.fill", title: "Philips Hue", color: .kacha)
                ApiGuideRow(
                    label: "セットアップ方法",
                    urlString: "https://developers.meethue.com/develop/get-started-2/",
                    note: "ブリッジと同じWi-Fiに接続した状態でブリッジ検索"
                )
                Divider().background(Color.kachaCardBorder)
                SettingsTextField(label: "ブリッジIP", placeholder: "192.168.1.100", text: $home.hueBridgeIP)
                    .onChange(of: home.hueBridgeIP) { _, val in UserDefaults.standard.set(val, forKey: "hueBridgeIP") }
                Divider().background(Color.kachaCardBorder)
                SettingsTextField(label: "ユーザー名", placeholder: "ブリッジ登録後に取得", text: $home.hueUsername)
                    .onChange(of: home.hueUsername) { _, val in UserDefaults.standard.set(val, forKey: "hueUsername") }
                Divider().background(Color.kachaCardBorder)
                HStack(spacing: 8) {
                    Button { Task { await discoverBridge() } } label: {
                        HStack {
                            if isDiscoveringBridge { ProgressView().tint(.kachaAccent) }
                            else { Image(systemName: "magnifyingglass") }
                            Text("ブリッジ検索")
                        }
                        .actionButtonStyle(.kachaAccent)
                    }
                    .disabled(isDiscoveringBridge)
                    Button { Task { await registerBridge() } } label: {
                        HStack {
                            if isRegisteringBridge { ProgressView().tint(.kacha) }
                            else { Image(systemName: "link") }
                            Text("ペアリング")
                        }
                        .actionButtonStyle(.kacha)
                    }
                    .disabled(isRegisteringBridge || home.hueBridgeIP.isEmpty)
                }
                if showHueInstructions {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill").foregroundColor(.kachaWarn)
                        Text("ブリッジのリンクボタンを押してから「ペアリング」をタップ")
                            .font(.caption).foregroundColor(.kachaWarn)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: Sesame

    private var sesameSection: some View {
        KachaCard {
            VStack(spacing: 14) {
                SettingsHeader(icon: "key.fill", title: "Sesame（CANDY HOUSE）", color: .kachaSuccess)
                ApiGuideRow(
                    label: "APIキーの取得",
                    urlString: "https://partners.candyhouse.co/",
                    note: "Sesameアプリ → デバイス → 歯車 → UUID をコピー / パートナーポータルでAPIキー発行"
                )
                Divider().background(Color.kachaCardBorder)
                SettingsTextField(label: "APIキー", placeholder: "xxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", text: $home.sesameApiKey, isSecure: true)
                Divider().background(Color.kachaCardBorder)
                SettingsTextField(label: "デバイスUUID", placeholder: "UUIDをカンマ区切りで（複数可）", text: $home.sesameDeviceUUIDs)
                Divider().background(Color.kachaCardBorder)
                Button { Task { await testSesame() } } label: {
                    HStack {
                        if isTestingSesame { ProgressView().tint(.kachaSuccess) }
                        else { Image(systemName: "arrow.clockwise") }
                        Text("接続テスト")
                    }
                    .actionButtonStyle(.kachaSuccess)
                }
                .disabled(isTestingSesame || home.sesameApiKey.isEmpty || home.sesameDeviceUUIDs.isEmpty)
            }
            .padding(16)
        }
    }

    // MARK: Qrio

    private var qrioSection: some View {
        KachaCard {
            VStack(spacing: 14) {
                SettingsHeader(icon: "key.horizontal.fill", title: "Qrio Lock", color: .kachaAccent)
                ApiGuideRow(
                    label: "開発者プログラムに申請",
                    urlString: "https://qrio.me/developer/",
                    note: "Qrioのクラウド連携にはQ-Hubが必要です"
                )
                Divider().background(Color.kachaCardBorder)
                SettingsTextField(label: "APIキー", placeholder: "Qrio APIキー（要申請）", text: $home.qrioApiKey, isSecure: true)
                Divider().background(Color.kachaCardBorder)
                SettingsTextField(label: "デバイスID", placeholder: "デバイスIDをカンマ区切りで", text: $home.qrioDeviceIds)
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").foregroundColor(.secondary).font(.caption)
                    Text("Qrio APIは開発者プログラムへの申請が必要です")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(16)
        }
    }

    // MARK: Device Integrations

    private var deviceIntegrationsSection: some View {
        KachaCard {
            VStack(spacing: 14) {
                HStack {
                    SettingsHeader(icon: "cpu.fill", title: "その他デバイス連携", color: .kachaAccent)
                    Spacer()
                    Button { showAddDevice = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.kachaAccent)
                            .font(.title3)
                    }
                }
                if integrations.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.rectangle.on.folder.fill")
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Nature Remo / Nuki / Tuya など").font(.subheadline).foregroundColor(.white)
                            Text("「＋」をタップしてデバイスを追加").font(.caption).foregroundColor(.secondary)
                        }
                    }
                } else {
                    ForEach(integrations) { integration in
                        Divider().background(Color.kachaCardBorder)
                        IntegrationRow(integration: integration) {
                            modelContext.delete(integration)
                            try? modelContext.save()
                        }
                    }
                    Divider().background(Color.kachaCardBorder)
                    Button { showAddDevice = true } label: {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text("デバイスを追加")
                        }
                        .font(.subheadline).foregroundColor(.kachaAccent)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: Beds24

    private var beds24Section: some View {
        KachaCard {
            VStack(spacing: 14) {
                SettingsHeader(icon: "calendar.badge.clock", title: "Beds24", color: Color(hex: "0066CC"))
                ApiGuideRow(
                    label: "APIキーの取得",
                    urlString: "https://beds24.com/control2.php?pagetype=account&pagemode=apikeys",
                    note: "Beds24ダッシュボード → Settings → Account → API Keys"
                )
                Divider().background(Color.kachaCardBorder)
                SettingsTextField(label: "APIキー", placeholder: "Beds24 v2 APIキー", text: $home.beds24ApiKey, isSecure: true)
                Divider().background(Color.kachaCardBorder)
                SettingsTextField(label: "iCal URL", placeholder: "beds24.com/ical.php?propKey=...", text: $home.beds24ICalURL)
                Divider().background(Color.kachaCardBorder)
                Button { Task { await syncBeds24() } } label: {
                    HStack {
                        if isSyncingBeds24 { ProgressView().tint(.kacha) }
                        else { Image(systemName: "arrow.clockwise") }
                        Text("予約を同期")
                    }
                    .actionButtonStyle(.kacha)
                }
                .disabled(isSyncingBeds24 || (home.beds24ApiKey.isEmpty && home.beds24ICalURL.isEmpty))
            }
            .padding(16)
        }
    }

    // MARK: iCal

    private var icalSection: some View {
        KachaCard {
            VStack(spacing: 14) {
                SettingsHeader(icon: "calendar.badge.plus", title: "iCal連携", color: .kachaAccent)
                SettingsTextField(label: "Airbnb URL", placeholder: "https://www.airbnb.com/calendar/ical/...", text: $home.airbnbICalURL)
                    .onChange(of: home.airbnbICalURL) { _, val in UserDefaults.standard.set(val, forKey: "airbnbICalURL") }
                Divider().background(Color.kachaCardBorder)
                SettingsTextField(label: "じゃらん URL", placeholder: "https://calendar.jalan.net/...", text: $home.jalanICalURL)
                    .onChange(of: home.jalanICalURL) { _, val in UserDefaults.standard.set(val, forKey: "jalanICalURL") }
                Divider().background(Color.kachaCardBorder)
                HStack(spacing: 8) {
                    Button { Task { await syncICalFeeds() } } label: {
                        HStack {
                            if isSyncingICal { ProgressView().tint(.kachaAccent) }
                            else { Image(systemName: "arrow.clockwise") }
                            Text("今すぐ同期")
                        }
                        .actionButtonStyle(.kachaAccent)
                    }
                    .disabled(isSyncingICal || (home.airbnbICalURL.isEmpty && home.jalanICalURL.isEmpty))
                    Button { showICalFileImporter = true } label: {
                        HStack { Image(systemName: "doc.badge.plus"); Text("ファイル") }
                            .actionButtonStyle(.kacha)
                    }
                }
                if home.icalLastSync > 0 {
                    Text("最終同期: \(Date(timeIntervalSince1970: home.icalLastSync).formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(16)
        }
    }

    // MARK: Minpaku

    private var minpakuSection: some View {
        KachaCard {
            VStack(spacing: 14) {
                SettingsHeader(icon: "building.2.fill", title: "民泊モード", color: .kachaWarn)
                Toggle(isOn: $minpakuModeEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("民泊として貸し出す").font(.subheadline).foregroundColor(.white)
                        Text("Airbnb・じゃらん連携や泊数管理が使えるようになります")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                .tint(.kacha)
                if minpakuModeEnabled {
                    Divider().background(Color.kachaCardBorder)
                    SettingsTextField(label: "民泊届出番号", placeholder: "例: 東京都渋谷区01234", text: $home.minpakuNumber)
                        .onChange(of: home.minpakuNumber) { _, val in UserDefaults.standard.set(val, forKey: "minpakuNumber") }
                    Divider().background(Color.kachaCardBorder)
                    HStack {
                        Text("今年の使用泊数").font(.subheadline).foregroundColor(.white)
                        Spacer()
                        Stepper("\(home.minpakuNights)泊", value: $home.minpakuNights, in: 0...180)
                            .foregroundColor(.white).tint(.kacha)
                            .onChange(of: home.minpakuNights) { _, val in UserDefaults.standard.set(val, forKey: "minpakuNights") }
                    }
                    HStack {
                        Text("残り利用可能泊数").font(.subheadline).foregroundColor(.secondary)
                        Spacer()
                        Text("\(max(0, 180 - home.minpakuNights))泊")
                            .font(.subheadline).bold().foregroundColor(remainingColor)
                    }
                    Button("年次リセット") {
                        home.minpakuNights = 0
                        UserDefaults.standard.set(0, forKey: "minpakuNights")
                        showAlert(title: "リセット完了", message: "民泊泊数カウンターを0にリセットしました")
                    }
                    .font(.caption).foregroundColor(.kachaDanger)
                }
            }
            .padding(16)
        }
    }

    private var remainingColor: Color {
        let r = 180 - home.minpakuNights
        if r > 54 { return .kachaSuccess }
        if r > 18 { return .kachaWarn }
        return .kachaDanger
    }

    // MARK: Sakutsu

    private var sakutsuSection: some View {
        KachaCard {
            VStack(spacing: 14) {
                SettingsHeader(icon: "yensign.circle.fill", title: "サクッと連携", color: .kachaSuccess)
                Text("売上データをサクッと（確定申告アプリ）に送信できます")
                    .font(.caption).foregroundColor(.secondary)
                Button { sendToSakutsu() } label: {
                    HStack { Image(systemName: "square.and.arrow.up"); Text("売上データを送信") }
                        .actionButtonStyle(.kachaSuccess)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Actions

    private func testSwitchBot() async {
        isFetchingSwitchBot = true
        defer { isFetchingSwitchBot = false }
        do {
            let devices = try await SwitchBotClient.shared.fetchDevices(
                token: home.switchBotToken, secret: home.switchBotSecret)
            showAlert(title: "接続成功", message: "\(devices.count)台のデバイスが見つかりました")
        } catch {
            showAlert(title: "エラー", message: "接続に失敗しました: \(error.localizedDescription)")
        }
    }

    private func testSesame() async {
        isTestingSesame = true
        defer { isTestingSesame = false }
        let uuids = home.sesameDeviceUUIDs.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let uuid = uuids.first else {
            showAlert(title: "エラー", message: "デバイスUUIDを入力してください"); return
        }
        do {
            let status = try await SesameClient.shared.fetchStatus(uuid: uuid, apiKey: home.sesameApiKey)
            let state = status.isLocked ? "施錠" : "解錠"
            showAlert(title: "接続成功", message: "ステータス: \(state) / バッテリー: \(status.batteryLevel)%")
        } catch {
            showAlert(title: "エラー", message: error.localizedDescription)
        }
    }

    private func discoverBridge() async {
        isDiscoveringBridge = true
        defer { isDiscoveringBridge = false }
        if let ip = await HueClient.shared.discoverBridge() {
            home.hueBridgeIP = ip
            UserDefaults.standard.set(ip, forKey: "hueBridgeIP")
            showAlert(title: "ブリッジ発見", message: "IP: \(ip)")
        } else {
            showAlert(title: "未発見", message: "ブリッジが見つかりませんでした。同じWi-Fiに接続されているか確認してください")
        }
    }

    private func registerBridge() async {
        showHueInstructions = true
        isRegisteringBridge = true
        defer { isRegisteringBridge = false }
        do {
            let username = try await HueClient.shared.register(bridgeIP: home.hueBridgeIP)
            home.hueUsername = username
            UserDefaults.standard.set(username, forKey: "hueUsername")
            showHueInstructions = false
            showAlert(title: "ペアリング成功", message: "Hueブリッジと接続しました")
        } catch {
            showAlert(title: "エラー", message: error.localizedDescription)
        }
    }

    private func syncICalFeeds() async {
        isSyncingICal = true
        defer { isSyncingICal = false }
        var imported = 0
        let existingIDs = Set(bookings.map { $0.id })
        let feeds: [(String, String)] = [
            (home.airbnbICalURL, "airbnb"),
            (home.jalanICalURL, "jalan")
        ].filter { !$0.0.isEmpty }
        for (urlString, platform) in feeds {
            guard let url = URL(string: urlString) else { continue }
            if let data = try? await URLSession.shared.data(from: url).0,
               let content = String(data: data, encoding: .utf8) {
                let events = ICalImporter.parse(icsContent: content, platform: platform)
                let newBookings = ICalImporter.importToBookings(events, platform: platform)
                for booking in newBookings where !existingIDs.contains(booking.id) {
                    booking.homeId = home.id
                    modelContext.insert(booking)
                    imported += 1
                }
            }
        }
        home.icalLastSync = Date().timeIntervalSince1970
        showAlert(title: "同期完了", message: "\(imported)件の予約をインポートしました")
    }

    private func syncBeds24() async {
        isSyncingBeds24 = true
        defer { isSyncingBeds24 = false }
        var imported = 0
        let existingExtIDs = Set(bookings.map { $0.externalId })

        // iCal URL経由（APIキー不要）
        if !home.beds24ICalURL.isEmpty, let url = URL(string: home.beds24ICalURL),
           let data = try? await URLSession.shared.data(from: url).0,
           let content = String(data: data, encoding: .utf8) {
            let events = ICalImporter.parse(icsContent: content, platform: "beds24")
            let newBookings = ICalImporter.importToBookings(events, platform: "beds24")
            for booking in newBookings where !existingExtIDs.contains(booking.externalId) {
                booking.homeId = home.id
                modelContext.insert(booking)
                imported += 1
            }
        }

        // API v2経由（より詳細な情報）
        if !home.beds24ApiKey.isEmpty {
            let b24Bookings = (try? await Beds24Client.shared.fetchBookings(apiKey: home.beds24ApiKey)) ?? []
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
            for b24 in b24Bookings {
                let extId = "beds24-\(b24.bookId ?? 0)"
                guard !existingExtIDs.contains(extId) else { continue }
                guard let cin = b24.checkIn.flatMap({ df.date(from: $0) }),
                      let cout = b24.checkOut.flatMap({ df.date(from: $0) }) else { continue }
                let booking = Booking(
                    guestName: b24.guestFullName,
                    guestEmail: b24.guestEmail ?? "",
                    guestPhone: b24.guestPhone ?? "",
                    platform: b24.platformKey,
                    homeId: home.id,
                    externalId: extId,
                    checkIn: cin,
                    checkOut: cout,
                    totalAmount: Int((b24.price ?? 0) * 100),
                    status: b24.status == "-1" ? "cancelled" : "upcoming"
                )
                modelContext.insert(booking)
                imported += 1
            }
        }
        showAlert(title: "同期完了", message: "\(imported)件の予約をインポートしました")
    }

    private func importICalFile(url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            showAlert(title: "エラー", message: "ファイルを読み込めませんでした"); return
        }
        let existingIDs = Set(bookings.map { $0.id })
        let events = ICalImporter.parse(icsContent: content, platform: "other")
        let newBookings = ICalImporter.importToBookings(events, platform: "other")
        var imported = 0
        for booking in newBookings where !existingIDs.contains(booking.id) {
            booking.homeId = home.id
            modelContext.insert(booking)
            imported += 1
        }
        home.icalLastSync = Date().timeIntervalSince1970
        showAlert(title: "インポート完了", message: "\(imported)件の予約をインポートしました")
    }

    private func sendToSakutsu() {
        if let url = URL(string: "sakutsu://import"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            showAlert(title: "サクッとが見つかりません", message: "App Storeからサクッとをインストールしてください")
        }
    }

    private func showAlert(title: String, message: String) {
        alertTitle = title; alertMessage = message; showAlert = true
    }
}

// MARK: - API Guide Row

struct ApiGuideRow: View {
    let label: String
    let urlString: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Link(destination: URL(string: urlString)!) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square").font(.caption)
                    Text(label).font(.caption).underline()
                }
                .foregroundColor(.kachaAccent)
            }
            Text(note).font(.caption2).foregroundColor(.secondary)
        }
    }
}

// MARK: - View Modifiers / Components

private extension View {
    func actionButtonStyle(_ color: Color) -> some View {
        self
            .font(.subheadline).bold()
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Settings Components (shared)

struct SettingsHeader: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundColor(color)
            Text(title).font(.subheadline).bold().foregroundColor(.white)
            Spacer()
        }
    }
}

struct SettingsTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.caption).foregroundColor(.secondary)
                .frame(width: 90, alignment: .leading)
            if isSecure {
                SecureField(placeholder, text: $text)
                    .foregroundColor(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } else {
                TextField(placeholder, text: $text)
                    .foregroundColor(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        }
    }
}

// MARK: - Integration Row

struct IntegrationRow: View {
    let integration: DeviceIntegration
    let onDelete: () -> Void

    private var platform: DevicePlatform? { DevicePlatform.find(integration.platform) }

    var body: some View {
        HStack(spacing: 12) {
            if let p = platform {
                ZStack {
                    Circle()
                        .fill(Color(hex: p.colorHex).opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: p.icon)
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: p.colorHex))
                }
            } else {
                Image(systemName: "cpu").foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(integration.name).font(.subheadline).bold().foregroundColor(.white)
                Text(platform?.name ?? integration.platform).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { integration.isEnabled },
                set: { integration.isEnabled = $0 }
            ))
            .tint(.kacha)
            .labelsHidden()
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("削除", systemImage: "trash")
            }
        }
    }
}
