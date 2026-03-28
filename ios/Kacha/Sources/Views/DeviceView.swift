import SwiftUI
import SwiftData

struct DeviceView: View {
    @Query private var devices: [SmartDevice]
    @Environment(\.modelContext) private var context

    @AppStorage("activeHomeId") private var activeHomeId = ""

    @Query private var homes: [Home]

    // Device tokens from activeHome, not global AppStorage
    private var switchBotToken: String { activeHome?.switchBotToken ?? "" }
    private var switchBotSecret: String { activeHome?.switchBotSecret ?? "" }
    private var hueBridgeIP: String { activeHome?.hueBridgeIP ?? "" }
    private var hueUsername: String { activeHome?.hueUsername ?? "" }
    @StateObject private var hue = HueClient.shared
    @StateObject private var switchBot = SwitchBotClient.shared
    @StateObject private var sesame = SesameClient.shared

    private var activeHome: Home? { homes.first { $0.id == activeHomeId } }
    private var sesameUUIDs: [String] {
        (activeHome?.sesameDeviceUUIDs ?? "")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    @State private var isRefreshing = false
    @State private var showScenePicker = false

    private var locks: [SmartDevice] { devices.filter { $0.type == "lock" } }
    private var lights: [SmartDevice] { devices.filter { $0.type == "light" } }
    private var switches: [SmartDevice] { devices.filter { $0.type == "switch" } }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        scenesSection
                                if !sesameUUIDs.isEmpty { sesameSection }
                        if !hue.lights.isEmpty || !hueBridgeIP.isEmpty {
                            hueLightsSection
                        }
                        if !switchBot.devices.isEmpty || !switchBotToken.isEmpty {
                            switchBotSection
                        }
                        if hue.lights.isEmpty && switchBot.devices.isEmpty && sesameUUIDs.isEmpty {
                            setupPromptSection
                        }
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .refreshable {
                    await refreshAll()
                }
            }
            .navigationTitle("デバイス")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.kachaBg, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refreshAll() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.kacha)
                    }
                }
            }
            .task {
                await refreshAll()
            }
        }
    }

    // MARK: - Sections

    private var scenesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "シーン", icon: "theatermasks.fill")

            HStack(spacing: 12) {
                SceneButton(
                    icon: "door.left.hand.open",
                    label: "ウェルカム",
                    subtitle: "解錠 + 明るい照明",
                    color: .kacha
                ) {
                    Task { await applyWelcomeScene() }
                }

                SceneButton(
                    icon: "moon.stars.fill",
                    label: "就寝",
                    subtitle: "暗め暖色",
                    color: .kachaAccent
                ) {
                    Task { await applyNightScene() }
                }

                SceneButton(
                    icon: "moon.zzz.fill",
                    label: "全消灯",
                    subtitle: "施錠 + 消灯",
                    color: .secondary
                ) {
                    Task { await applyAllOffScene() }
                }
            }
        }
    }

    private var hueLightsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Philips Hue", icon: "lightbulb.fill")

            if hue.isLoading {
                ProgressView("読み込み中...")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if hue.lights.isEmpty {
                KachaCard {
                    HStack {
                        Image(systemName: "lightbulb.slash")
                            .foregroundColor(.secondary)
                        Text("ライトが見つかりません")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(16)
                }
            } else {
                ForEach(hue.lights) { light in
                    HueLightCard(light: light, bridgeIP: hueBridgeIP, username: hueUsername)
                }
            }
        }
    }

    private var switchBotSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "SwitchBot", icon: "lock.shield.fill")

            if switchBot.isLoading {
                ProgressView("読み込み中...")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if switchBot.devices.isEmpty {
                KachaCard {
                    HStack {
                        Image(systemName: "wifi.slash")
                            .foregroundColor(.secondary)
                        Text("デバイスが見つかりません")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(16)
                }
            } else {
                ForEach(switchBot.devices) { device in
                    SwitchBotDeviceCard(
                        device: device,
                        token: switchBotToken,
                        secret: switchBotSecret
                    )
                }
            }
        }
    }

    private var sesameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Sesame", icon: "key.fill")
            if sesame.isLoading {
                ProgressView("読み込み中...").foregroundColor(.secondary).frame(maxWidth: .infinity).padding()
            } else {
                ForEach(sesameUUIDs, id: \.self) { uuid in
                    SesameDeviceCard(
                        uuid: uuid,
                        status: sesame.statuses[uuid],
                        apiKey: activeHome?.sesameApiKey ?? ""
                    )
                }
            }
        }
    }

    private var setupPromptSection: some View {
        KachaCard {
            VStack(spacing: 12) {
                Image(systemName: "homekit")
                    .font(.system(size: 48))
                    .foregroundColor(.kacha.opacity(0.5))
                Text("デバイスが未設定です")
                    .font(.subheadline).bold()
                    .foregroundColor(.white)
                Text("設定タブからSwitchBot APIキーまたはPhilips HueブリッジIPを設定してください")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Actions

    private func refreshAll() async {
        isRefreshing = true
        defer { isRefreshing = false }

        if !switchBotToken.isEmpty {
            try? await SwitchBotClient.shared.fetchDevices(
                token: switchBotToken, secret: switchBotSecret)
        }
        if !hueBridgeIP.isEmpty && !hueUsername.isEmpty {
            _ = try? await HueClient.shared.fetchLights(
                bridgeIP: hueBridgeIP, username: hueUsername)
        }
        if let home = activeHome, !sesameUUIDs.isEmpty {
            await SesameClient.shared.fetchAll(uuids: sesameUUIDs, apiKey: home.sesameApiKey)
        }
    }

    private func applyWelcomeScene() async {
        if !switchBotToken.isEmpty {
            let locks = switchBot.devices.filter { $0.deviceType.lowercased().contains("lock") }
            for device in locks {
                try? await SwitchBotClient.shared.unlock(
                    deviceId: device.deviceId, token: switchBotToken, secret: switchBotSecret)
            }
        }
        if !hueBridgeIP.isEmpty {
            try? await HueClient.shared.welcomeScene(bridgeIP: hueBridgeIP, username: hueUsername)
        }
        SoundPlayer.shared.playKacha()
    }

    private func applyNightScene() async {
        if !hueBridgeIP.isEmpty {
            try? await HueClient.shared.nightScene(bridgeIP: hueBridgeIP, username: hueUsername)
        }
    }

    private func applyAllOffScene() async {
        if !switchBotToken.isEmpty {
            let locks = switchBot.devices.filter { $0.deviceType.lowercased().contains("lock") }
            for device in locks {
                try? await SwitchBotClient.shared.lock(
                    deviceId: device.deviceId, token: switchBotToken, secret: switchBotSecret)
            }
        }
        if !hueBridgeIP.isEmpty {
            try? await HueClient.shared.allOff(bridgeIP: hueBridgeIP, username: hueUsername)
        }
    }
}

// MARK: - Scene Button

struct SceneButton: View {
    let icon: String
    let label: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(label)
                    .font(.subheadline).bold()
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.kachaCard)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

// MARK: - Hue Light Card

struct HueLightCard: View {
    let light: HueClient.HueLight
    let bridgeIP: String
    let username: String

    @State private var isOn: Bool
    @State private var brightness: Double
    @State private var isUpdating = false

    init(light: HueClient.HueLight, bridgeIP: String, username: String) {
        self.light = light
        self.bridgeIP = bridgeIP
        self.username = username
        _isOn = State(initialValue: light.on)
        _brightness = State(initialValue: Double(light.brightnessPercent))
    }

    var body: some View {
        KachaCard {
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: isOn ? "lightbulb.fill" : "lightbulb")
                        .foregroundColor(isOn ? .kacha : .secondary)
                    Text(light.name)
                        .font(.subheadline).bold()
                        .foregroundColor(.white)
                    Spacer()
                    Toggle("", isOn: $isOn)
                        .tint(.kacha)
                        .labelsHidden()
                        .onChange(of: isOn) { _, newValue in
                            Task { await setOn(newValue) }
                        }
                }

                if isOn {
                    HStack(spacing: 8) {
                        Image(systemName: "sun.min.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Slider(value: $brightness, in: 0...100, step: 1) { editing in
                            if !editing { Task { await setBrightness() } }
                        }
                        .tint(.kacha)
                        Image(systemName: "sun.max.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(Int(brightness))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 36)
                    }
                }
            }
            .padding(14)
        }
    }

    private func setOn(_ on: Bool) async {
        guard !bridgeIP.isEmpty else { return }
        try? await HueClient.shared.setState(lightId: light.id, on: on,
                                              bridgeIP: bridgeIP, username: username)
    }

    private func setBrightness() async {
        guard !bridgeIP.isEmpty, isOn else { return }
        let bri = max(1, min(254, Int(brightness / 100.0 * 254)))
        try? await HueClient.shared.setState(lightId: light.id, bri: bri,
                                              bridgeIP: bridgeIP, username: username)
    }
}

// MARK: - SwitchBot Device Card

struct SwitchBotDeviceCard: View {
    let device: SwitchBotClient.SwitchBotDevice
    let token: String
    let secret: String

    @State private var isLocked = true
    @State private var isLoading = false

    private var isLock: Bool {
        device.deviceType.lowercased().contains("lock")
    }

    var body: some View {
        KachaCard {
            HStack {
                Image(systemName: isLock ? "lock.fill" : "power")
                    .font(.title3)
                    .foregroundColor(isLock ? (isLocked ? .kachaLocked : .kachaUnlocked) : .kachaAccent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.deviceName)
                        .font(.subheadline).bold()
                        .foregroundColor(.white)
                    Text(device.deviceType)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isLock {
                    Button {
                        Task { await toggleLock() }
                    } label: {
                        if isLoading {
                            ProgressView().tint(.kacha)
                        } else {
                            Text(isLocked ? "解錠" : "施錠")
                                .font(.subheadline).bold()
                                .foregroundColor(isLocked ? .kachaUnlocked : .kachaLocked)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background((isLocked ? Color.kachaUnlocked : Color.kachaLocked).opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    .disabled(isLoading)
                } else {
                    HStack(spacing: 8) {
                        Button("ON") {
                            Task { await turnOn() }
                        }
                        .font(.caption).bold()
                        .foregroundColor(.kachaSuccess)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.kachaSuccess.opacity(0.15))
                        .clipShape(Capsule())

                        Button("OFF") {
                            Task { await turnOff() }
                        }
                        .font(.caption).bold()
                        .foregroundColor(.kachaDanger)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.kachaDanger.opacity(0.15))
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(14)
        }
    }

    private func toggleLock() async {
        isLoading = true
        defer { isLoading = false }
        if isLocked {
            try? await SwitchBotClient.shared.unlock(
                deviceId: device.deviceId, token: token, secret: secret)
            isLocked = false
            SoundPlayer.shared.playKacha()
        } else {
            try? await SwitchBotClient.shared.lock(
                deviceId: device.deviceId, token: token, secret: secret)
            isLocked = true
        }
    }

    private func turnOn() async {
        try? await SwitchBotClient.shared.turnOn(
            deviceId: device.deviceId, token: token, secret: secret)
    }

    private func turnOff() async {
        try? await SwitchBotClient.shared.turnOff(
            deviceId: device.deviceId, token: token, secret: secret)
    }
}

// MARK: - Sesame Device Card

struct SesameDeviceCard: View {
    let uuid: String
    let status: SesameStatus?
    let apiKey: String

    @State private var isLocking = false
    @State private var isUnlocking = false

    private var isLocked: Bool { status?.isLocked ?? true }
    private var battery: Int { status?.batteryLevel ?? 0 }
    private var shortUUID: String { String(uuid.prefix(8)) + "..." }

    var body: some View {
        KachaCard {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill((isLocked ? Color.kachaLocked : Color.kachaUnlocked).opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
                        .foregroundColor(isLocked ? .kachaLocked : .kachaUnlocked)
                        .font(.title3)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Sesame").font(.subheadline).bold().foregroundColor(.white)
                    Text(shortUUID).font(.caption2).foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        Text(isLocked ? "施錠中" : "解錠中")
                            .font(.caption).foregroundColor(isLocked ? .kachaLocked : .kachaUnlocked)
                        if battery > 0 {
                            Text("🔋\(battery)%").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        Task { await doLock() }
                    } label: {
                        if isLocking { ProgressView().tint(.kachaLocked).scaleEffect(0.8) }
                        else {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.kachaLocked)
                                .padding(8)
                                .background(Color.kachaLocked.opacity(0.15))
                                .clipShape(Circle())
                        }
                    }
                    .disabled(isLocking || isUnlocking)

                    Button {
                        Task { await doUnlock() }
                    } label: {
                        if isUnlocking { ProgressView().tint(.kachaUnlocked).scaleEffect(0.8) }
                        else {
                            Image(systemName: "lock.open.fill")
                                .foregroundColor(.kachaUnlocked)
                                .padding(8)
                                .background(Color.kachaUnlocked.opacity(0.15))
                                .clipShape(Circle())
                        }
                    }
                    .disabled(isLocking || isUnlocking)
                }
            }
            .padding(14)
        }
    }

    private func doLock() async {
        isLocking = true; defer { isLocking = false }
        try? await SesameClient.shared.lock(uuid: uuid, apiKey: apiKey)
        SoundPlayer.shared.playKacha()
    }

    private func doUnlock() async {
        isUnlocking = true; defer { isUnlocking = false }
        try? await SesameClient.shared.unlock(uuid: uuid, apiKey: apiKey)
        SoundPlayer.shared.playKacha()
    }
}
