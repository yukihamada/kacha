import SwiftUI
import SwiftData
import WidgetKit

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query private var bookings: [Booking]
    @Query private var homes: [Home]

    @AppStorage("facilityName") private var facilityName = "私の家"
    @AppStorage("switchBotToken") private var switchBotToken = ""
    @AppStorage("switchBotSecret") private var switchBotSecret = ""
    @AppStorage("hueBridgeIP") private var hueBridgeIP = ""
    @AppStorage("hueUsername") private var hueUsername = ""
    @AppStorage("minpakuNights") private var minpakuNights = 0
    @AppStorage("minpakuModeEnabled") private var minpakuModeEnabled = false
    @AppStorage("activeHomeId") private var activeHomeId = ""

    @StateObject private var switchBot = SwitchBotClient.shared
    @StateObject private var hue = HueClient.shared
    @StateObject private var sesame = SesameClient.shared
    @Query private var allIntegrations: [DeviceIntegration]

    @State private var showCelebration = false
    @State private var celebrationBookingName = ""
    @State private var showShare = false
    @State private var showKeyRotation = false
    @State private var showGuestCard = false
    @State private var showChecklist = false
    @State private var showUtility = false
    @State private var showMaintenance = false
    @State private var showActivityLog = false
    @State private var showHouseManual = false
    @State private var showRevenueReport = false
    @State private var isPressingAutolock = false
    @State private var autolockSuccess = false
    @State private var isRunningScene = false

    private var activeHome: Home? { homes.first { $0.id == activeHomeId } }

    private var sesameUUIDs: [String] {
        (activeHome?.sesameDeviceUUIDs ?? "")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var activeIntegrations: [DeviceIntegration] {
        allIntegrations.filter { $0.homeId == activeHomeId && $0.isEnabled }
    }

    private var todayCheckIns: [Booking] {
        bookings.filter { Calendar.current.isDateInToday($0.checkIn) && $0.status == "upcoming" }
    }
    private var activeBookings: [Booking] {
        bookings.filter { $0.status == "active" }
    }
    private var monthlyRevenue: Int {
        let cal = Calendar.current; let now = Date()
        return bookings.filter {
            cal.isDate($0.checkIn, equalTo: now, toGranularity: .month)
            && ($0.status == "active" || $0.status == "completed")
        }.reduce(0) { $0 + $1.totalAmount }
    }
    private var remainingNights: Int { max(0, 180 - minpakuNights) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        headerSection
                        if activeHome?.autolockEnabled == true && !(activeHome?.autolockBotDeviceId ?? "").isEmpty {
                            autolockSection
                        }
                        quickActionsGrid
                        if minpakuModeEnabled {
                            statsSection
                            minpakuCounterSection
                        }
                        if minpakuModeEnabled && !todayCheckIns.isEmpty { todayCheckInsSection }
                        if minpakuModeEnabled && !activeBookings.isEmpty { activeBookingsSection }
                        scenesSection
                        devicesSection
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                updateWidgetData()
                Task { await refreshDevices() }
            }
            .onChange(of: bookings.count) { _, _ in updateWidgetData() }
            .overlay {
                if showCelebration {
                    DoorOpenEffect(guestName: celebrationBookingName) { showCelebration = false }
                }
            }
            .sheet(isPresented: $showShare) {
                if let home = activeHome { ShareCalendarView(home: home) }
            }
            .sheet(isPresented: $showKeyRotation) {
                if let home = activeHome { KeyRotationView(home: home) }
            }
            .sheet(isPresented: $showGuestCard) {
                if let home = activeHome { GuestCardView(home: home) }
            }
            .sheet(isPresented: $showChecklist) {
                if let home = activeHome { ChecklistView(home: home) }
            }
            .sheet(isPresented: $showUtility) {
                if let home = activeHome { UtilityView(home: home) }
            }
            .sheet(isPresented: $showMaintenance) {
                if let home = activeHome { MaintenanceView(home: home) }
            }
            .sheet(isPresented: $showActivityLog) {
                if let home = activeHome { ActivityLogView(home: home) }
            }
            .sheet(isPresented: $showHouseManual) {
                if let home = activeHome { HouseManualView(home: home) }
            }
            .sheet(isPresented: $showRevenueReport) {
                if let home = activeHome { RevenueReportView(home: home) }
            }
        }
    }

    // MARK: - Header

    @State private var showHomePicker = false

    private var headerSection: some View {
        HStack {
            Menu {
                // Dashboard
                Button {
                    // Post notification to switch to dashboard page
                    NotificationCenter.default.post(name: .switchToDashboard, object: nil)
                } label: {
                    Label("ダッシュボード", systemImage: "square.grid.2x2.fill")
                }

                Divider()

                // Home list
                ForEach(homes) { home in
                    Button {
                        activeHomeId = home.id
                        home.syncToAppStorage()
                    } label: {
                        Label(home.name, systemImage: home.id == activeHomeId ? "house.fill" : "house")
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(facilityName)
                            .font(.title2).bold().foregroundColor(.white)
                        if homes.count > 1 {
                            Image(systemName: "chevron.down")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Text(minpakuModeEnabled ? "開いた、ウェルカム。" : "おかえりなさい。")
                        .font(.caption).foregroundColor(.kacha)
                }
            }
            Spacer()
            HStack(spacing: 14) {
                Button { showActivityLog = true } label: {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 18))
                        .foregroundColor(.kacha.opacity(0.6))
                }
                Button { showKeyRotation = true } label: {
                    Image(systemName: "key.rotate")
                        .font(.system(size: 20))
                        .foregroundColor(.kacha.opacity(0.7))
                }
                Button { showShare = true } label: {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 22))
                        .foregroundColor(.kacha)
                }
                Image(systemName: "door.left.hand.open")
                    .font(.system(size: 28))
                    .foregroundColor(.kacha.opacity(0.4))
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Auto-lock Unlock

    private var autolockSection: some View {
        Button {
            Task { await pressAutolockBot() }
        } label: {
            KachaCard {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill((autolockSuccess ? Color.kachaSuccess : Color.kachaAccent).opacity(0.15))
                            .frame(width: 50, height: 50)
                        if isPressingAutolock {
                            ProgressView().tint(.kachaAccent)
                        } else {
                            Image(systemName: autolockSuccess ? "checkmark.circle.fill" : "building.2.fill")
                                .font(.system(size: 22))
                                .foregroundColor(autolockSuccess ? .kachaSuccess : .kachaAccent)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(autolockSuccess ? "解錠しました" : "オートロック解除")
                            .font(.subheadline).bold()
                            .foregroundColor(autolockSuccess ? .kachaSuccess : .white)
                        Text("エントランスのオートロックを遠隔解除")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3).foregroundColor(.kachaAccent.opacity(0.5))
                }
                .padding(16)
            }
        }
        .disabled(isPressingAutolock)
    }

    private func pressAutolockBot() async {
        guard let home = activeHome, !home.autolockBotDeviceId.isEmpty else { return }
        isPressingAutolock = true
        autolockSuccess = false
        do {
            // SwitchBot Bot: "press" command simulates button press
            try await SwitchBotClient.shared.sendCommand(
                deviceId: home.autolockBotDeviceId,
                command: "press",
                token: home.switchBotToken,
                secret: home.switchBotSecret
            )
            ActivityLogger.log(
                context: modelContext,
                homeId: home.id,
                action: "unlock",
                detail: "オートロックを遠隔解除",
                deviceName: "SwitchBot Bot (インターホン)"
            )
            withAnimation { autolockSuccess = true }
            SoundPlayer.shared.playKacha()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation { autolockSuccess = false }
            }
        } catch {
            // fail silently
        }
        isPressingAutolock = false
    }

    // MARK: - Quick Actions Grid

    private var quickActionsGrid: some View {
        var actions: [(String, String, Color, () -> Void)] = [
            ("bolt.fill", "光熱費", .kachaWarn, { showUtility = true }),
            ("wrench.and.screwdriver", "家の管理", .kacha, { showMaintenance = true }),
        ]
        if minpakuModeEnabled {
            actions.insert(("wifi", "ゲストカード", .kachaAccent, { showGuestCard = true }), at: 0)
            actions.insert(("checklist", "チェックリスト", .kachaSuccess, { showChecklist = true }), at: 1)
            actions.append(("book.fill", "マニュアル", .kachaAccent, { showHouseManual = true }))
            actions.append(("chart.bar.fill", "収支", .kacha, { showRevenueReport = true }))
        }
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(actions, id: \.1) { icon, label, color, action in
                Button(action: action) {
                    KachaCard {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().fill(color.opacity(0.15)).frame(width: 36, height: 36)
                                Image(systemName: icon).font(.system(size: 16)).foregroundColor(color)
                            }
                            Text(label).font(.caption).bold().foregroundColor(.white)
                            Spacer()
                        }
                        .padding(12)
                    }
                }
            }
        }
    }

    // MARK: - Scenes

    private var scenesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "シーン", icon: "theatermasks.fill")
            HStack(spacing: 10) {
                SceneCard(icon: "figure.walk.arrival", label: "帰宅", subtitle: "解錠＋照明オン", color: .kachaSuccess, loading: isRunningScene) {
                    Task { await runScene(.homecoming) }
                }
                SceneCard(icon: "figure.walk.departure", label: "外出", subtitle: "施錠＋消灯", color: .kachaAccent, loading: isRunningScene) {
                    Task { await runScene(.leaving) }
                }
                SceneCard(icon: "moon.stars.fill", label: "就寝", subtitle: "暗め暖色", color: .kachaWarn, loading: isRunningScene) {
                    Task { await runScene(.sleep) }
                }
                SceneCard(icon: "sun.and.horizon.fill", label: "起床", subtitle: "明るい照明", color: .kacha, loading: isRunningScene) {
                    Task { await runScene(.wakeup) }
                }
            }
        }
    }

    // MARK: - Devices

    private var devicesSection: some View {
        VStack(spacing: 12) {
            // Sesame
            if !sesameUUIDs.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Sesame", icon: "key.fill")
                    ForEach(sesameUUIDs, id: \.self) { uuid in
                        SesameDeviceCard(uuid: uuid, status: sesame.statuses[uuid], apiKey: activeHome?.sesameApiKey ?? "")
                    }
                }
            }
            // SwitchBot Locks
            let locks = switchBot.devices.filter { $0.deviceType.lowercased().contains("lock") }
            if !locks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "SwitchBot ロック", icon: "lock.shield.fill")
                    ForEach(locks) { device in
                        SwitchBotLockCard(device: device, token: switchBotToken, secret: switchBotSecret)
                    }
                }
            }
            // SwitchBot Buttons / Plugs / Bots
            let buttons = switchBot.devices.filter {
                let t = $0.deviceType.lowercased()
                return t.contains("bot") || t.contains("plug") || t.contains("switch") || t.contains("button")
            }
            if !buttons.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "SwitchBot スイッチ", icon: "hand.tap.fill")
                    ForEach(buttons) { device in
                        SwitchBotButtonCard(device: device, token: switchBotToken, secret: switchBotSecret)
                    }
                }
            }
            // Hue lights
            if !hue.lights.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "照明", icon: "lightbulb.fill")
                    ForEach(hue.lights) { light in
                        HueLightCard(light: light, bridgeIP: hueBridgeIP, username: hueUsername)
                    }
                }
            }
            // DeviceIntegration cards
            if !activeIntegrations.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "連携デバイス", icon: "cpu.fill")
                    ForEach(activeIntegrations) { integration in
                        DeviceIntegrationCard(integration: integration)
                    }
                }
            }
            // Nothing configured yet
            if sesameUUIDs.isEmpty && switchBot.devices.isEmpty && hue.lights.isEmpty
               && activeIntegrations.isEmpty
               && switchBotToken.isEmpty && hueBridgeIP.isEmpty {
                KachaCard {
                    HStack(spacing: 12) {
                        Image(systemName: "homekit").font(.title2).foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("デバイス未設定").font(.subheadline).bold().foregroundColor(.white)
                            Text("設定タブからSwitchBot・Sesame・Hue・Nature Remoなどを連携できます")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    // MARK: - Minpaku sections

    private var statsSection: some View {
        HStack(spacing: 12) {
            StatCard(icon: "arrow.right.square.fill", label: "本日チェックイン",
                     value: "\(todayCheckIns.count)件", color: .kachaSuccess)
            StatCard(icon: "arrow.left.square.fill", label: "本日チェックアウト",
                     value: "\(activeBookings.filter { Calendar.current.isDateInToday($0.checkOut) }.count)件", color: .kachaAccent)
            StatCard(icon: "yensign.circle.fill", label: "今月売上",
                     value: "¥\(monthlyRevenue.formatted())", color: .kacha)
        }
    }

    private var minpakuCounterSection: some View {
        KachaCard {
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "calendar.badge.clock").foregroundColor(.kacha)
                    Text("民泊新法カウンター").font(.subheadline).bold().foregroundColor(.white)
                    Spacer()
                    Text("\(minpakuNights) / 180泊").font(.caption).foregroundColor(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.1)).frame(height: 8)
                        RoundedRectangle(cornerRadius: 4).fill(progressColor)
                            .frame(width: geo.size.width * min(1, Double(minpakuNights) / 180.0), height: 8)
                    }
                }
                .frame(height: 8)
                HStack {
                    Text("残り \(remainingNights)泊 利用可能").font(.caption).foregroundColor(progressColor)
                    Spacer()
                    Button("+ 泊数追加") { minpakuNights = min(180, minpakuNights + 1) }
                        .font(.caption).foregroundColor(.kacha)
                }
            }
            .padding(16)
        }
    }

    private var progressColor: Color {
        let r = Double(minpakuNights) / 180.0
        if r < 0.7 { return .kachaSuccess }
        if r < 0.9 { return .kachaWarn }
        return .kachaDanger
    }

    private var todayCheckInsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "本日チェックイン", icon: "person.fill.checkmark")
            ForEach(todayCheckIns) { booking in
                TodayCheckInCard(booking: booking) { checkInGuest(booking) }
            }
        }
    }

    private var activeBookingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "滞在中", icon: "moon.stars.fill")
            ForEach(activeBookings) { booking in ActiveBookingCard(booking: booking) }
        }
    }

    // MARK: - Actions

    enum Scene { case homecoming, leaving, sleep, wakeup }

    @Environment(\.modelContext) private var modelContext

    private func runScene(_ scene: Scene) async {
        isRunningScene = true
        defer { isRunningScene = false }
        let apiKey = activeHome?.sesameApiKey ?? ""
        let homeId = activeHome?.id ?? ""
        let sceneName: String
        switch scene {
        case .homecoming:
            sceneName = "ただいま"
            for uuid in sesameUUIDs { try? await SesameClient.shared.unlock(uuid: uuid, apiKey: apiKey) }
            for d in switchBot.devices.filter({ $0.deviceType.lowercased().contains("lock") }) {
                try? await SwitchBotClient.shared.unlock(deviceId: d.deviceId, token: switchBotToken, secret: switchBotSecret)
            }
            if !hueBridgeIP.isEmpty { try? await HueClient.shared.welcomeScene(bridgeIP: hueBridgeIP, username: hueUsername) }
            SoundPlayer.shared.playKacha()
        case .leaving:
            sceneName = "おでかけ"
            for uuid in sesameUUIDs { try? await SesameClient.shared.lock(uuid: uuid, apiKey: apiKey) }
            for d in switchBot.devices.filter({ $0.deviceType.lowercased().contains("lock") }) {
                try? await SwitchBotClient.shared.lock(deviceId: d.deviceId, token: switchBotToken, secret: switchBotSecret)
            }
            if !hueBridgeIP.isEmpty { try? await HueClient.shared.allOff(bridgeIP: hueBridgeIP, username: hueUsername) }
        case .sleep:
            sceneName = "おやすみ"
            if !hueBridgeIP.isEmpty { try? await HueClient.shared.nightScene(bridgeIP: hueBridgeIP, username: hueUsername) }
        case .wakeup:
            sceneName = "おはよう"
            if !hueBridgeIP.isEmpty { try? await HueClient.shared.welcomeScene(bridgeIP: hueBridgeIP, username: hueUsername) }
        }
        ActivityLogger.log(context: modelContext, homeId: homeId, action: "scene", detail: "「\(sceneName)」シーンを実行")
    }

    private func checkInGuest(_ booking: Booking) {
        booking.status = "active"
        celebrationBookingName = booking.guestName
        showCelebration = true
        SoundPlayer.shared.playKacha()
        Task {
            if booking.autoUnlock && !switchBotToken.isEmpty {
                let locks = switchBot.devices.filter { $0.deviceType.lowercased().contains("lock") }
                for d in locks {
                    try? await SwitchBotClient.shared.unlock(deviceId: d.deviceId, token: switchBotToken, secret: switchBotSecret)
                }
            }
            if booking.autoLight && !hueBridgeIP.isEmpty {
                try? await HueClient.shared.welcomeScene(bridgeIP: hueBridgeIP, username: hueUsername)
            }
        }
    }

    private func refreshDevices() async {
        if !switchBotToken.isEmpty {
            try? await SwitchBotClient.shared.fetchDevices(token: switchBotToken, secret: switchBotSecret)
        }
        if !hueBridgeIP.isEmpty && !hueUsername.isEmpty {
            _ = try? await HueClient.shared.fetchLights(bridgeIP: hueBridgeIP, username: hueUsername)
        }
        if let home = activeHome, !sesameUUIDs.isEmpty {
            await SesameClient.shared.fetchAll(uuids: sesameUUIDs, apiKey: home.sesameApiKey)
        }
    }

    private func updateWidgetData() {
        guard let defaults = UserDefaults(suiteName: "group.com.enablerdao.kacha") else { return }
        defaults.set(todayCheckIns.count, forKey: "widget_today_checkins")
        defaults.set(true, forKey: "widget_is_locked")
        defaults.set(minpakuNights, forKey: "widget_month_nights")
        struct BookingItem: Codable { let guestName: String; let timeLabel: String; let platform: String }
        let tf = DateFormatter(); tf.dateFormat = "HH:mm"
        let items = todayCheckIns.prefix(3).map {
            BookingItem(guestName: $0.guestName, timeLabel: "\(tf.string(from: $0.checkIn)) チェックイン", platform: $0.platformLabel)
        }
        if let encoded = try? JSONEncoder().encode(Array(items)) {
            defaults.set(encoded, forKey: "widget_upcoming_bookings")
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "KachaWidget")
    }
}

// MARK: - Scene Card

struct SceneCard: View {
    let icon: String
    let label: String
    let subtitle: String
    let color: Color
    let loading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                if loading {
                    ProgressView().tint(color).frame(width: 28, height: 28)
                } else {
                    Image(systemName: icon).font(.title2).foregroundColor(color)
                }
                Text(label).font(.subheadline).bold().foregroundColor(.white)
                Text(subtitle).font(.system(size: 9)).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(color.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.25), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(loading)
    }
}

// MARK: - SwitchBot Lock Card (compact)

struct SwitchBotLockCard: View {
    let device: SwitchBotClient.SwitchBotDevice
    let token: String
    let secret: String
    @State private var isLocking = false
    @State private var isUnlocking = false

    var body: some View {
        KachaCard {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill").foregroundColor(.kachaAccent).font(.title3)
                Text(device.deviceName).font(.subheadline).bold().foregroundColor(.white)
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        isLocking = true
                        Task {
                            try? await SwitchBotClient.shared.lock(deviceId: device.deviceId, token: token, secret: secret)
                            isLocking = false
                        }
                    } label: {
                        lockActionLabel("lock.fill", color: .kachaLocked, loading: isLocking)
                    }
                    .disabled(isLocking || isUnlocking)

                    Button {
                        isUnlocking = true
                        Task {
                            try? await SwitchBotClient.shared.unlock(deviceId: device.deviceId, token: token, secret: secret)
                            isUnlocking = false
                            SoundPlayer.shared.playKacha()
                        }
                    } label: {
                        lockActionLabel("lock.open.fill", color: .kachaUnlocked, loading: isUnlocking)
                    }
                    .disabled(isLocking || isUnlocking)
                }
            }
            .padding(14)
        }
    }

    private func lockActionLabel(_ icon: String, color: Color, loading: Bool) -> some View {
        Group {
            if loading { ProgressView().tint(color).scaleEffect(0.8) }
            else { Image(systemName: icon).foregroundColor(color) }
        }
        .frame(width: 32, height: 32)
        .background(color.opacity(0.12))
        .clipShape(Circle())
    }
}

// MARK: - Shared Sub-components

struct StatCard: View {
    let icon: String; let label: String; let value: String; let color: Color
    var body: some View {
        KachaCard {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title3).foregroundColor(color)
                Text(value).font(.subheadline).bold().foregroundColor(.white)
                Text(label).font(.system(size: 10)).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
            .padding(.vertical, 12).frame(maxWidth: .infinity)
        }
    }
}

struct SectionHeader: View {
    let title: String; let icon: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundColor(.kacha).font(.subheadline)
            Text(title).font(.subheadline).bold().foregroundColor(.white)
            Spacer()
        }
    }
}

struct TodayCheckInCard: View {
    let booking: Booking; let onCheckIn: () -> Void
    var body: some View {
        KachaCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(booking.guestName).font(.subheadline).bold().foregroundColor(.white)
                    HStack(spacing: 6) {
                        Text(booking.platformLabel)
                            .font(.caption).padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Color(hex: booking.platformColor).opacity(0.2))
                            .foregroundColor(Color(hex: booking.platformColor)).clipShape(Capsule())
                        Text("\(booking.nights)泊").font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button(action: onCheckIn) {
                    HStack(spacing: 4) {
                        Image(systemName: "door.left.hand.open")
                        Text("チェックイン").font(.caption).bold()
                    }
                    .foregroundColor(.kachaBg).padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.kacha).clipShape(Capsule())
                }
            }
            .padding(14)
        }
    }
}

struct ActiveBookingCard: View {
    let booking: Booking
    var body: some View {
        KachaCard {
            HStack {
                Circle().fill(Color.kachaSuccess).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(booking.guestName).font(.subheadline).bold().foregroundColor(.white)
                    Text("〜 \(booking.checkOut.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Text("滞在中").font(.caption).bold().foregroundColor(.kachaSuccess)
            }
            .padding(14)
        }
    }
}

// MARK: - SwitchBot Button/Bot Card

struct SwitchBotButtonCard: View {
    let device: SwitchBotClient.SwitchBotDevice
    let token: String
    let secret: String
    @State private var isPressing = false
    @State private var isOn = false

    private var isPlug: Bool { device.deviceType.lowercased().contains("plug") }

    var body: some View {
        KachaCard {
            HStack(spacing: 12) {
                Image(systemName: isPlug ? "powerplug.fill" : "hand.tap.fill")
                    .foregroundColor(.kachaWarn).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.deviceName).font(.subheadline).bold().foregroundColor(.white)
                    Text(device.deviceType).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if isPlug {
                    // プラグ: ON/OFF トグル
                    HStack(spacing: 8) {
                        Button {
                            Task {
                                isPressing = true
                                try? await SwitchBotClient.shared.turnOff(deviceId: device.deviceId, token: token, secret: secret)
                                isOn = false; isPressing = false
                            }
                        } label: {
                            Text("OFF").font(.caption).bold()
                                .foregroundColor(isOn ? .secondary : .kachaDanger)
                                .frame(width: 40, height: 30)
                                .background((isOn ? Color.clear : Color.kachaDanger).opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .disabled(isPressing)
                        Button {
                            Task {
                                isPressing = true
                                try? await SwitchBotClient.shared.turnOn(deviceId: device.deviceId, token: token, secret: secret)
                                isOn = true; isPressing = false
                            }
                        } label: {
                            Text("ON").font(.caption).bold()
                                .foregroundColor(isOn ? .kachaSuccess : .secondary)
                                .frame(width: 40, height: 30)
                                .background((isOn ? Color.kachaSuccess : Color.clear).opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .disabled(isPressing)
                    }
                } else {
                    // Bot/スイッチ: プレスボタン
                    Button {
                        isPressing = true
                        Task {
                            try? await SwitchBotClient.shared.sendCommand(
                                deviceId: device.deviceId, command: "press", token: token, secret: secret)
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            isPressing = false
                        }
                    } label: {
                        Group {
                            if isPressing { ProgressView().tint(.kachaWarn).scaleEffect(0.8) }
                            else { Image(systemName: "hand.tap.fill").foregroundColor(.kachaWarn) }
                        }
                        .frame(width: 36, height: 36)
                        .background(Color.kachaWarn.opacity(0.15))
                        .clipShape(Circle())
                    }
                    .disabled(isPressing)
                }
            }
            .padding(14)
        }
    }
}

// MARK: - DeviceIntegration Card

struct DeviceIntegrationCard: View {
    let integration: DeviceIntegration
    @State private var isRunning = false
    @State private var resultMessage: String?

    private var platform: DevicePlatform? { DevicePlatform.find(integration.platform) }

    var body: some View {
        KachaCard {
            HStack(spacing: 12) {
                if let p = platform {
                    ZStack {
                        Circle().fill(Color(hex: p.colorHex).opacity(0.15)).frame(width: 40, height: 40)
                        Image(systemName: p.icon).foregroundColor(Color(hex: p.colorHex)).font(.system(size: 18))
                    }
                } else {
                    Image(systemName: "cpu").foregroundColor(.secondary).font(.title3)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(integration.name).font(.subheadline).bold().foregroundColor(.white)
                    if let msg = resultMessage {
                        Text(msg).font(.caption).foregroundColor(.kachaSuccess)
                    } else {
                        Text(platform?.name ?? integration.platform).font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button {
                    Task {
                        isRunning = true
                        do {
                            try await CustomWebhookClient.execute(integration: integration)
                            resultMessage = "送信完了"
                        } catch {
                            resultMessage = "エラー"
                        }
                        isRunning = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { resultMessage = nil }
                    }
                } label: {
                    Group {
                        if isRunning { ProgressView().tint(Color(hex: platform?.colorHex ?? "6366F1")).scaleEffect(0.8) }
                        else { Image(systemName: "play.fill").foregroundColor(Color(hex: platform?.colorHex ?? "6366F1")) }
                    }
                    .frame(width: 36, height: 36)
                    .background(Color(hex: platform?.colorHex ?? "6366F1").opacity(0.15))
                    .clipShape(Circle())
                }
                .disabled(isRunning)
            }
            .padding(14)
        }
    }
}
