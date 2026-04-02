import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            SafetyDashboardView()
                .tabItem {
                    Label("ダッシュボード", systemImage: "heart.circle.fill")
                }

            DeviceListView()
                .tabItem {
                    Label("デバイス", systemImage: "antenna.radiowaves.left.and.right")
                }

            IKISettingsView()
                .tabItem {
                    Label("設定", systemImage: "gearshape.fill")
                }
        }
        .accentColor(.iki)
        .background(Color.ikiBg)
    }
}

// MARK: - DeviceListView
// デバイス一覧 (BLE接続管理)

struct DeviceListView: View {
    @StateObject var bleManager = IKIBLEManager()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ikiBg.ignoresSafeArea()

                VStack(spacing: 20) {
                    // BLE利用不可時の警告バナー
                    if !bleManager.isBluetoothAvailable {
                        HStack(spacing: 10) {
                            Image(systemName: "bluetooth.slash")
                                .foregroundColor(.ikiDanger)
                            Text(bleManager.bleError ?? "Bluetoothが使用できません")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding()
                        .background(Color.ikiDanger.opacity(0.12))
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
                                .progressViewStyle(CircularProgressViewStyle(tint: .iki))
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
                                        .foregroundColor(.iki)
                                    Text(peripheral.name ?? "IKI デバイス")
                                        .foregroundColor(.white)
                                    Spacer()
                                    if bleManager.connectedDevice?.identifier == peripheral.identifier {
                                        Text("接続中")
                                            .font(.caption)
                                            .foregroundColor(.ikiSuccess)
                                    }
                                }
                            }
                            .listRowBackground(Color.ikiCard)
                        }
                        .scrollContentBackground(.hidden)
                        .frame(maxHeight: 300)
                    } else if !bleManager.isScanning {
                        VStack(spacing: 16) {
                            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                .font(.system(size: 48))
                                .foregroundColor(.white.opacity(0.3))
                            Text("近くのIKIデバイスが見つかりません")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
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
                        .background(bleManager.isScanning ? Color.ikiDanger : Color.iki)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal)

                    Spacer()
                }
                .padding(.top, 16)
            }
            .navigationTitle("デバイス")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    /// BLEで取得したローカルステータスカード
    private func bleStatusCard(status: IKIBLEManager.LocalDeviceStatus) -> some View {
        IKICard {
            VStack(spacing: 12) {
                HStack {
                    Label("ローカル接続", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.ikiSuccess)
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
                .foregroundColor(.iki)
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

// MARK: - Color Extension

extension Color {
    static let ikiBg        = Color(hex: "0A0A12")
    static let iki          = Color(hex: "E8A838")   // IKI amber
    static let ikiAccent    = Color(hex: "3B9FE8")
    static let ikiSuccess   = Color(hex: "10B981")
    static let ikiWarn      = Color(hex: "F59E0B")
    static let ikiDanger    = Color(hex: "EF4444")
    static let ikiCard      = Color(white: 1, opacity: 0.06)
    static let ikiCardBorder = Color(white: 1, opacity: 0.10)

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Shared Card Style

struct IKICard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(Color.ikiCard)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.ikiCardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
