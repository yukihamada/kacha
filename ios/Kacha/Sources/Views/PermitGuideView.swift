import SwiftUI

struct PermitGuideView: View {
    let businessType: String // "minpaku" or "ryokan"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        VStack(spacing: 8) {
                            ZStack {
                                Circle().fill(Color.kachaWarn.opacity(0.12)).frame(width: 80, height: 80)
                                Image(systemName: "doc.text.fill").font(.system(size: 36)).foregroundColor(.kachaWarn)
                            }
                            Text(businessType == "minpaku" ? "民泊届出ガイド" : "旅館業許可ガイド")
                                .font(.title3).bold().foregroundColor(.white)
                            Text("申請から届出番号取得までの手順")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        .padding(.top, 8)

                        if businessType == "minpaku" {
                            minpakuGuide
                        } else {
                            ryokanGuide
                        }

                        // Links
                        linksSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("申請ガイド")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }.foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Minpaku Guide

    private var minpakuGuide: some View {
        VStack(spacing: 12) {
            stepCard(1, "条件を確認",
                     "building.2", .kacha,
                     [
                        "住居専用地域で営業可能か確認（自治体により制限あり）",
                        "マンションの場合、管理規約で民泊が禁止されていないか確認",
                        "年間180日以内の営業（自治体により更に制限される場合あり）",
                     ])

            stepCard(2, "消防設備を整備",
                     "flame.fill", .kachaDanger,
                     [
                        "消火器の設置（各階に1本以上）",
                        "住宅用火災警報器（全居室+台所）",
                        "避難経路図の作成・掲示",
                        "消防署への「防火対象物使用開始届」提出",
                     ])

            stepCard(3, "必要書類を準備",
                     "doc.on.doc.fill", .kachaAccent,
                     [
                        "住宅宿泊事業届出書（様式第一）",
                        "住宅の図面（間取り図）",
                        "賃貸の場合: 賃貸人の承諾書",
                        "マンションの場合: 管理規約の写し",
                        "欠格事由に該当しない旨の誓約書",
                        "住民票の写し",
                        "登記事項証明書（法人の場合）",
                     ])

            stepCard(4, "届出を提出",
                     "paperplane.fill", .kachaSuccess,
                     [
                        "管轄の都道府県（または政令市・中核市）に提出",
                        "民泊制度ポータルサイトからオンライン申請可能",
                        "届出番号（M+数字）が発行される",
                        "届出番号をカチャの設定に入力",
                     ])

            stepCard(5, "運営開始",
                     "checkmark.seal.fill", .kacha,
                     [
                        "宿泊者名簿の作成・保管（3年間）",
                        "標識の掲示（玄関付近に届出番号）",
                        "2ヶ月ごとに宿泊日数等を報告",
                        "周辺住民への事前説明",
                     ])
        }
    }

    // MARK: - Ryokan Guide

    private var ryokanGuide: some View {
        VStack(spacing: 12) {
            stepCard(1, "用途地域を確認",
                     "building.2", .kacha,
                     [
                        "商業地域・近隣商業地域・準工業地域等で営業可能",
                        "住居専用地域では原則不可（条件付きで可能な場合あり）",
                        "用途変更が必要な場合がある（100m²超）",
                     ])

            stepCard(2, "施設基準を満たす",
                     "wrench.and.screwdriver.fill", .kachaWarn,
                     [
                        "客室面積: 1室33m²以上（簡易宿所は1人3.3m²以上）",
                        "フロント設置（簡易宿所は不要の場合あり）",
                        "消防設備: 自動火災報知設備・誘導灯・消火器",
                        "換気・照明・給排水設備",
                        "バリアフリー対応（規模による）",
                     ])

            stepCard(3, "保健所に事前相談",
                     "cross.case.fill", .kachaAccent,
                     [
                        "管轄の保健所に事前相談（必須ではないが強く推奨）",
                        "施設の図面を持参",
                        "必要な改修箇所の確認",
                        "申請に必要な書類の確認",
                     ])

            stepCard(4, "許可申請",
                     "doc.text.fill", .kachaSuccess,
                     [
                        "旅館業営業許可申請書",
                        "施設の図面・配置図",
                        "建築基準法への適合証明",
                        "消防法令適合通知書",
                        "水質検査成績書（井戸水使用の場合）",
                        "申請手数料: 22,000〜30,000円程度",
                     ])

            stepCard(5, "検査・許可",
                     "checkmark.seal.fill", .kacha,
                     [
                        "保健所の立入検査",
                        "許可証の交付（2〜4週間程度）",
                        "許可番号をカチャの設定に入力",
                        "日数制限なしで営業開始",
                     ])
        }
    }

    // MARK: - Links

    private var linksSection: some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 12) {
                SettingsHeader(icon: "link", title: "参考リンク", color: .kachaAccent)
                if businessType == "minpaku" {
                    linkRow("民泊制度ポータルサイト", "https://www.mlit.go.jp/kankocho/minpaku/")
                    linkRow("民泊制度運営システム", "https://www.minpaku.ishin.jp/")
                    linkRow("消防庁 民泊の防火対策", "https://www.fdma.go.jp/mission/prevention/items/minpaku.pdf")
                } else {
                    linkRow("旅館業法の概要（厚労省）", "https://www.mhlw.go.jp/stf/seisakunitsuite/bunya/kenkou_iryou/kenkou/seikatsu-eisei/ryokangyou/index.html")
                    linkRow("簡易宿所営業の手引き", "https://www.mhlw.go.jp/stf/newpage_04082.html")
                }
            }
            .padding(16)
        }
    }

    // MARK: - Components

    private func stepCard(_ num: Int, _ title: String, _ icon: String, _ color: Color, _ items: [String]) -> some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("\(num)")
                        .font(.caption).bold().foregroundColor(.black)
                        .frame(width: 24, height: 24)
                        .background(color)
                        .clipShape(Circle())
                    Image(systemName: icon).foregroundColor(color)
                    Text(title).font(.subheadline).bold().foregroundColor(.white)
                }
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").foregroundColor(color)
                        Text(item).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .padding(14)
        }
    }

    private func linkRow(_ title: String, _ url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.right.square").font(.caption).foregroundColor(.kachaAccent)
                Text(title).font(.caption).foregroundColor(.white)
                Spacer()
            }
        }
    }
}
