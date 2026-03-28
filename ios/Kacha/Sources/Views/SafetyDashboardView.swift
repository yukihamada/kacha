import SwiftUI

// MARK: - SafetyDashboardView
// KAGI安否確認ダッシュボードのメイン画面
// family_tokenが未設定の場合はセットアップ画面を表示する

struct SafetyDashboardView: View {
    @StateObject var service = KAGIService()
    @StateObject var bleManager = KAGIBLEManager()

    /// 家族グループトークン (UserDefaultsに永続化)
    @State var familyToken: String = UserDefaults.standard.string(forKey: "kagi_family_token") ?? ""

    /// セットアップシートの表示制御
    @State var showSetup = false

    /// BLE接続シートの表示制御
    @State var showBLESheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景色 (既存アプリに合わせてダークテーマ)
                Color.kachaBg.ignoresSafeArea()

                if familyToken.isEmpty {
                    // 初回: セットアップ案内
                    KAGIWelcomeView(showSetup: $showSetup)
                } else {
                    // メインダッシュボード
                    dashboardContent
                }
            }
            .navigationTitle("IKI 安否確認")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if !familyToken.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button(action: { showSetup = true }) {
                                Label("設定を変更", systemImage: "gearshape")
                            }
                            Button(action: {
                                Task { try? await service.fetchStatus(familyToken: familyToken) }
                            }) {
                                Label("今すぐ更新", systemImage: "arrow.clockwise")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundColor(.kacha)
                        }
                    }
                }
            }
            .sheet(isPresented: $showSetup) {
                KAGISetupView(familyToken: $familyToken, onComplete: { newToken in
                    familyToken = newToken
                    UserDefaults.standard.set(newToken, forKey: "kagi_family_token")
                    service.startPolling(familyToken: newToken)
                })
            }
            .sheet(isPresented: $showBLESheet) {
                KAGIBLEConnectionSheet(bleManager: bleManager)
            }
            .onAppear {
                // 画面表示時にポーリング開始
                if !familyToken.isEmpty {
                    service.startPolling(familyToken: familyToken)
                }
            }
            .onDisappear {
                // 画面離脱時にポーリング停止 (バッテリー節約)
                service.stopPolling()
            }
        }
    }

    // MARK: - Dashboard Content

    @ViewBuilder
    private var dashboardContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                // メインデバイス表示 (最初のデバイスを大きく表示)
                if let device = service.devices.first {
                    StatusCircleView(device: device)
                        .padding(.top, 8)

                    // 連続安否確認ストリーク
                    streakCard(days: device.streakDays)

                    // 生体情報カード (spo2/心拍がある場合)
                    if device.spo2 != nil || device.heartRate != nil {
                        vitalSignsCard(device: device)
                    }

                    // イベントタイムライン
                    if !device.recentEvents.isEmpty {
                        EventTimelineView(events: device.recentEvents)
                    }
                } else if service.isLoading {
                    // ローディング表示
                    loadingView
                } else {
                    // データなし表示
                    emptyStateView
                }

                // エラー表示
                if let error = service.errorMessage {
                    errorBanner(message: error)
                }

                // BLEローカル接続ボタン (Wi-Fiオフライン時の代替手段)
                bleConnectionButton

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Streak Card

    private func streakCard(days: Int) -> some View {
        KachaCard {
            HStack(spacing: 16) {
                // 炎アイコン (連続日数を視覚的に表現)
                ZStack {
                    Circle()
                        .fill(Color.kacha.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: days > 0 ? "flame.fill" : "flame")
                        .font(.system(size: 22))
                        .foregroundColor(.kacha)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("連続安否確認")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    Text("\(days)日継続中")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }

                Spacer()

                // 連続日数の視覚的バー (最大7日分)
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { dayIndex in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(dayIndex < min(days, 7) ? Color.kacha : Color.white.opacity(0.15))
                            .frame(width: 10, height: 24)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Vital Signs Card

    private func vitalSignsCard(device: KAGIDevice) -> some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("生体情報")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 2)

                HStack(spacing: 0) {
                    if let spo2 = device.spo2 {
                        vitalItem(
                            icon: "drop.fill",
                            color: .kachaAccent,
                            value: "\(spo2)%",
                            label: "SpO₂"
                        )
                    }

                    if device.spo2 != nil && device.heartRate != nil {
                        Divider()
                            .background(Color.white.opacity(0.15))
                            .frame(height: 40)
                    }

                    if let hr = device.heartRate {
                        vitalItem(
                            icon: "heart.fill",
                            color: .kachaDanger,
                            value: "\(hr)",
                            label: "bpm"
                        )
                    }
                }
            }
            .padding(16)
        }
    }

    private func vitalItem(icon: String, color: Color, value: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 18))
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - BLE Connection Button

    private var bleConnectionButton: some View {
        Button(action: {
            bleManager.startScan()
            showBLESheet = true
        }) {
            HStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 16))
                Text("Bluetooth経由で接続")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.4))
            }
            .foregroundColor(.white.opacity(0.8))
            .padding(14)
            .background(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .kacha))
                .scaleEffect(1.5)
            Text("安否状況を確認中...")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.3))
            Text("デバイスが見つかりません")
                .font(.headline)
                .foregroundColor(.white.opacity(0.6))
            Text("IKIデバイスが正しく設定されているか確認してください")
                .font(.caption)
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Error Banner

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.kachaDanger)
            Text(message)
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
            Spacer()
        }
        .padding(12)
        .background(Color.kachaDanger.opacity(0.15))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.kachaDanger.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - StatusCircleView
// 大きな円形ステータス表示コンポーネント
// 中央にステータステキスト、外周にACSリング、active/alert時にパルスアニメーション

struct StatusCircleView: View {
    let device: KAGIDevice

    /// パルスアニメーション用状態変数
    @State private var isPulsing = false

    /// ステータスに対応する色
    private var statusColor: Color {
        switch device.status {
        case .active: return .kachaSuccess
        case .quiet:  return .kachaWarn
        case .check:  return .kacha
        case .alert:  return .kachaDanger
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                // 外側パルスリング (active/alertのみ表示)
                if device.status.shouldPulse {
                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 220, height: 220)
                        .scaleEffect(isPulsing ? 1.15 : 1.0)
                        .opacity(isPulsing ? 0.0 : 0.6)
                        .animation(
                            .easeInOut(duration: 1.8).repeatForever(autoreverses: false),
                            value: isPulsing
                        )
                }

                // ACSリング (外周の弧 = acsPct/100)
                ZStack {
                    // 背景リング
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 10)
                        .frame(width: 180, height: 180)

                    // ACS値のリング (12時方向から時計回りに塗る)
                    Circle()
                        .trim(from: 0, to: CGFloat(device.acsPct) / 100)
                        .stroke(
                            statusColor,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .frame(width: 180, height: 180)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.8), value: device.acsPct)

                    // 中央コンテンツ
                    VStack(spacing: 6) {
                        // ステータスアイコン
                        Image(systemName: statusIconName)
                            .font(.system(size: 36, weight: .light))
                            .foregroundColor(statusColor)

                        // メインステータステキスト
                        Text(device.status.label)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        // 最後の活動時刻
                        Text("最後の活動: \(lastSeenLabel)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.55))
                    }
                }
            }
            .onAppear {
                // 初回表示時にパルスアニメーション開始
                if device.status.shouldPulse { isPulsing = true }
            }
            .onChange(of: device.status) { _, newStatus in
                isPulsing = newStatus.shouldPulse
            }

            // ACSスコアテキスト表示
            VStack(spacing: 4) {
                Text("活動信頼度 (ACS)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
                Text("\(device.acsPct)%")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(statusColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    /// ステータスに対応するSF Symbolアイコン名
    private var statusIconName: String {
        switch device.status {
        case .active: return "checkmark.circle.fill"
        case .quiet:  return "moon.fill"
        case .check:  return "questionmark.circle"
        case .alert:  return "exclamationmark.triangle.fill"
        }
    }

    /// 「N分前」形式の最終確認ラベル
    private var lastSeenLabel: String {
        let minutes = device.lastSeenMinutesAgo
        switch minutes {
        case 0:       return "たった今"
        case 1..<60:  return "\(minutes)分前"
        case 60..<1440:
            return "\(minutes / 60)時間前"
        default:
            return "\(minutes / 1440)日前"
        }
    }
}

// MARK: - EventTimelineView
// 安否イベントのタイムライン表示

struct EventTimelineView: View {
    let events: [SafetyEvent]

    var body: some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 0) {
                // セクションヘッダー
                Text("最近のイベント")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                Divider()
                    .background(Color.white.opacity(0.08))

                // イベント一覧 (最大10件表示)
                ForEach(Array(events.prefix(10).enumerated()), id: \.element.id) { index, event in
                    EventRowView(event: event)

                    // 区切り線 (最後の行以外)
                    if index < min(events.count, 10) - 1 {
                        Divider()
                            .background(Color.white.opacity(0.06))
                            .padding(.leading, 56)
                    }
                }
            }
        }
    }
}

// MARK: - EventRowView
// イベント1行の表示

struct EventRowView: View {
    let event: SafetyEvent

    var body: some View {
        HStack(spacing: 12) {
            // イベントアイコン
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: event.icon)
                    .font(.system(size: 14))
                    .foregroundColor(iconColor)
            }

            // イベント説明と時刻
            VStack(alignment: .leading, spacing: 2) {
                Text(event.description)
                    .font(.subheadline)
                    .foregroundColor(.white)
                Text(event.dateLabel)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.45))
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// イベント種別によるアイコン色
    private var iconColor: Color {
        switch event.type {
        case "sos", "fall_detected", "spo2_low", "inactivity_alert":
            return .kachaDanger
        case "motion", "wake":
            return .kachaSuccess
        case "heartbeat":
            return Color(hex: "EF6B6B")  // 薄めの赤
        case "charge_start", "charge_end":
            return .kachaWarn
        default:
            return .kachaAccent
        }
    }
}

// MARK: - KAGIWelcomeView
// family_token未設定時のウェルカム画面

struct KAGIWelcomeView: View {
    @Binding var showSetup: Bool

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // KAGI シールドアイコン
            ZStack {
                Circle()
                    .fill(Color.kachaSuccess.opacity(0.12))
                    .frame(width: 120, height: 120)
                Image(systemName: "shield.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.kachaSuccess)
            }

            VStack(spacing: 12) {
                Text("IKI 安否確認")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("大切な人のKAGIデバイスと連携して\n24時間安否をモニタリングします")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            // 機能一覧カード
            VStack(spacing: 12) {
                featureRow(icon: "checkmark.shield.fill", color: .kachaSuccess, text: "リアルタイム活動モニタリング")
                featureRow(icon: "flame.fill",             color: .kacha,        text: "連続安否確認ストリーク")
                featureRow(icon: "bell.fill",              color: .kachaWarn,    text: "異変時プッシュ通知")
                featureRow(icon: "antenna.radiowaves.left.and.right", color: .kachaAccent, text: "Bluetoothローカル接続対応")
            }
            .padding(20)
            .background(Color.kachaCard)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.kachaCardBorder))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            // セットアップ開始ボタン
            Button(action: { showSetup = true }) {
                Text("セットアップを開始")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.kachaSuccess)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func featureRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
                .frame(width: 28)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.85))
            Spacer()
        }
    }
}

// MARK: - KAGIBLEConnectionSheet
// BLE接続シート (デバイス一覧と接続状態を表示)

struct KAGIBLEConnectionSheet: View {
    @ObservedObject var bleManager: KAGIBLEManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()

                VStack(spacing: 20) {
                    // BLE利用不可時の警告バナー
                    if !bleManager.isBluetoothAvailable {
                        HStack(spacing: 10) {
                            Image(systemName: "bluetooth.slash")
                                .foregroundColor(.kachaDanger)
                            Text(bleManager.bleError ?? "Bluetoothが使用できません")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding()
                        .background(Color.kachaDanger.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }

                    // ローカルステータス表示 (BLE接続済みの場合)
                    if let status = bleManager.localStatus {
                        bleStatusCard(status: status)
                    }

                    // スキャン中表示
                    if bleManager.nearbyDevices.isEmpty && bleManager.isScanning {
                        VStack(spacing: 12) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .kacha))
                            Text("IKIデバイスをスキャン中...")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else if !bleManager.nearbyDevices.isEmpty {
                        // 発見したデバイス一覧
                        List(bleManager.nearbyDevices, id: \.identifier) { peripheral in
                            Button(action: { bleManager.connect(to: peripheral) }) {
                                HStack {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .foregroundColor(.kacha)
                                    Text(peripheral.name ?? "IKI デバイス")
                                        .foregroundColor(.white)
                                    Spacer()
                                    // 接続済みインジケーター
                                    if bleManager.connectedDevice?.identifier == peripheral.identifier {
                                        Text("接続中")
                                            .font(.caption)
                                            .foregroundColor(.kachaSuccess)
                                    }
                                }
                            }
                            .listRowBackground(Color.kachaCard)
                        }
                        .scrollContentBackground(.hidden)
                        .frame(maxHeight: 250)
                    }

                    // スキャン開始/停止ボタン
                    Button(action: {
                        if bleManager.isScanning { bleManager.stopScan() }
                        else { bleManager.startScan() }
                    }) {
                        Label(
                            bleManager.isScanning ? "スキャン停止" : "スキャン開始",
                            systemImage: bleManager.isScanning ? "stop.circle" : "magnifyingglass.circle"
                        )
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(bleManager.isScanning ? Color.kachaDanger : Color.kacha)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal)

                    Spacer()
                }
                .padding(.top, 16)
            }
            .navigationTitle("Bluetooth接続")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .foregroundColor(.kacha)
                }
            }
        }
    }

    /// BLEで取得したローカルステータスカード
    private func bleStatusCard(status: KAGIBLEManager.LocalDeviceStatus) -> some View {
        KachaCard {
            VStack(spacing: 12) {
                HStack {
                    Label("ローカル接続", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.kachaSuccess)
                    Spacer()
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    bleStatusItem(label: "ACS",    value: "\(status.acsPct)%",    icon: "waveform")
                    bleStatusItem(label: "連続日数", value: "\(status.streakDays)日", icon: "flame")
                    bleStatusItem(label: "バッテリー", value: status.batteryLabel, icon: "battery.50percent")
                    bleStatusItem(label: "SpO₂",   value: "\(status.spo2)%",    icon: "drop")
                    bleStatusItem(label: "心拍",    value: "\(status.heartRate)bpm", icon: "heart")
                    bleStatusItem(label: "Wi-Fi",  value: status.wifiConnected ? "接続中" : "未接続", icon: "wifi")
                }
            }
            .padding(16)
        }
        .padding(.horizontal)
    }

    private func bleStatusItem(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.kacha)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
                Text(value)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            Spacer()
        }
    }
}
