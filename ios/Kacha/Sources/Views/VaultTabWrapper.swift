import SwiftUI
import SwiftData
import LocalAuthentication

/// Safe wrapper for VaultView when used as a tab.
/// Handles Face ID before creating the full VaultView.
struct VaultTabWrapper: View {
    @State private var isUnlocked = false
    @State private var authFailed = false

    var body: some View {
        Group {
            if isUnlocked {
                VaultView(home: nil)
            } else {
                ZStack {
                    Color.kachaBg.ignoresSafeArea()
                    VStack(spacing: 24) {
                        ZStack {
                            Circle().fill(Color.kacha.opacity(0.12)).frame(width: 80, height: 80)
                            Image(systemName: "lock.shield.fill").font(.system(size: 36)).foregroundColor(.kacha)
                        }
                        Text("Face ID / Touch IDで\nロックを解除してください")
                            .font(.subheadline).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button { doAuth() } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "faceid")
                                Text("解除する")
                            }
                            .foregroundColor(.black).font(.subheadline).bold()
                            .padding(.horizontal, 28).padding(.vertical, 12)
                            .background(Color.kacha)
                            .clipShape(Capsule())
                        }
                        if authFailed {
                            Text("認証に失敗しました。もう一度お試しください。")
                                .font(.caption).foregroundColor(.red)
                        }
                    }
                }
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            doAuth()
        }
    }

    private func doAuth() {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // No biometrics — just unlock
            isUnlocked = true
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "鍵管理にアクセス") { success, _ in
            DispatchQueue.main.async {
                if success {
                    isUnlocked = true
                } else {
                    authFailed = true
                }
            }
        }
    }
}
