import SwiftUI

/// Dedicated lock control view with confirmation dialog
struct WatchLockView: View {

    @EnvironmentObject private var connectivity: WatchConnectivityManager

    @State private var showUnlockConfirm = false
    @State private var showLockConfirm = false

    private let gold = Color(red: 0.910, green: 0.659, blue: 0.220)       // #E8A838
    private let background = Color(red: 0.039, green: 0.039, blue: 0.071) // #0A0A12
    private let lockedRed = Color(red: 0.9, green: 0.3, blue: 0.3)
    private let unlockedGreen = Color(red: 0.3, green: 0.85, blue: 0.5)

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Lock status indicator
                lockStatusCircle

                // Action buttons
                actionButtons

                // Error display
                if let error = connectivity.lastError {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 6)
                }
            }
            .padding(.horizontal, 4)
        }
        .background(background)
        .navigationTitle("鍵操作")
        .confirmationDialog(
            "解錠しますか?",
            isPresented: $showUnlockConfirm,
            titleVisibility: .visible
        ) {
            Button("解錠する", role: .destructive) {
                connectivity.sendUnlock()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("玄関の鍵を遠隔で解錠します")
        }
        .confirmationDialog(
            "施錠しますか?",
            isPresented: $showLockConfirm,
            titleVisibility: .visible
        ) {
            Button("施錠する") {
                connectivity.sendLock()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("玄関の鍵を遠隔で施錠します")
        }
    }

    // MARK: - Lock Status Circle

    private var lockStatusCircle: some View {
        let locked = connectivity.isLocked
        let statusColor = locked ? lockedRed : unlockedGreen

        return ZStack {
            Circle()
                .fill(statusColor.opacity(0.12))
                .frame(width: 100, height: 100)
            Circle()
                .strokeBorder(statusColor, lineWidth: 3)
                .frame(width: 100, height: 100)

            if connectivity.isSending {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: gold))
                    .scaleEffect(1.3)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: locked ? "lock.fill" : "lock.open.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(statusColor)
                    Text(locked ? "施錠中" : "解錠中")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(statusColor)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(locked ? "現在施錠されています" : "現在解錠されています")
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        let locked = connectivity.isLocked

        return VStack(spacing: 10) {
            if locked {
                // Show unlock button
                Button {
                    showUnlockConfirm = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 14))
                        Text("解錠")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(unlockedGreen)
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(connectivity.isSending)
                .accessibilityLabel("解錠する")
                .accessibilityHint("確認後に玄関の鍵を解錠します")
            } else {
                // Show lock button
                Button {
                    showLockConfirm = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 14))
                        Text("施錠")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(lockedRed)
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(connectivity.isSending)
                .accessibilityLabel("施錠する")
                .accessibilityHint("確認後に玄関の鍵を施錠します")
            }

            // Home name context
            if !connectivity.homeName.isEmpty {
                Text(connectivity.homeName)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

#Preview {
    WatchLockView()
        .environmentObject(WatchConnectivityManager.shared)
}
