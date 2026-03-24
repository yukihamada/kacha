import SwiftUI

struct SecurityInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Header
                        VStack(spacing: 8) {
                            ZStack {
                                Circle().fill(Color.kachaSuccess.opacity(0.12)).frame(width: 80, height: 80)
                                Image(systemName: "lock.shield.fill").font(.system(size: 36)).foregroundColor(.kachaSuccess)
                            }
                            Text("セキュリティとデータ保護").font(.title3).bold().foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)

                        // Data storage
                        infoCard(
                            icon: "iphone",
                            title: "データの保存場所",
                            color: .kacha,
                            items: [
                                ("デバイス設定（APIキー等）", "iPhoneのローカルストレージ（SwiftData）にのみ保存。外部サーバーには送信されません。"),
                                ("予約・チェックリスト・光熱費", "すべてiPhoneのローカルに保存。"),
                                ("アクティビティログ", "ローカル保存 + デバイスAPIから取得した履歴。"),
                            ]
                        )

                        // Sharing security
                        infoCard(
                            icon: "person.badge.plus",
                            title: "シェアのセキュリティ",
                            color: .kachaAccent,
                            items: [
                                ("E2E暗号化", "シェアデータはAES-256-GCMで端末上で暗号化。サーバーには暗号化済みデータのみ保存され、平文は一切送信されません。"),
                                ("復号キーの保護", "復号キーはURLフラグメント（#以降）に格納。HTTPリクエストでサーバーに送信されないため、サーバーがハッキングされてもデータは安全です。"),
                                ("期限管理", "サーバー側で有効期間を強制。期限切れのリンクはデータを返しません。"),
                                ("取り消し", "オーナーはいつでもシェアを取り消し可能。取り消し後はアクセス不能に。"),
                            ]
                        )

                        // API keys
                        infoCard(
                            icon: "key.fill",
                            title: "APIキーの安全性",
                            color: .kachaWarn,
                            items: [
                                ("ローカル保存", "SwitchBot、Sesame、Hue等のAPIキーはiPhoneのローカルストレージにのみ保存。"),
                                ("通信", "各デバイスメーカーのAPIサーバーと直接通信。カチャのサーバーを経由しません。"),
                                ("キーローテーション", "シェア終了後にAPIキーを入れ替える機能を搭載。古いキーを無効化できます。"),
                            ]
                        )

                        // What we don't do
                        infoCard(
                            icon: "xmark.shield.fill",
                            title: "カチャがしないこと",
                            color: .kachaDanger,
                            items: [
                                ("広告トラッキングなし", "広告SDKは一切組み込んでいません。"),
                                ("データ販売なし", "ユーザーデータを第三者に提供・販売しません。"),
                                ("アナリティクスなし", "利用状況の収集は行っていません。"),
                                ("クラウド同期なし", "データはiPhoneのローカルにのみ存在します。（シェア時の暗号化blobを除く）"),
                            ]
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("セキュリティ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }.foregroundStyle(.secondary)
                }
            }
        }
    }

    private func infoCard(icon: String, title: String, color: Color, items: [(String, String)]) -> some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: icon).foregroundColor(color)
                    Text(title).font(.subheadline).bold().foregroundColor(.white)
                }
                ForEach(items, id: \.0) { label, desc in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(label).font(.caption).bold().foregroundColor(.white)
                        Text(desc).font(.caption2).foregroundColor(.secondary)
                    }
                    if label != items.last?.0 {
                        Divider().background(Color.kachaCardBorder)
                    }
                }
            }
            .padding(16)
        }
    }
}
