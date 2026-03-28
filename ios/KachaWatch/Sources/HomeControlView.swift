import SwiftUI

struct HomeControlView: View {

    @EnvironmentObject private var connectivity: WatchConnectivityManager

    private let background = Color(red: 0.039, green: 0.039, blue: 0.071) // #0A0A12
    private let gold = Color(red: 0.910, green: 0.659, blue: 0.220)        // #E8A838
    private let lockedRed = Color(red: 0.9, green: 0.3, blue: 0.3)
    private let unlockedGreen = Color(red: 0.3, green: 0.85, blue: 0.5)

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                headerSection
                lockButton
                if !connectivity.lights.isEmpty {
                    lightsSection
                }
                if let error = connectivity.lastError {
                    errorView(error)
                }
            }
            .padding(.horizontal, 4)
        }
        .background(background)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 2) {
            if connectivity.homeName.isEmpty {
                Text("KAGI")
                    .font(.headline)
                    .foregroundColor(gold)
            } else {
                Text(connectivity.homeName)
                    .font(.headline)
                    .foregroundColor(gold)
                    .lineLimit(1)
                if !connectivity.homeAddress.isEmpty {
                    Text(connectivity.homeAddress)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Lock Button

    private var lockButton: some View {
        let locked = connectivity.isLocked
        return Button(action: { handleLockToggle() }) {
            ZStack {
                Circle()
                    .fill(locked ? lockedRed.opacity(0.15) : unlockedGreen.opacity(0.15))
                    .frame(width: 80, height: 80)
                Circle()
                    .strokeBorder(locked ? lockedRed : unlockedGreen, lineWidth: 2.5)
                    .frame(width: 80, height: 80)
                if connectivity.isSending {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: gold))
                        .scaleEffect(1.2)
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: locked ? "lock.fill" : "lock.open.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(locked ? lockedRed : unlockedGreen)
                        Text(locked ? "施錠中" : "解錠中")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(locked ? lockedRed : unlockedGreen)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(connectivity.isSending)
    }

    // MARK: - Lights

    private var lightsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("照明")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.leading, 4)
            ForEach(connectivity.lights) { light in
                lightRow(light)
            }
        }
    }

    private func lightRow(_ light: WatchLightInfo) -> some View {
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
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 10))
            .foregroundColor(.red)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 6)
    }

    // MARK: - Actions

    private func handleLockToggle() {
        if connectivity.isLocked {
            connectivity.sendUnlock()
        } else {
            connectivity.sendLock()
        }
    }
}

#Preview {
    HomeControlView()
        .environmentObject(WatchConnectivityManager.shared)
}
