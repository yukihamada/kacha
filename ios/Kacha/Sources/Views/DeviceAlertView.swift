import SwiftUI
import SwiftData

// MARK: - DeviceAlertView
// アクティブなデバイス異常アラート一覧 + アラート履歴

struct DeviceAlertView: View {
    let home: Home

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allAlerts: [DeviceAlert]

    @State private var showHistory = false
    @State private var isRunningCheck = false

    private var activeAlerts: [DeviceAlert] {
        allAlerts
            .filter { $0.homeId == home.id && !$0.isResolved }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var resolvedAlerts: [DeviceAlert] {
        allAlerts
            .filter { $0.homeId == home.id && $0.isResolved }
            .sorted { ($0.resolvedAt ?? $0.createdAt) > ($1.resolvedAt ?? $1.createdAt) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // アクティブアラート
                        if activeAlerts.isEmpty && !showHistory {
                            emptyState
                        } else {
                            if !activeAlerts.isEmpty {
                                alertSection(
                                    title: "アクティブなアラート",
                                    alerts: activeAlerts,
                                    isActive: true
                                )
                            }

                            // 履歴トグル
                            if !resolvedAlerts.isEmpty {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showHistory.toggle()
                                    }
                                } label: {
                                    HStack {
                                        Text("アラート履歴 (\(resolvedAlerts.count)件)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Image(systemName: showHistory ? "chevron.up" : "chevron.down")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 4)
                                }

                                if showHistory {
                                    alertSection(
                                        title: "解決済み",
                                        alerts: resolvedAlerts,
                                        isActive: false
                                    )
                                }
                            }
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("デバイスアラート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                        .foregroundColor(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await runManualCheck() }
                    } label: {
                        if isRunningCheck {
                            ProgressView().tint(.kachaAccent)
                        } else {
                            Label("今すぐチェック", systemImage: "arrow.clockwise")
                                .labelStyle(.iconOnly)
                                .foregroundColor(.kachaAccent)
                        }
                    }
                    .disabled(isRunningCheck)
                    .accessibilityLabel(isRunningCheck ? "チェック中" : "今すぐデバイスをチェック")
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 60)
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 56))
                .foregroundColor(.kachaSuccess)
            Text("異常なし")
                .font(.title3).bold()
                .foregroundColor(.white)
            Text("すべてのデバイスが正常に動作しています。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 40)

            if !resolvedAlerts.isEmpty {
                Button {
                    withAnimation { showHistory = true }
                } label: {
                    Text("解決済みアラートを見る (\(resolvedAlerts.count)件)")
                        .font(.subheadline)
                        .foregroundColor(.kachaAccent)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Alert Section

    @ViewBuilder
    private func alertSection(title: String, alerts: [DeviceAlert], isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            ForEach(alerts) { alert in
                DeviceAlertCard(alert: alert, isActive: isActive) {
                    resolveAlert(alert)
                }
            }
        }
    }

    // MARK: - Actions

    private func resolveAlert(_ alert: DeviceAlert) {
        withAnimation {
            alert.isResolved = true
            alert.resolvedAt = Date()
            try? context.save()
        }
    }

    private func runManualCheck() async {
        isRunningCheck = true
        defer { isRunningCheck = false }
        if let container = try? ModelContainer(
            for: Schema([
                Home.self, Booking.self, SmartDevice.self, DeviceIntegration.self,
                ShareRecord.self, ChecklistItem.self, UtilityRecord.self,
                MaintenanceTask.self, ActivityLog.self, HouseManual.self,
                SecureItem.self, DeviceAlert.self,
            ]),
            configurations: ModelConfiguration()
        ) {
            await DeviceMonitorService.shared.runChecks(container: container)
        }
    }
}

// MARK: - DeviceAlertCard

struct DeviceAlertCard: View {
    let alert: DeviceAlert
    let isActive: Bool
    let onResolve: () -> Void

    @State private var isConfirmingResolve = false

    private var alertType: AlertType? {
        AlertType(rawValue: alert.alertType)
    }

    private var severityColor: Color {
        alert.severity == "critical" ? .kachaDanger : .kachaWarn
    }

    private var severityLabel: String {
        alert.severity == "critical" ? "緊急" : "警告"
    }

    var body: some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 12) {
                // ヘッダー行
                HStack(spacing: 10) {
                    // アイコン
                    ZStack {
                        Circle()
                            .fill(severityColor.opacity(isActive ? 0.2 : 0.08))
                            .frame(width: 42, height: 42)
                        Image(systemName: alertType?.icon ?? "exclamationmark.triangle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(isActive ? severityColor : .secondary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(alertType?.title ?? alert.alertType)
                                .font(.subheadline).bold()
                                .foregroundColor(isActive ? .white : .secondary)

                            // 深刻度バッジ
                            if isActive {
                                Text(severityLabel)
                                    .font(.caption2).bold()
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(severityColor.opacity(0.2))
                                    .foregroundColor(severityColor)
                                    .clipShape(Capsule())
                            }
                        }

                        Text(alert.deviceName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // 解決済みチェックマーク
                    if !isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.kachaSuccess.opacity(0.6))
                    }
                }

                // メッセージ
                Text(alert.message)
                    .font(.caption)
                    .foregroundColor(isActive ? .white.opacity(0.85) : .secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // フッター行
                HStack {
                    Text(alert.createdAt.relativeFormatted)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if !isActive, let resolvedAt = alert.resolvedAt {
                        Text("・")
                            .foregroundColor(.secondary)
                        Text("対応: \(resolvedAt.relativeFormatted)")
                            .font(.caption2)
                            .foregroundColor(.kachaSuccess.opacity(0.7))
                    }

                    Spacer()

                    // 対応済みボタン (アクティブのみ)
                    if isActive {
                        if isConfirmingResolve {
                            HStack(spacing: 8) {
                                Button("キャンセル") {
                                    withAnimation { isConfirmingResolve = false }
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .accessibilityLabel("キャンセル")

                                Button("対応済みにする") {
                                    withAnimation { onResolve() }
                                }
                                .font(.caption).bold()
                                .foregroundColor(.kachaSuccess)
                                .accessibilityLabel("このアラートを対応済みにする")
                            }
                        } else {
                            Button {
                                withAnimation { isConfirmingResolve = true }
                            } label: {
                                Label("対応済み", systemImage: "checkmark.circle")
                                    .font(.caption)
                                    .foregroundColor(.kachaAccent)
                            }
                            .accessibilityLabel("\(alert.deviceName)のアラートを対応済みにする")
                        }
                    }
                }
            }
            .padding(2)
        }
        .opacity(isActive ? 1.0 : 0.6)
    }
}

// MARK: - Date Extension (相対表記)

private extension Date {
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - Preview Support

#if DEBUG
struct DeviceAlertView_Previews: PreviewProvider {
    static var previews: some View {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: Schema([
                Home.self, Booking.self, SmartDevice.self, DeviceIntegration.self,
                ShareRecord.self, ChecklistItem.self, UtilityRecord.self,
                MaintenanceTask.self, ActivityLog.self, HouseManual.self,
                SecureItem.self, DeviceAlert.self,
            ]),
            configurations: config
        )
        let home = Home(name: "渋谷の家")
        container.mainContext.insert(home)

        let alert1 = DeviceAlert(
            homeId: home.id,
            deviceName: "Sesame (abc12345...)",
            alertType: AlertType.lowBattery.rawValue,
            message: "電池残量が15%です。早めに交換してください。",
            severity: "warning"
        )
        let alert2 = DeviceAlert(
            homeId: home.id,
            deviceName: "玄関 SwitchBot Lock",
            alertType: AlertType.unlockAfterCheckout.rawValue,
            message: "田中様のチェックアウトから30分以上経過しましたが、玄関 SwitchBot Lockが解錠状態です。",
            severity: "critical"
        )
        let alert3 = DeviceAlert(
            homeId: home.id,
            deviceName: "リビング Hue",
            alertType: AlertType.lightLeftOn.rawValue,
            message: "リビング Hueが13時間以上点灯したままです。",
            severity: "warning",
            isResolved: true
        )
        container.mainContext.insert(alert1)
        container.mainContext.insert(alert2)
        container.mainContext.insert(alert3)

        return DeviceAlertView(home: home)
            .modelContainer(container)
            .preferredColorScheme(.dark)
    }
}
#endif
