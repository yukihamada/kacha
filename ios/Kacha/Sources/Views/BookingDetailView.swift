import SwiftUI
import SwiftData

struct BookingDetailView: View {
    @Bindable var booking: Booking
    @Query private var homes: [Home]

    // Resolve the home this booking belongs to for device tokens
    private var home: Home? { homes.first { $0.id == booking.homeId } ?? homes.first }
    private var switchBotToken: String { home?.switchBotToken ?? "" }
    private var switchBotSecret: String { home?.switchBotSecret ?? "" }
    private var hueBridgeIP: String { home?.hueBridgeIP ?? "" }
    private var hueUsername: String { home?.hueUsername ?? "" }

    @State private var isUnlocking = false
    @State private var isLocking = false
    @State private var isLightsOn = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showMessageSheet = false

    private let checklistItems = [
        "タオル交換",
        "シーツ交換",
        "浴室清掃",
        "キッチン清掃",
        "備品補充",
        "ゴミ収集"
    ]

    var body: some View {
        ZStack {
            Color.kachaBg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    guestInfoSection
                    stayInfoSection
                    messageButton
                    autoActionsSection
                    deviceControlSection
                    cleaningSection
                    if booking.status == "active" {
                        checkOutButton
                    }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .navigationTitle(booking.guestName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.kachaBg, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showMessageSheet) {
            GuestMessageView(booking: booking)
        }
        .alert("操作結果", isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Sections

    private var messageButton: some View {
        Button {
            showMessageSheet = true
        } label: {
            HStack {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                Text("メッセージを送る")
                    .bold()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.kachaSuccess.opacity(0.15))
            .foregroundColor(.kachaSuccess)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.kachaSuccess.opacity(0.3), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var guestInfoSection: some View {
        KachaCard {
            VStack(spacing: 12) {
                infoRow(icon: "person.fill", label: "ゲスト", value: booking.guestName)
                if !booking.guestEmail.isEmpty {
                    infoRow(icon: "envelope.fill", label: "メール", value: booking.guestEmail)
                }
                if !booking.guestPhone.isEmpty {
                    infoRow(icon: "phone.fill", label: "電話", value: booking.guestPhone)
                }
                infoRow(icon: "globe", label: "プラットフォーム", value: booking.platformLabel)
                if booking.guestCount > 0 {
                    infoRow(icon: "person.2.fill", label: "人数",
                            value: booking.numChildren > 0
                                ? "大人\(booking.numAdults)名 + 子ども\(booking.numChildren)名（計\(booking.guestCount)名）"
                                : "\(booking.numAdults)名")
                }
                if booking.commission > 0 {
                    infoRow(icon: "yensign.circle", label: "手数料", value: "¥\(booking.commission.formatted())")
                }
                if !booking.guestNotes.isEmpty {
                    infoRow(icon: "text.bubble", label: "ゲストメモ", value: booking.guestNotes)
                }
            }
            .padding(16)
        }
    }

    private var stayInfoSection: some View {
        KachaCard {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("チェックイン")
                            .font(.caption).foregroundColor(.secondary)
                        Text(booking.checkIn.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline).bold().foregroundColor(.white)
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .foregroundColor(.kacha)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("チェックアウト")
                            .font(.caption).foregroundColor(.secondary)
                        Text(booking.checkOut.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline).bold().foregroundColor(.white)
                    }
                }

                Divider().background(Color.kachaCardBorder)

                HStack {
                    Label("\(booking.nights)泊", systemImage: "moon.fill")
                        .font(.subheadline).foregroundColor(.kachaAccent)
                    Spacer()
                    if booking.totalAmount > 0 {
                        Text("¥\(booking.totalAmount.formatted())")
                            .font(.subheadline).bold().foregroundColor(.kacha)
                    }
                }

                if !booking.notes.isEmpty {
                    Divider().background(Color.kachaCardBorder)
                    Text(booking.notes)
                        .font(.caption).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
    }

    private var autoActionsSection: some View {
        KachaCard {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "bolt.fill").foregroundColor(.kacha)
                    Text("自動アクション").font(.subheadline).bold().foregroundColor(.white)
                    Spacer()
                }

                Toggle(isOn: $booking.autoUnlock) {
                    Label("チェックイン時に自動解錠", systemImage: "lock.open.fill")
                        .font(.subheadline).foregroundColor(.white)
                }
                .tint(.kacha)

                Toggle(isOn: $booking.autoLight) {
                    Label("ウェルカムライト自動点灯", systemImage: "lightbulb.fill")
                        .font(.subheadline).foregroundColor(.white)
                }
                .tint(.kacha)
            }
            .padding(16)
        }
    }

    private var deviceControlSection: some View {
        KachaCard {
            VStack(spacing: 14) {
                HStack {
                    Image(systemName: "homekit").foregroundColor(.kachaAccent)
                    Text("デバイス操作").font(.subheadline).bold().foregroundColor(.white)
                    Spacer()
                }

                HStack(spacing: 12) {
                    DeviceControlButton(
                        icon: "lock.open.fill",
                        label: "解錠",
                        color: .kachaUnlocked,
                        isLoading: isUnlocking
                    ) {
                        Task { await performUnlock() }
                    }

                    DeviceControlButton(
                        icon: "lock.fill",
                        label: "施錠",
                        color: .kachaLocked,
                        isLoading: isLocking
                    ) {
                        Task { await performLock() }
                    }

                    DeviceControlButton(
                        icon: "lightbulb.fill",
                        label: "ウェルカム",
                        color: .kacha,
                        isLoading: false
                    ) {
                        Task { await performWelcomeLights() }
                    }

                    DeviceControlButton(
                        icon: "moon.fill",
                        label: "消灯",
                        color: .kachaAccent,
                        isLoading: false
                    ) {
                        Task { await performLightsOff() }
                    }
                }
            }
            .padding(16)
        }
    }

    private var cleaningSection: some View {
        KachaCard {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "sparkles").foregroundColor(.kachaSuccess)
                    Text("清掃チェックリスト").font(.subheadline).bold().foregroundColor(.white)
                    Spacer()
                    if booking.cleaningDone {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.kachaSuccess)
                    }
                }

                VStack(spacing: 8) {
                    ForEach(checklistItems, id: \.self) { item in
                        HStack {
                            Image(systemName: booking.cleaningDone ? "checkmark.square.fill" : "square")
                                .foregroundColor(booking.cleaningDone ? .kachaSuccess : .secondary)
                            Text(item)
                                .font(.subheadline)
                                .foregroundColor(booking.cleaningDone ? .secondary : .white)
                            Spacer()
                        }
                    }
                }

                Button {
                    booking.cleaningDone.toggle()
                } label: {
                    Text(booking.cleaningDone ? "清掃完了を取り消す" : "清掃完了としてマーク")
                        .font(.subheadline).bold()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(booking.cleaningDone ? Color.kachaCard : Color.kachaSuccess)
                        .foregroundColor(booking.cleaningDone ? .secondary : .white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(16)
        }
    }

    private var checkOutButton: some View {
        Button {
            booking.status = "completed"
        } label: {
            HStack {
                Image(systemName: "arrow.left.square.fill")
                Text("チェックアウト処理")
                    .bold()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.kachaAccent)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Helpers

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.kacha)
                .frame(width: 24)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundColor(.white)
            Spacer()
        }
    }

    private func performUnlock() async {
        guard !switchBotToken.isEmpty else {
            alertMessage = "SwitchBotトークンを設定してください"
            showAlert = true
            return
        }
        isUnlocking = true
        defer { isUnlocking = false }
        let locks = SwitchBotClient.shared.devices.filter {
            $0.deviceType.lowercased().contains("lock")
        }
        for device in locks {
            try? await SwitchBotClient.shared.unlock(
                deviceId: device.deviceId, token: switchBotToken, secret: switchBotSecret)
        }
        SoundPlayer.shared.playKacha()
    }

    private func performLock() async {
        guard !switchBotToken.isEmpty else { return }
        isLocking = true
        defer { isLocking = false }
        let locks = SwitchBotClient.shared.devices.filter {
            $0.deviceType.lowercased().contains("lock")
        }
        for device in locks {
            try? await SwitchBotClient.shared.lock(
                deviceId: device.deviceId, token: switchBotToken, secret: switchBotSecret)
        }
    }

    private func performWelcomeLights() async {
        guard !hueBridgeIP.isEmpty else { return }
        try? await HueClient.shared.welcomeScene(bridgeIP: hueBridgeIP, username: hueUsername)
    }

    private func performLightsOff() async {
        guard !hueBridgeIP.isEmpty else { return }
        try? await HueClient.shared.allOff(bridgeIP: hueBridgeIP, username: hueUsername)
    }
}

struct DeviceControlButton: View {
    let icon: String
    let label: String
    let color: Color
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .tint(color)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(color)
                }
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.kachaCard)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.kachaCardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isLoading)
    }
}
