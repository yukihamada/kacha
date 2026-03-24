import SwiftUI

struct PermitGuideView: View {
    let businessType: String
    let home: Home?
    @Environment(\.dismiss) private var dismiss
    @State private var showDocuments = false

    init(businessType: String, home: Home? = nil) {
        self.businessType = businessType
        self.home = home
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
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

                        // Document generation button
                        Button { showDocuments = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.badge.gearshape.fill").font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text("申請書類を自動作成").font(.subheadline).bold()
                                        Text("Beta").font(.system(size: 9)).bold()
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Color.black.opacity(0.2))
                                            .clipShape(Capsule())
                                    }
                                    Text("住所・名前等を自動入力したテンプレートを生成")
                                        .font(.caption2).opacity(0.8)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .foregroundColor(.black)
                            .padding(14)
                            .frame(maxWidth: .infinity)
                            .background(Color.kacha)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal, 16)

                        if businessType == "minpaku" {
                            minpakuGuide
                        } else {
                            ryokanGuide
                        }

                        linksSection
                    }
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
            .sheet(isPresented: $showDocuments) {
                DocumentTemplateView(businessType: businessType, home: home)
            }
        }
    }

    // MARK: - Minpaku Guide

    private var minpakuGuide: some View {
        VStack(spacing: 10) {
            stepCard(1, "条件を確認", "building.2", .kacha, [
                "住居専用地域で営業可能か確認（自治体により制限あり）",
                "マンションの場合、管理規約で民泊が禁止されていないか確認",
                "年間180日以内の営業（自治体により更に制限される場合あり）",
            ])
            stepCard(2, "消防設備を整備", "flame.fill", .kachaDanger, [
                "消火器の設置（各階に1本以上）",
                "住宅用火災警報器（全居室+台所）",
                "避難経路図の作成・掲示",
                "消防署への「防火対象物使用開始届」提出",
            ])
            stepCard(3, "必要書類を準備", "doc.on.doc.fill", .kachaAccent, [
                "住宅宿泊事業届出書（様式第一）",
                "住宅の図面（間取り図）",
                "賃貸の場合: 賃貸人の承諾書",
                "マンションの場合: 管理規約の写し",
                "欠格事由に該当しない旨の誓約書",
                "住民票の写し",
            ])
            stepCard(4, "届出を提出", "paperplane.fill", .kachaSuccess, [
                "管轄の都道府県（または政令市・中核市）に提出",
                "民泊制度ポータルサイトからオンライン申請可能",
                "届出番号（M+数字）が発行される",
                "届出番号をカチャの設定に入力",
            ])
            stepCard(5, "運営開始", "checkmark.seal.fill", .kacha, [
                "宿泊者名簿の作成・保管（3年間）",
                "標識の掲示（玄関付近に届出番号）",
                "2ヶ月ごとに宿泊日数等を報告",
                "周辺住民への事前説明",
            ])
        }
    }

    // MARK: - Ryokan Guide

    private var ryokanGuide: some View {
        VStack(spacing: 10) {
            stepCard(1, "用途地域を確認", "building.2", .kacha, [
                "商業地域・近隣商業地域・準工業地域等で営業可能",
                "住居専用地域では原則不可（条件付きで可能な場合あり）",
                "用途変更が必要な場合がある（100m²超）",
            ])
            stepCard(2, "施設基準を満たす", "wrench.and.screwdriver.fill", .kachaWarn, [
                "客室面積: 1室33m²以上（簡易宿所は1人3.3m²以上）",
                "フロント設置（簡易宿所は不要の場合あり）",
                "消防設備: 自動火災報知設備・誘導灯・消火器",
                "換気・照明・給排水設備",
            ])
            stepCard(3, "保健所に事前相談", "cross.case.fill", .kachaAccent, [
                "管轄の保健所に事前相談（強く推奨）",
                "施設の図面を持参",
                "必要な改修箇所の確認",
            ])
            stepCard(4, "許可申請", "doc.text.fill", .kachaSuccess, [
                "旅館業営業許可申請書",
                "施設の図面・配置図",
                "消防法令適合通知書",
                "申請手数料: 22,000〜30,000円程度",
            ])
            stepCard(5, "検査・許可", "checkmark.seal.fill", .kacha, [
                "保健所の立入検査",
                "許可証の交付（2〜4週間程度）",
                "許可番号をカチャの設定に入力",
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
        .padding(.horizontal, 16)
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
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

// MARK: - Document Template Generator

struct DocumentTemplateView: View {
    let businessType: String
    let home: Home?
    @Environment(\.dismiss) private var dismiss
    @State private var ownerName = ""
    @State private var ownerAddress = ""
    @State private var phoneNumber = ""
    @State private var generatedDocs: [GeneratedDoc] = []

    struct GeneratedDoc: Identifiable {
        let id = UUID()
        let title: String
        let icon: String
        let content: String
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        // Input fields
                        KachaCard {
                            VStack(spacing: 14) {
                                SettingsHeader(icon: "person.fill", title: "申請者情報", color: .kacha)
                                SettingsTextField(label: "氏名", placeholder: "山田 太郎", text: $ownerName)
                                Divider().background(Color.kachaCardBorder)
                                SettingsTextField(label: "住所", placeholder: home?.address ?? "東京都...", text: $ownerAddress)
                                Divider().background(Color.kachaCardBorder)
                                SettingsTextField(label: "電話番号", placeholder: "090-xxxx-xxxx", text: $phoneNumber)
                            }
                            .padding(16)
                        }
                        .padding(.horizontal, 16)
                        .onAppear {
                            ownerAddress = home?.address ?? ""
                        }

                        // Generate button
                        Button { generateDocuments() } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.badge.gearshape.fill")
                                Text("書類を生成").bold()
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(ownerName.isEmpty ? Color.kacha.opacity(0.4) : Color.kacha)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(ownerName.isEmpty)
                        .padding(.horizontal, 16)

                        // Generated documents
                        ForEach(generatedDocs) { doc in
                            KachaCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 8) {
                                        Image(systemName: doc.icon).foregroundColor(.kacha)
                                        Text(doc.title).font(.subheadline).bold().foregroundColor(.white)
                                        Spacer()
                                        ShareLink(item: doc.content) {
                                            Image(systemName: "square.and.arrow.up").font(.caption).foregroundColor(.kachaAccent)
                                        }
                                    }
                                    Text(doc.content)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("書類テンプレート (Beta)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }.foregroundStyle(.secondary)
                }
            }
        }
    }

    private func generateDocuments() {
        let addr = ownerAddress.isEmpty ? (home?.address ?? "＿＿＿＿＿＿＿＿") : ownerAddress
        let propertyAddr = home?.address ?? "＿＿＿＿＿＿＿＿"
        let name = ownerName
        let phone = phoneNumber.isEmpty ? "＿＿＿＿＿＿＿＿" : phoneNumber
        let permitNum = home?.minpakuNumber ?? ""
        let today = {
            let f = DateFormatter(); f.dateFormat = "令和\(Calendar.current.component(.year, from: Date()) - 2018)年M月d日"
            return f.string(from: Date())
        }()

        var docs: [GeneratedDoc] = []

        if businessType == "minpaku" {
            docs.append(GeneratedDoc(
                title: "住宅宿泊事業届出書",
                icon: "doc.text.fill",
                content: """
                住宅宿泊事業届出書

                届出年月日: \(today)

                【届出者】
                氏名: \(name)
                住所: \(addr)
                電話番号: \(phone)

                【届出住宅】
                所在地: \(propertyAddr)
                住宅の種別: □ 自己の生活の本拠  □ 入居者の募集が行われている家屋
                           □ 随時その所有者等の居住の用に供されている家屋
                住宅の規模: ＿＿＿ m²（宿泊室の面積: ＿＿＿ m²）
                届出番号: \(permitNum.isEmpty ? "（届出後に記入）" : permitNum)

                【管理業者への委託】
                □ 委託する（業者名: ＿＿＿＿＿＿＿＿）
                □ 委託しない（住宅宿泊管理業務を自ら行う）

                ※ 本届出書と併せて以下の書類を添付すること
                ・住宅の図面
                ・欠格事由に該当しない旨の誓約書
                ・住民票の写し
                """
            ))

            docs.append(GeneratedDoc(
                title: "誓約書",
                icon: "checkmark.seal.fill",
                content: """
                誓約書

                \(today)

                ＿＿＿＿＿＿＿＿ 都道府県知事 殿

                私は、住宅宿泊事業法第4条各号に定める
                欠格事由のいずれにも該当しないことを誓約します。

                住所: \(addr)
                氏名: \(name)
                電話番号: \(phone)
                """
            ))

            docs.append(GeneratedDoc(
                title: "宿泊者名簿（テンプレート）",
                icon: "list.clipboard.fill",
                content: """
                宿泊者名簿

                届出番号: \(permitNum.isEmpty ? "M__________" : permitNum)
                届出住宅: \(propertyAddr)

                No. | 宿泊日 | 氏名 | 住所 | 職業 | 国籍 | パスポート番号
                ---|--------|------|------|------|------|-------------
                1  |        |      |      |      |      |
                2  |        |      |      |      |      |
                3  |        |      |      |      |      |

                ※ 3年間保管義務あり
                ※ 外国人の場合はパスポート写しも保管
                """
            ))

            docs.append(GeneratedDoc(
                title: "標識（玄関掲示用）",
                icon: "signpost.right.fill",
                content: """
                ┌────────────────────────────┐
                │                            │
                │    住宅宿泊事業            │
                │                            │
                │  届出番号: \(permitNum.isEmpty ? "M__________" : permitNum)      │
                │                            │
                │  届出者: \(name)            │
                │                            │
                └────────────────────────────┘

                ※ 玄関の見やすい場所に掲示してください
                ※ 大きさ: 縦25cm以上 × 横35cm以上
                """
            ))

        } else {
            // Ryokan
            docs.append(GeneratedDoc(
                title: "旅館業営業許可申請書",
                icon: "doc.text.fill",
                content: """
                旅館業営業許可申請書

                申請年月日: \(today)

                【申請者】
                氏名: \(name)
                住所: \(addr)
                電話番号: \(phone)

                【施設】
                名称: \(home?.name ?? "＿＿＿＿＿＿＿＿")
                所在地: \(propertyAddr)
                営業の種別: □ 旅館・ホテル営業  □ 簡易宿所営業
                客室数: ＿＿＿ 室
                収容定員: ＿＿＿ 名
                敷地面積: ＿＿＿ m²
                延床面積: ＿＿＿ m²

                【添付書類】
                □ 施設の構造設備の概要
                □ 施設の配置図・各階平面図
                □ 消防法令適合通知書
                □ 建築基準法適合証明書
                □ 水質検査成績書（該当する場合）
                □ 登記事項証明書（法人の場合）
                """
            ))

            docs.append(GeneratedDoc(
                title: "宿泊者名簿（テンプレート）",
                icon: "list.clipboard.fill",
                content: """
                宿泊者名簿

                施設名: \(home?.name ?? "＿＿＿＿＿＿＿＿")
                許可番号: \(permitNum.isEmpty ? "＿＿＿＿＿＿＿＿" : permitNum)

                No. | 宿泊日 | 氏名 | 住所 | 職業 | 国籍 | パスポート番号
                ---|--------|------|------|------|------|-------------
                1  |        |      |      |      |      |
                2  |        |      |      |      |      |

                ※ 3年間保管義務あり
                """
            ))
        }

        generatedDocs = docs
    }
}
