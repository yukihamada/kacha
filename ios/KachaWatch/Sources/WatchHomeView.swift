import SwiftUI

/// Watch home screen: property status + today's check-ins + lock shortcut
struct WatchHomeView: View {

    @EnvironmentObject private var connectivity: WatchConnectivityManager

    private let gold = Color(red: 0.910, green: 0.659, blue: 0.220)       // #E8A838
    private let background = Color(red: 0.039, green: 0.039, blue: 0.071) // #0A0A12

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Home name header
                    headerSection

                    // Lock shortcut
                    NavigationLink(destination: WatchLockView()) {
                        lockStatusRow
                    }
                    .buttonStyle(.plain)

                    // Today's check-ins
                    if !connectivity.todayCheckIns.isEmpty {
                        checkInsSection
                    }

                    // Lights quick access
                    if !connectivity.lights.isEmpty {
                        lightsSection
                    }

                    // Connection status
                    if !connectivity.isConnected {
                        disconnectedBanner
                    }
                }
                .padding(.horizontal, 4)
            }
            .background(background)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 2) {
            Text(connectivity.homeName.isEmpty ? "KAGI" : connectivity.homeName)
                .font(.headline)
                .foregroundColor(gold)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            if !connectivity.homeAddress.isEmpty {
                Text(connectivity.homeAddress)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Lock Status Row

    private var lockStatusRow: some View {
        let locked = connectivity.isLocked
        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill((locked ? Color.red : Color.green).opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: locked ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(locked ? .red : .green)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(locked ? "施錠中" : "解錠中")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text("タップして操作")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06))
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(locked ? "施錠中。タップして鍵を操作" : "解錠中。タップして鍵を操作")
    }

    // MARK: - Today's Check-ins

    private var checkInsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("本日チェックイン")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(gold)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)

            ForEach(connectivity.todayCheckIns) { checkIn in
                HStack(spacing: 8) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 12))
                        .foregroundColor(gold.opacity(0.7))
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(checkIn.guestName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(checkIn.timeLabel)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06))
                .cornerRadius(10)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(checkIn.guestName)、\(checkIn.timeLabel)")
            }
        }
    }

    // MARK: - Lights

    private var lightsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("照明")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)

            ForEach(connectivity.lights) { light in
                Button(action: {
                    connectivity.sendToggleLight(deviceId: light.deviceId, isOn: !light.isOn)
                }) {
                    HStack {
                        Image(systemName: light.isOn ? "lightbulb.fill" : "lightbulb")
                            .font(.system(size: 14))
                            .foregroundColor(light.isOn ? gold : .secondary)
                            .frame(width: 20)
                        Text(light.name)
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                        Circle()
                            .fill(light.isOn ? gold : Color.gray.opacity(0.4))
                            .frame(width: 8, height: 8)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("\(light.name)、\(light.isOn ? "オン" : "オフ")")
                .accessibilityHint("ダブルタップで切り替えます")
            }
        }
    }

    // MARK: - Disconnected

    private var disconnectedBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "iphone.slash")
                .font(.system(size: 12))
                .foregroundColor(.orange)
            Text("iPhoneと未接続")
                .font(.system(size: 11))
                .foregroundColor(.orange)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}
