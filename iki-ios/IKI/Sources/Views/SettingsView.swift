import SwiftUI

// MARK: - IKISettingsView
// IKIアプリの設定画面

struct IKISettingsView: View {
    @State private var familyToken: String = UserDefaults.standard.string(forKey: "iki_family_token") ?? ""
    @State private var notificationsEnabled = false
    @State private var showSetup = false

    private let appVersion: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ikiBg.ignoresSafeArea()

                List {
                    // 家族トークン設定
                    Section {
                        HStack {
                            Label("家族トークン", systemImage: "key.fill")
                                .foregroundColor(.white)
                            Spacer()
                            if familyToken.isEmpty {
                                Text("未設定")
                                    .foregroundColor(.ikiDanger)
                            } else {
                                Text(maskedToken)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .listRowBackground(Color.ikiCard)

                        Button {
                            showSetup = true
                        } label: {
                            Label(
                                familyToken.isEmpty ? "トークンを設定" : "トークンを変更",
                                systemImage: "pencil.circle"
                            )
                            .foregroundColor(.iki)
                        }
                        .listRowBackground(Color.ikiCard)
                    } header: {
                        Text("デバイス接続")
                            .foregroundColor(.white.opacity(0.5))
                    }

                    // 通知設定
                    Section {
                        HStack {
                            Label("プッシュ通知", systemImage: notificationsEnabled ? "bell.badge.fill" : "bell.slash.fill")
                                .foregroundColor(.white)
                            Spacer()
                            Text(notificationsEnabled ? "有効" : "無効")
                                .foregroundColor(notificationsEnabled ? .ikiSuccess : .white.opacity(0.4))
                        }
                        .listRowBackground(Color.ikiCard)

                        if !notificationsEnabled {
                            Button {
                                openNotificationSettings()
                            } label: {
                                Label("通知設定を開く", systemImage: "gear")
                                    .foregroundColor(.iki)
                            }
                            .listRowBackground(Color.ikiCard)
                        }
                    } header: {
                        Text("通知")
                            .foregroundColor(.white.opacity(0.5))
                    }

                    // アプリ情報
                    Section {
                        HStack {
                            Label("バージョン", systemImage: "info.circle")
                                .foregroundColor(.white)
                            Spacer()
                            Text(appVersion)
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .listRowBackground(Color.ikiCard)

                        Link(destination: URL(string: "https://kacha-server.fly.dev/")!) {
                            HStack {
                                Label("IKI プロダクトページ", systemImage: "globe")
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                        .listRowBackground(Color.ikiCard)
                    } header: {
                        Text("このアプリについて")
                            .foregroundColor(.white.opacity(0.5))
                    }

                    // データ管理
                    Section {
                        Button(role: .destructive) {
                            resetApp()
                        } label: {
                            Label("データをリセット", systemImage: "trash")
                                .foregroundColor(.ikiDanger)
                        }
                        .listRowBackground(Color.ikiCard)
                    } header: {
                        Text("データ管理")
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showSetup) {
                IKISetupView(familyToken: $familyToken, onComplete: { newToken in
                    familyToken = newToken
                    UserDefaults.standard.set(newToken, forKey: "iki_family_token")
                })
            }
            .onAppear {
                checkNotificationStatus()
            }
        }
    }

    // MARK: - Helpers

    /// トークンをマスク表示 (先頭4文字 + ****)
    private var maskedToken: String {
        guard familyToken.count > 4 else { return familyToken }
        let prefix = String(familyToken.prefix(4))
        return "\(prefix)****"
    }

    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationsEnabled = settings.authorizationStatus == .authorized
            }
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func resetApp() {
        familyToken = ""
        UserDefaults.standard.removeObject(forKey: "iki_family_token")
    }
}

import UserNotifications
