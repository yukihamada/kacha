import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CoreLocation

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
    @State private var showTutorial = false
    @State private var showSecurity = false

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
                        helpSection
                        deviceShopSection
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
            .fullScreenCover(isPresented: $showTutorial) { OnboardingView(isReview: true) }
            .sheet(isPresented: $showSecurity) { SecurityInfoView() }
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
                    .font(.system(size: 40)).foregroundColor(.secondary)
                Text("ホームを追加してください").foregroundColor(.secondary)
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
                        .font(.system(size: 48)).foregroundColor(.kacha).padding(.top, 40)
                    TextField("家の名前（例: 渋谷の部屋）", text: $newHomeName)
                        .foregroundColor(.white).padding(14)
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

    // MARK: - Device Shop

    private let shopDevices: [(String, String, String)] = [
        ("SwitchBot ロック Pro", "lock.fill", "https://www.amazon.co.jp/dp/B0CWL6RMPP?tag=yukihamada-22"),
        ("SwitchBot ハブ2", "antenna.radiowaves.left.and.right", "https://www.amazon.co.jp/dp/B0BM8VS13P?tag=yukihamada-22"),
        ("Philips Hue スターターキット", "lightbulb.fill", "https://www.amazon.co.jp/dp/B09MRZ2LPQ?tag=yukihamada-22"),
        ("Sesame 5 Pro", "key.fill", "https://www.amazon.co.jp/dp/B0D4JRLB63?tag=yukihamada-22"),
        ("Nature Remo mini 2", "dot.radiowaves.right", "https://www.amazon.co.jp/dp/B09B2N5MKL?tag=yukihamada-22"),
        ("Nuki Smart Lock 4.0", "lock.rectangle.fill", "https://www.amazon.co.jp/dp/B0CX4YH9VF?tag=yukihamada-22"),
    ]

    private var deviceShopSection: some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "cart.fill").foregroundColor(.kacha)
                    Text("対応デバイスを購入").font(.subheadline).bold().foregroundColor(.white)
                }
                ForEach(shopDevices, id: \.0) { name, icon, url in
                    Link(destination: URL(string: url)!) {
                        HStack(spacing: 10) {
                            Image(systemName: icon).font(.caption).foregroundColor(.kacha).frame(width: 20)
                            Text(name).font(.caption).foregroundColor(.white)
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    if name != shopDevices.last?.0 {
                        Divider().background(Color.kachaCardBorder)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Help

    private var helpSection: some View {
        KachaCard {
            VStack(spacing: 12) {
                SettingsHeader(icon: "questionmark.circle.fill", title: "ヘルプ", color: .kachaAccent)
                Button { showTutorial = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "book.fill").foregroundColor(.kacha).frame(width: 20)
                        Text("チュートリアルを見る").font(.subheadline).foregroundColor(.white)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                    }
                }
                Divider().background(Color.kachaCardBorder)
                Button { showSecurity = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.shield.fill").foregroundColor(.kachaSuccess).frame(width: 20)
                        Text("セキュリティとデータ保護").font(.subheadline).foregroundColor(.white)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Actions

    private func switchHome(_ home: Home) {
        activeHomeId = home.id
        home.syncToAppStorage()
        minpakuModeEnabled = (home.businessType != "none")
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
                Image(systemName: isActive ? "house.fill" : "house").font(.caption)
                Text(home.name).font(.subheadline).fontWeight(isActive ? .bold : .regular)
                if isActive {
                    Image(systemName: "checkmark.circle.fill").font(.caption)
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

    // Expand state for each section
    @State private var expandSwitchBot = false
    @State private var expandHue = false
    @State private var expandSesame = false
    @State private var expandQrio = false
    @State private var expandAutolock = false
    @State private var isFetchingBotDevices = false
    @State private var botDevices: [SwitchBotClient.SwitchBotDevice] = []

    private var integrations: [DeviceIntegration] { allIntegrations.filter { $0.homeId == home.id } }

    var body: some View {
        Group {
            homeInfoSection
            businessModeSection
            if minpakuModeEnabled {
                guestInfoSection
            }
            autolockSetupSection
            devicesOverviewSection
            deviceIntegrationsSection
            if minpakuModeEnabled {
                beds24Section
                icalSection
                automationSection
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

    // MARK: - Home Info

    @State private var wifiSSID: String = ""

    private var homeInfoSection: some View {
        KachaCard {
            VStack(spacing: 14) {
                SettingsHeader(icon: "house.fill", title: "ホーム情報", color: .kacha)
                SettingsTextField(label: "家の名前", placeholder: "例: 我が家", text: $home.name)
                    .onChange(of: home.name) { _, val in UserDefaults.standard.set(val, forKey: "facilityName") }
                Divider().background(Color.kachaCardBorder)
                SettingsTextField(label: "住所", placeholder: "東京都渋谷区...", text: $home.address)
                    .onChange(of: home.address) { _, val in UserDefaults.standard.set(val, forKey: "facilityAddress") }
            }
            .padding(16)
        }
    }

    // MARK: - Auto-lock Setup

    private var autolockSetupSection: some View {
        DeviceStatusCard(
            icon: "building.2.fill",
            name: "オートロック解除",
            color: .kachaAccent,
            isConnected: home.autolockEnabled && !home.autolockBotDeviceId.isEmpty,
            isExpanded: $expandAutolock
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $home.autolockEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("オートロック解除を使う").font(.subheadline).foregroundColor(.white)
                        Text("マンションのエントランス等のオートロックを遠隔で解除します")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
                .tint(.kacha)

                if !home.autolockEnabled {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle").foregroundColor(.secondary)
                        Text("オートロックのないお住まいの方はOFFのままで大丈夫です")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }

                if home.autolockEnabled {
                    Divider().background(Color.kachaCardBorder)

                    // Guide
                    VStack(alignment: .leading, spacing: 8) {
                        Text("セットアップ手順").font(.caption).bold().foregroundColor(.kacha)
                    guideStep(1, "SwitchBot Botを用意",
                              "指ロボットタイプのSwitchBot Bot")
                    guideStep(2, "インターホンの解錠ボタンに貼り付け",
                              "室内のインターホン受話器の「解錠」ボタンにBotのアームが当たるように設置")
                    guideStep(3, "SwitchBotアプリでBot動作を確認",
                              "ボタンモードを「押す」に設定し、解錠ボタンが押されることを確認")
                    guideStep(4, "下のリストからBotを選択",
                              "カチャから遠隔でオートロック解除できるようになります")
                }

                Divider().background(Color.kachaCardBorder)

                // Room number
                SettingsTextField(label: "部屋番号", placeholder: "例: 301", text: $home.autolockRoomNumber)

                Divider().background(Color.kachaCardBorder)

                // Bot device picker
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("インターホン用Bot").font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Button {
                            Task { await fetchBotDevices() }
                        } label: {
                            HStack(spacing: 4) {
                                if isFetchingBotDevices { ProgressView().tint(.kachaAccent) }
                                else { Image(systemName: "arrow.clockwise") }
                                Text("取得").font(.caption)
                            }
                            .foregroundColor(.kachaAccent)
                        }
                        .disabled(isFetchingBotDevices || home.switchBotToken.isEmpty)
                    }

                    if home.switchBotToken.isEmpty {
                        Text("先にSwitchBotのAPIトークンを設定してください")
                            .font(.caption2).foregroundColor(.kachaWarn)
                    } else if botDevices.isEmpty && !isFetchingBotDevices {
                        Text("「取得」をタップしてBotデバイスを検索")
                            .font(.caption2).foregroundColor(.secondary)
                    }

                    ForEach(botDevices, id: \.deviceId) { device in
                        Button {
                            home.autolockBotDeviceId = device.deviceId
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: home.autolockBotDeviceId == device.deviceId
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(home.autolockBotDeviceId == device.deviceId
                                                     ? .kachaSuccess : .secondary)
                                Text(device.deviceName).font(.subheadline).foregroundColor(.white)
                                Spacer()
                                Text(device.deviceType).font(.caption2).foregroundColor(.secondary)
                            }
                            .padding(10)
                            .background(home.autolockBotDeviceId == device.deviceId
                                        ? Color.kachaSuccess.opacity(0.08) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    if !home.autolockBotDeviceId.isEmpty {
                        Divider().background(Color.kachaCardBorder)
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill").foregroundColor(.kachaSuccess)
                            Text("設定完了 — ホーム画面に「オートロック解除」ボタンが表示されます")
                                .font(.caption).foregroundColor(.kachaSuccess)
                        }
                    }
                }

                // Amazon link
                Link(destination: URL(string: "https://www.amazon.co.jp/dp/B09B2KJ7WJ?tag=yukihamada-22")!) {
                    HStack(spacing: 8) {
                        Image(systemName: "cart.fill").font(.caption)
                        Text("SwitchBot Botを購入").font(.caption).bold()
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption2)
                    }
                    .foregroundColor(.kacha)
                    .padding(10)
                    .background(Color.kacha.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Divider().background(Color.kachaCardBorder)

                // Geofence
                geofenceSection
                } // end if autolockEnabled
            }
        }
    }

    private func guideStep(_ num: Int, _ title: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(num)")
                .font(.caption2).bold().foregroundColor(.black)
                .frame(width: 20, height: 20)
                .background(Color.kacha)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).bold().foregroundColor(.white)
                Text(desc).font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    @ObservedObject private var geofence = GeofenceManager.shared
    @State private var isGeocoding = false
    @State private var showManualCoords = false

    private var geofenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "location.circle.fill").foregroundColor(.kachaSuccess)
                Text("近づいたら通知").font(.caption).bold().foregroundColor(.white)
            }
            Text("設定した場所に近づくとオートロック解除の通知が届きます")
                .font(.caption2).foregroundColor(.secondary)

            Toggle(isOn: $home.geofenceEnabled) {
                Text("ジオフェンス通知").font(.subheadline).foregroundColor(.white)
            }
            .tint(.kacha)
            .onChange(of: home.geofenceEnabled) { _, enabled in
                if enabled {
                    GeofenceManager.shared.requestPermission()
                    if home.latitude != 0 {
                        GeofenceManager.shared.registerGeofence(
                            homeId: home.id, latitude: home.latitude,
                            longitude: home.longitude, radius: home.geofenceRadius
                        )
                    } else if !home.address.isEmpty {
                        Task { await geocodeAndRegister() }
                    }
                } else {
                    GeofenceManager.shared.removeGeofence(homeId: home.id)
                }
            }

            if home.geofenceEnabled {
                // Location setting
                VStack(alignment: .leading, spacing: 8) {
                    Text("通知する場所").font(.caption).bold().foregroundColor(.white)

                    // Option 1: From address
                    Button {
                        Task { await geocodeAndRegister() }
                    } label: {
                        HStack(spacing: 6) {
                            if isGeocoding { ProgressView().tint(.kachaAccent) }
                            else { Image(systemName: "location.magnifyingglass") }
                            Text("住所から設定").font(.caption)
                        }
                        .foregroundColor(.kachaAccent)
                    }
                    .disabled(isGeocoding || home.address.isEmpty)

                    // Option 2: Current location
                    Button {
                        Task { await useCurrentLocation() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "location.fill")
                            Text("現在地を使う").font(.caption)
                        }
                        .foregroundColor(.kachaAccent)
                    }

                    // Option 3: Manual input
                    @State var showManualInput = false
                    DisclosureGroup("座標を手入力", isExpanded: $showManualCoords) {
                        HStack(spacing: 8) {
                            TextField("緯度", value: $home.latitude, format: .number)
                                .foregroundColor(.white).font(.caption)
                                .keyboardType(.decimalPad)
                                .padding(8).background(Color.kachaCard)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            TextField("経度", value: $home.longitude, format: .number)
                                .foregroundColor(.white).font(.caption)
                                .keyboardType(.decimalPad)
                                .padding(8).background(Color.kachaCard)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Button("この座標で登録") {
                            if home.latitude != 0 && home.longitude != 0 {
                                GeofenceManager.shared.registerGeofence(
                                    homeId: home.id, latitude: home.latitude,
                                    longitude: home.longitude, radius: home.geofenceRadius
                                )
                            }
                        }
                        .font(.caption).foregroundColor(.kacha)
                    }
                    .font(.caption).foregroundColor(.secondary)
                }

                if home.latitude != 0 {
                    HStack {
                        Image(systemName: "mappin.circle.fill").foregroundColor(.kachaSuccess).font(.caption)
                        Text("\(String(format: "%.4f", home.latitude)), \(String(format: "%.4f", home.longitude))")
                            .font(.caption2).foregroundColor(.white)
                        Spacer()
                        Button {
                            home.latitude = 0; home.longitude = 0
                            GeofenceManager.shared.removeGeofence(homeId: home.id)
                        } label: {
                            Text("リセット").font(.caption2).foregroundColor(.kachaDanger)
                        }
                    }
                }

                HStack {
                    Text("半径").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { Int(home.geofenceRadius) },
                        set: { home.geofenceRadius = Double($0) }
                    )) {
                        Text("100m").tag(100)
                        Text("200m").tag(200)
                        Text("500m").tag(500)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                .onChange(of: home.geofenceRadius) { _, _ in
                    if home.geofenceEnabled && home.latitude != 0 {
                        GeofenceManager.shared.registerGeofence(
                            homeId: home.id, latitude: home.latitude,
                            longitude: home.longitude, radius: home.geofenceRadius
                        )
                    }
                }

                if let result = geofence.lastGeocodeResult {
                    Text(result).font(.caption2).foregroundColor(.kachaSuccess)
                }

                if geofence.authorizationStatus == .denied || geofence.authorizationStatus == .restricted {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.kachaWarn)
                        Text("位置情報の許可が必要です。設定アプリから許可してください。")
                            .font(.caption2).foregroundColor(.kachaWarn)
                    }
                }
            }
        }
    }

    private func useCurrentLocation() async {
        GeofenceManager.shared.requestPermission()
        let manager = CLLocationManager()
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.requestLocation()
        // Wait briefly for location
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if let location = manager.location {
            home.latitude = location.coordinate.latitude
            home.longitude = location.coordinate.longitude
            GeofenceManager.shared.registerGeofence(
                homeId: home.id, latitude: home.latitude,
                longitude: home.longitude, radius: home.geofenceRadius
            )
        }
    }

    private func geocodeAndRegister() async {
        isGeocoding = true
        defer { isGeocoding = false }
        guard let coord = await GeofenceManager.shared.geocodeAddress(home.address) else { return }
        home.latitude = coord.latitude
        home.longitude = coord.longitude
        GeofenceManager.shared.registerGeofence(
            homeId: home.id, latitude: home.latitude,
            longitude: home.longitude, radius: home.geofenceRadius
        )
    }

    private func fetchBotDevices() async {
        isFetchingBotDevices = true
        defer { isFetchingBotDevices = false }
        guard let devices = try? await SwitchBotClient.shared.fetchDevices(
            token: home.switchBotToken, secret: home.switchBotSecret
        ) else { return }
        // Filter to Bot type devices
        botDevices = devices.filter {
            $0.deviceType.lowercased().contains("bot")
        }
        // If no bots, show all devices as fallback
        if botDevices.isEmpty {
            botDevices = devices
        }
    }

    // MARK: - Devices Overview (status cards, no raw keys)

    private var devicesOverviewSection: some View {
        VStack(spacing: 12) {
            // SwitchBot
            DeviceStatusCard(
                icon: "lock.shield.fill",
                name: "SwitchBot",
                color: .kachaAccent,
                isConnected: !home.switchBotToken.isEmpty,
                isExpanded: $expandSwitchBot
            ) {
                VStack(spacing: 12) {
                    SecureTokenField(label: "APIトークン", text: $home.switchBotToken)
                        .onChange(of: home.switchBotToken) { _, val in UserDefaults.standard.set(val, forKey: "switchBotToken") }
                    SecureTokenField(label: "シークレット", text: $home.switchBotSecret)
                        .onChange(of: home.switchBotSecret) { _, val in UserDefaults.standard.set(val, forKey: "switchBotSecret") }
                    Button { Task { await testSwitchBot() } } label: {
                        HStack {
                            if isFetchingSwitchBot { ProgressView().tint(.kachaAccent) }
                            else { Image(systemName: "arrow.clockwise") }
                            Text("接続テスト")
                        }
                        .actionButtonStyle(.kachaAccent)
                    }
                    .disabled(isFetchingSwitchBot || home.switchBotToken.isEmpty)
                    ApiGuideRow(
                        label: "APIキーの取得方法",
                        urlString: "https://support.switch-bot.com/hc/ja/articles/12822710195351",
                        note: "SwitchBotアプリ → プロフィール → 開発者向けオプション"
                    )
                }
            }

            // Philips Hue
            DeviceStatusCard(
                icon: "lightbulb.fill",
                name: "Philips Hue",
                color: .kacha,
                isConnected: !home.hueUsername.isEmpty,
                isExpanded: $expandHue
            ) {
                VStack(spacing: 12) {
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
                    if !home.hueBridgeIP.isEmpty {
                        HStack {
                            Text("ブリッジIP").font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Text(home.hueBridgeIP).font(.caption).foregroundColor(.white)
                        }
                    }
                    if showHueInstructions {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill").foregroundColor(.kachaWarn)
                            Text("ブリッジのリンクボタンを押してから「ペアリング」をタップ")
                                .font(.caption).foregroundColor(.kachaWarn)
                        }
                    }
                }
            }

            // Sesame
            DeviceStatusCard(
                icon: "key.fill",
                name: "Sesame",
                color: .kachaSuccess,
                isConnected: !home.sesameApiKey.isEmpty,
                isExpanded: $expandSesame
            ) {
                VStack(spacing: 12) {
                    SecureTokenField(label: "APIキー", text: $home.sesameApiKey)
                    SettingsTextField(label: "UUID", placeholder: "UUIDをカンマ区切り", text: $home.sesameDeviceUUIDs)
                    Button { Task { await testSesame() } } label: {
                        HStack {
                            if isTestingSesame { ProgressView().tint(.kachaSuccess) }
                            else { Image(systemName: "arrow.clockwise") }
                            Text("接続テスト")
                        }
                        .actionButtonStyle(.kachaSuccess)
                    }
                    .disabled(isTestingSesame || home.sesameApiKey.isEmpty || home.sesameDeviceUUIDs.isEmpty)
                    ApiGuideRow(
                        label: "APIキーの取得方法",
                        urlString: "https://partners.candyhouse.co/",
                        note: "パートナーポータルでAPIキー発行 / アプリでUUID確認"
                    )
                }
            }

            // Qrio
            DeviceStatusCard(
                icon: "key.horizontal.fill",
                name: "Qrio Lock",
                color: .kachaAccent,
                isConnected: !home.qrioApiKey.isEmpty,
                isExpanded: $expandQrio
            ) {
                VStack(spacing: 12) {
                    SecureTokenField(label: "APIキー", text: $home.qrioApiKey)
                    SettingsTextField(label: "デバイスID", placeholder: "カンマ区切り", text: $home.qrioDeviceIds)
                    ApiGuideRow(
                        label: "開発者プログラムに申請",
                        urlString: "https://qrio.me/developer/",
                        note: "Q-Hubが必要です"
                    )
                }
            }
        }
    }

    // MARK: Device Integrations

    private var deviceIntegrationsSection: some View {
        KachaCard {
            VStack(spacing: 14) {
                HStack {
                    SettingsHeader(icon: "cpu.fill", title: "その他デバイス", color: .kachaAccent)
                    Spacer()
                    Button { showAddDevice = true } label: {
                        Image(systemName: "plus.circle.fill").foregroundColor(.kachaAccent).font(.title3)
                    }
                }
                if integrations.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.rectangle.on.folder.fill").foregroundColor(.secondary)
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
                }
            }
            .padding(16)
        }
    }

    // MARK: Beds24

    @State private var beds24Properties: [[String: Any]] = []
    @State private var isFetchingBeds24Props = false
    @State private var isConnectingBeds24 = false
    @State private var beds24Error: String?
    @State private var beds24InviteInput = ""
    // showBeds24PropertyModal removed — inline display

    private var beds24Section: some View {
        KachaCard {
            VStack(spacing: 14) {
                HStack {
                    SettingsHeader(icon: "calendar.badge.clock", title: "Beds24", color: Color(hex: "0066CC"))
                    Text("Beta").font(.caption2).bold()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.kachaWarn.opacity(0.2))
                        .foregroundColor(.kachaWarn)
                        .clipShape(Capsule())
                }

                // Setup guide
                VStack(alignment: .leading, spacing: 6) {
                    Text("Invite Codeの取得方法").font(.caption).bold().foregroundColor(.white)
                    VStack(alignment: .leading, spacing: 4) {
                        beds24Step("1", "Beds24にログイン")
                        beds24Step("2", "設定 → API v2 を開く")
                        beds24Step("3", "「Invite Code」を作成（スコープ: bookings, properties）")
                        beds24Step("4", "生成されたコードを下に貼り付け")
                    }
                    Link(destination: URL(string: "https://beds24.com/control3.php?pagetype=apiv2")!) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.right.square").font(.caption)
                            Text("Beds24 API設定ページを開く").font(.caption).bold()
                        }
                        .foregroundColor(Color(hex: "0066CC"))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color(hex: "0066CC").opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle").foregroundColor(.secondary)
                        Text("Invite Codeは1回限り有効です。接続後のリフレッシュトークンは管理者シェア時に自動で共有されます。")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }

                Divider().background(Color.kachaCardBorder)

                if home.beds24ICalURL.isEmpty {
                    // Not connected — show invite code input
                    SecureTokenField(label: "Invite Code", text: $beds24InviteInput)

                    if !beds24InviteInput.isEmpty {
                        Button {
                            Task { await connectBeds24() }
                        } label: {
                            HStack {
                                if isConnectingBeds24 { ProgressView().tint(.white) }
                                else { Image(systemName: "link") }
                                Text("接続する")
                            }
                            .font(.subheadline).bold()
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(Color(hex: "0066CC"))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(isConnectingBeds24)
                    }
                } else {
                    // Connected — show status
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.kachaSuccess)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("接続済み").font(.subheadline).foregroundColor(.kachaSuccess)
                            Text("リフレッシュトークン保持中（この物件専用）")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            home.beds24ICalURL = ""
                            home.beds24ApiKey = ""
                        } label: {
                            Text("切断").font(.caption2).foregroundColor(.kachaDanger)
                        }
                    }
                }

                if let err = beds24Error {
                    Text(err).font(.caption2).foregroundColor(.kachaDanger)
                }

                // Property linking (auto-loaded)
                if !home.beds24ICalURL.isEmpty {
                    Divider().background(Color.kachaCardBorder)
                    HStack {
                        Text("物件の関連付け").font(.caption).bold().foregroundColor(.white)
                        Spacer()
                        if isFetchingBeds24Props {
                            ProgressView().tint(.kachaAccent)
                        }
                    }
                    .onAppear {
                        if beds24Properties.isEmpty {
                            Task { await fetchBeds24Properties() }
                        }
                    }

                    ForEach(0..<beds24Properties.count, id: \.self) { idx in
                        let prop = beds24Properties[idx]
                        let propId = prop["id"] as? Int ?? 0
                        let propName = prop["name"] as? String ?? "物件 \(propId)"
                        let isLinked = home.beds24ApiKey.contains("|\(propId)") || home.beds24ApiKey == "\(propId)"
                        VStack(spacing: 8) {
                            HStack(spacing: 10) {
                                Image(systemName: isLinked ? "checkmark.circle.fill" : "building.2")
                                    .foregroundColor(isLinked ? .kachaSuccess : Color(hex: "0066CC"))
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 6) {
                                        Text(propName).font(.caption).bold().foregroundColor(.white)
                                        if isLinked {
                                            Text("関連付け済み").font(.system(size: 9)).bold()
                                                .padding(.horizontal, 5).padding(.vertical, 1)
                                                .background(Color.kachaSuccess.opacity(0.2))
                                                .foregroundColor(.kachaSuccess)
                                                .clipShape(Capsule())
                                        }
                                    }
                                    Text("ID: \(propId)").font(.caption2).foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            if !isLinked {
                                HStack(spacing: 8) {
                                    Button {
                                        linkBeds24Property(propId: propId, propName: propName, toCurrentHome: true)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "link")
                                            Text("このホームに関連付け")
                                        }
                                        .font(.caption2).bold()
                                        .foregroundColor(Color(hex: "0066CC"))
                                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                                        .background(Color(hex: "0066CC").opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    Button {
                                        linkBeds24Property(propId: propId, propName: propName, toCurrentHome: false)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "plus.circle")
                                            Text("新規ホーム作成")
                                        }
                                        .font(.caption2).bold()
                                        .foregroundColor(.kacha)
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background(Color.kacha.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                            } // end if !isLinked
                        }
                        .padding(10)
                        .background(Color.kachaCard)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.kachaCardBorder))
                    }
                }

                Divider().background(Color.kachaCardBorder)
                Button { Task { await syncBeds24() } } label: {
                    HStack {
                        if isSyncingBeds24 { ProgressView().tint(.kacha) }
                        else { Image(systemName: "arrow.clockwise") }
                        Text("予約を同期")
                    }
                    .actionButtonStyle(.kacha)
                }
                .disabled(isSyncingBeds24 || home.beds24ICalURL.isEmpty)
            }
            .padding(16)
        }
    }

    // MARK: Automation (guest message + cleaner notify)

    @AppStorage("autoGuestMessage") private var autoGuestMessageGlobal = false
    @AppStorage("autoCleanerNotify") private var autoCleanerNotifyGlobal = false

    private var automationSection: some View {
        KachaCard {
            VStack(spacing: 14) {
                SettingsHeader(icon: "bell.badge.fill", title: "自動通知", color: .kacha)

                Toggle(isOn: Binding(
                    get: { UserDefaults.standard.bool(forKey: "autoGuestMessage_\(home.id)") },
                    set: { UserDefaults.standard.set($0, forKey: "autoGuestMessage_\(home.id)") }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ゲスト自動メッセージ").font(.subheadline).foregroundColor(.white)
                        Text("チェックイン前日18時にWiFi/ドアコード案内を通知")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
                .tint(.kacha)

                Divider().background(Color.kachaCardBorder)

                Toggle(isOn: Binding(
                    get: { UserDefaults.standard.bool(forKey: "autoCleanerNotify_\(home.id)") },
                    set: { UserDefaults.standard.set($0, forKey: "autoCleanerNotify_\(home.id)") }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("清掃スタッフ通知").font(.subheadline).foregroundColor(.white)
                        Text("チェックアウト時に清掃依頼を自動通知")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
                .tint(.kacha)

                HStack(spacing: 6) {
                    Image(systemName: "info.circle").foregroundColor(.secondary)
                    Text("どちらもデフォルトOFFです。必要に応じてONにしてください。")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            .padding(16)
        }
    }

    // MARK: iCal

    private var icalSection: some View {
        KachaCard {
            VStack(spacing: 14) {
                SettingsHeader(icon: "calendar.badge.plus", title: "iCal連携", color: .kachaAccent)
                SettingsTextField(label: "Airbnb", placeholder: "https://www.airbnb.com/calendar/ical/...", text: $home.airbnbICalURL)
                    .onChange(of: home.airbnbICalURL) { _, val in UserDefaults.standard.set(val, forKey: "airbnbICalURL") }
                Divider().background(Color.kachaCardBorder)
                SettingsTextField(label: "じゃらん", placeholder: "https://calendar.jalan.net/...", text: $home.jalanICalURL)
                    .onChange(of: home.jalanICalURL) { _, val in UserDefaults.standard.set(val, forKey: "jalanICalURL") }
                Divider().background(Color.kachaCardBorder)
                HStack(spacing: 8) {
                    Button { Task { await syncICalFeeds() } } label: {
                        HStack {
                            if isSyncingICal { ProgressView().tint(.kachaAccent) }
                            else { Image(systemName: "arrow.clockwise") }
                            Text("同期")
                        }
                        .actionButtonStyle(.kachaAccent)
                    }
                    .disabled(isSyncingICal || (home.airbnbICalURL.isEmpty && home.jalanICalURL.isEmpty))
                    Button { showICalFileImporter = true } label: {
                        HStack { Image(systemName: "doc.badge.plus"); Text("ファイル") }
                            .actionButtonStyle(.kacha)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: Minpaku

    // MARK: - Business Mode (top-level toggle)

    private var businessModeSection: some View {
        KachaCard {
            VStack(spacing: 14) {
                SettingsHeader(icon: "building.2.fill", title: "営業モード", color: .kachaWarn)

                // Type picker
                VStack(alignment: .leading, spacing: 8) {
                    ForEach([
                        ("none", "自宅のみ", "宿泊事業を行わない"),
                        ("minpaku", "民泊（住宅宿泊事業）", "年間180日まで、届出番号が必要"),
                        ("ryokan", "旅館業", "日数制限なし、旅館業許可が必要"),
                    ], id: \.0) { key, title, desc in
                        Button {
                            home.businessType = key
                            minpakuModeEnabled = (key != "none")
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: home.businessType == key ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(home.businessType == key ? .kacha : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(title).font(.subheadline).foregroundColor(.white)
                                    Text(desc).font(.caption2).foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(home.businessType == key ? Color.kacha.opacity(0.06) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                if minpakuModeEnabled {
                    Divider().background(Color.kachaCardBorder)
                    SettingsTextField(
                        label: home.businessType == "minpaku" ? "届出番号" : "許可番号",
                        placeholder: home.businessType == "minpaku" ? "M130xxxxx" : "渋保衛xxxx号",
                        text: $home.minpakuNumber
                    )
                    .onChange(of: home.minpakuNumber) { _, val in UserDefaults.standard.set(val, forKey: "minpakuNumber") }

                    if home.businessType == "minpaku" {
                        Divider().background(Color.kachaCardBorder)
                        HStack {
                            Text("使用泊数").font(.subheadline).foregroundColor(.white)
                            Spacer()
                            Stepper("\(home.minpakuNights)泊", value: $home.minpakuNights, in: 0...180)
                                .foregroundColor(.white).tint(.kacha)
                                .onChange(of: home.minpakuNights) { _, val in UserDefaults.standard.set(val, forKey: "minpakuNights") }
                        }
                        HStack {
                            Text("残り").font(.subheadline).foregroundColor(.secondary)
                            Spacer()
                            Text("\(max(0, 180 - home.minpakuNights))泊").font(.subheadline).bold()
                                .foregroundColor(remainingColor)
                        }
                    }

                    Divider().background(Color.kachaCardBorder)

                    // Permit guide button
                    Button { showPermitGuide = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text.fill").foregroundColor(.kachaWarn)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(home.businessType == "minpaku" ? "民泊届出の方法" : "旅館業許可の取り方")
                                    .font(.subheadline).foregroundColor(.white)
                                Text("申請手順をステップで解説")
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(16)
        }
        .sheet(isPresented: $showPermitGuide) {
            PermitGuideView(businessType: home.businessType, home: home)
        }
    }

    @State private var showPermitGuide = false

    private var remainingColor: Color {
        let r = 180 - home.minpakuNights
        if r > 54 { return .kachaSuccess }
        if r > 18 { return .kachaWarn }
        return .kachaDanger
    }

    // MARK: - Guest Info (door code, wifi — only in business mode)

    private var guestInfoSection: some View {
        KachaCard {
            VStack(spacing: 14) {
                SettingsHeader(icon: "person.badge.key.fill", title: "ゲスト情報", color: .kachaSuccess)
                Text("ゲストに共有する情報を設定").font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider().background(Color.kachaCardBorder)
                MaskedField(label: "ドアコード", value: $home.doorCode, icon: "keypad.rectangle.fill")
                    .onChange(of: home.doorCode) { _, val in UserDefaults.standard.set(val, forKey: "facilityDoorCode") }

                Divider().background(Color.kachaCardBorder)
                HStack {
                    MaskedField(label: "Wi-Fiパスワード", value: $home.wifiPassword, icon: "wifi")
                        .onChange(of: home.wifiPassword) { _, val in UserDefaults.standard.set(val, forKey: "facilityWifiPassword") }
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
            showAlertMsg(title: "接続成功", message: "\(devices.count)台のデバイスが見つかりました")
        } catch {
            showAlertMsg(title: "エラー", message: error.localizedDescription)
        }
    }

    private func testSesame() async {
        isTestingSesame = true
        defer { isTestingSesame = false }
        let uuids = home.sesameDeviceUUIDs.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let uuid = uuids.first else {
            showAlertMsg(title: "エラー", message: "UUIDを入力してください"); return
        }
        do {
            let status = try await SesameClient.shared.fetchStatus(uuid: uuid, apiKey: home.sesameApiKey)
            let state = status.isLocked ? "施錠" : "解錠"
            showAlertMsg(title: "接続成功", message: "\(state) / バッテリー: \(status.batteryLevel)%")
        } catch {
            showAlertMsg(title: "エラー", message: error.localizedDescription)
        }
    }

    private func discoverBridge() async {
        isDiscoveringBridge = true
        defer { isDiscoveringBridge = false }
        if let ip = await HueClient.shared.discoverBridge() {
            home.hueBridgeIP = ip
            UserDefaults.standard.set(ip, forKey: "hueBridgeIP")
            showAlertMsg(title: "発見", message: "IP: \(ip)")
        } else {
            showAlertMsg(title: "未発見", message: "同じWi-Fiに接続されているか確認してください")
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
            showAlertMsg(title: "ペアリング成功", message: "Hueブリッジと接続しました")
        } catch {
            showAlertMsg(title: "エラー", message: error.localizedDescription)
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
        showAlertMsg(title: "同期完了", message: "\(imported)件インポート")
    }

    private func beds24Step(_ num: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Text(num).font(.caption2).bold().foregroundColor(.black)
                .frame(width: 18, height: 18)
                .background(Color(hex: "0066CC"))
                .clipShape(Circle())
            Text(text).font(.caption2).foregroundColor(.secondary)
        }
    }

    private func connectBeds24() async {
        isConnectingBeds24 = true
        beds24Error = nil
        do {
            let result = try await Beds24Client.shared.authenticate(inviteCode: beds24InviteInput)
            // Store refreshToken per-home (beds24ICalURL field)
            home.beds24ICalURL = result.refreshToken
            beds24InviteInput = ""
            home.beds24ApiKey = ""
            // Auto-fetch properties inline
            await fetchBeds24Properties()
            showAlertMsg(title: "接続成功", message: beds24Properties.isEmpty ? "Beds24に接続しました" : "Beds24に接続しました。物件を選択してください。")
        } catch {
            beds24Error = error.localizedDescription
        }
        isConnectingBeds24 = false
    }

    private func linkBeds24Property(propId: Int, propName: String, toCurrentHome: Bool) {
        if toCurrentHome {
            home.beds24ApiKey = "\(propId)"
            showAlertMsg(title: "関連付け完了", message: "\(propName)を「\(home.name)」に関連付けました")
        } else {
            let newHome = Home(name: propName, sortOrder: 100)
            newHome.address = home.address
            newHome.businessType = home.businessType
            newHome.beds24ApiKey = "\(propId)"
            newHome.beds24ICalURL = home.beds24ICalURL
            modelContext.insert(newHome)
            try? modelContext.save()
            showAlertMsg(title: "ホーム作成", message: "「\(propName)」を新しいホームとして作成しました")
        }
        // Remove from list
        beds24Properties.removeAll { ($0["id"] as? Int) == propId }
    }

    private func fetchBeds24Properties() async {
        isFetchingBeds24Props = true
        defer { isFetchingBeds24Props = false }
        let refreshToken = home.beds24ICalURL
        guard let token = try? await Beds24Client.shared.getToken(refreshToken: refreshToken) else { return }
        beds24Properties = (try? await Beds24Client.shared.fetchProperties(token: token)) ?? []
    }

    private func syncBeds24() async {
        isSyncingBeds24 = true
        defer { isSyncingBeds24 = false }

        // refreshToken → token → fetch bookings
        let refreshToken = home.beds24ICalURL // repurposed as refreshToken storage
        guard !refreshToken.isEmpty else {
            showAlertMsg(title: "エラー", message: "先にInvite Codeで接続してください")
            return
        }

        do {
            let token = try await Beds24Client.shared.getToken(refreshToken: refreshToken)
            let b24Bookings = try await Beds24Client.shared.fetchBookings(token: token)

            var imported = 0
            let existingExtIDs = Set(bookings.map { $0.externalId })
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
            for b24 in b24Bookings {
                let extId = "beds24-\(b24.effectiveId)"
                guard !existingExtIDs.contains(extId) else { continue }
                guard let cin = b24.arrival.flatMap({ df.date(from: $0) }),
                      let cout = b24.departure.flatMap({ df.date(from: $0) }) else { continue }
                let statusMap = ["cancelled": "cancelled", "request": "upcoming", "new": "upcoming"]
                let booking = Booking(
                    guestName: b24.guestFullName,
                    guestEmail: b24.email ?? "",
                    guestPhone: b24.phone ?? "",
                    platform: b24.platformKey,
                    homeId: home.id,
                    externalId: extId,
                    checkIn: cin, checkOut: cout,
                    totalAmount: Int((b24.price ?? 0) * 100),
                    status: statusMap[b24.status ?? ""] ?? "upcoming"
                )
                modelContext.insert(booking)
                imported += 1
            }
            showAlertMsg(title: "同期完了", message: "\(imported)件インポート")
        } catch {
            showAlertMsg(title: "同期エラー", message: error.localizedDescription)
        }
    }

    private func importICalFile(url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            showAlertMsg(title: "エラー", message: "ファイルを読み込めませんでした"); return
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
        showAlertMsg(title: "完了", message: "\(imported)件インポート")
    }

    private func showAlertMsg(title: String, message: String) {
        alertTitle = title; alertMessage = message; showAlert = true
    }
}

// MARK: - Device Status Card (collapsible, hides keys)

struct DeviceStatusCard<Content: View>: View {
    let icon: String
    let name: String
    let color: Color
    let isConnected: Bool
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content

    var body: some View {
        KachaCard {
            VStack(spacing: 0) {
                // Header — always visible
                Button { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(color.opacity(0.15)).frame(width: 40, height: 40)
                            Image(systemName: icon).font(.system(size: 18)).foregroundColor(color)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).font(.subheadline).bold().foregroundColor(.white)
                            HStack(spacing: 4) {
                                Circle().fill(isConnected ? Color.kachaSuccess : Color.secondary.opacity(0.5))
                                    .frame(width: 6, height: 6)
                                Text(isConnected ? "接続済み" : "未設定")
                                    .font(.caption).foregroundColor(isConnected ? .kachaSuccess : .secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundColor(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .padding(16)
                }

                // Expandable content
                if isExpanded {
                    Divider().background(Color.kachaCardBorder)
                    VStack(spacing: 12) {
                        content
                    }
                    .padding(16)
                }
            }
        }
    }
}

// MARK: - Masked Field (shows dots, tap to reveal)

struct MaskedField: View {
    let label: String
    @Binding var value: String
    let icon: String
    @State private var isEditing = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.caption).foregroundColor(.kacha).frame(width: 20)
            Text(label).font(.caption).foregroundColor(.secondary).frame(width: 70, alignment: .leading)
            if isEditing {
                TextField(label, text: $value)
                    .foregroundColor(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button { isEditing = false } label: {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.kachaSuccess)
                }
            } else {
                Text(value.isEmpty ? "未設定" : String(repeating: "•", count: min(value.count, 12)))
                    .font(.subheadline)
                    .foregroundColor(value.isEmpty ? .secondary : .white)
                Spacer()
                Button { isEditing = true } label: {
                    Image(systemName: "pencil.circle").foregroundColor(.kacha)
                }
            }
        }
    }
}

// MARK: - Secure Token Field (always masked, paste-friendly)

struct SecureTokenField: View {
    let label: String
    @Binding var text: String
    @State private var isEditing = false

    var body: some View {
        HStack {
            Text(label).font(.caption).foregroundColor(.secondary).frame(width: 90, alignment: .leading)
            if isEditing {
                SecureField("貼り付けてください", text: $text)
                    .foregroundColor(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button { isEditing = false } label: {
                    Text("完了").font(.caption).foregroundColor(.kacha)
                }
            } else if text.isEmpty {
                Text("未設定").font(.subheadline).foregroundColor(.secondary)
                Spacer()
                Button { isEditing = true } label: {
                    Text("設定する").font(.caption).bold().foregroundColor(.kacha)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.kacha.opacity(0.12))
                        .clipShape(Capsule())
                }
            } else {
                Text("•••••••••").font(.subheadline).foregroundColor(.white)
                Spacer()
                Button { isEditing = true } label: {
                    Text("変更").font(.caption).foregroundColor(.secondary)
                }
            }
        }
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
            Text(label).font(.caption).foregroundColor(.secondary).frame(width: 90, alignment: .leading)
            if isSecure {
                SecureField(placeholder, text: $text)
                    .foregroundColor(.white).autocorrectionDisabled().textInputAutocapitalization(.never)
            } else {
                TextField(placeholder, text: $text)
                    .foregroundColor(.white).autocorrectionDisabled().textInputAutocapitalization(.never)
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
                    Circle().fill(Color(hex: p.colorHex).opacity(0.15)).frame(width: 36, height: 36)
                    Image(systemName: p.icon).font(.system(size: 16)).foregroundColor(Color(hex: p.colorHex))
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
            .tint(.kacha).labelsHidden()
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) { Label("削除", systemImage: "trash") }
        }
    }
}
