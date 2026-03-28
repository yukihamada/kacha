import SwiftUI

// MARK: - Permit Progress Helper

struct PermitProgress {
    private var completed: Set<String>

    init(json: String) {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Bool] else {
            completed = []
            return
        }
        completed = Set(dict.filter(\.value).map(\.key))
    }

    func isCompleted(_ key: String) -> Bool { completed.contains(key) }

    mutating func toggle(_ key: String) {
        if completed.contains(key) { completed.remove(key) } else { completed.insert(key) }
    }

    var json: String {
        let dict = Dictionary(uniqueKeysWithValues: completed.map { ($0, true) })
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    var completedCount: Int { completed.count }
}

// MARK: - Permit Guide View

struct PermitGuideView: View {
    let businessType: String
    @Bindable var home: Home
    @Environment(\.dismiss) private var dismiss
    @State private var progress: PermitProgress
    @State private var showDocuments = false

    init(businessType: String, home: Home) {
        self.businessType = businessType
        self._home = Bindable(wrappedValue: home)
        self._progress = State(initialValue: PermitProgress(json: home.permitProgress))
    }

    private var steps: [(key: String, title: String, icon: String, color: Color, items: [String])] {
        if businessType == "minpaku" {
            return [
                ("m1", "条件を確認", "building.2", .kacha, [
                    "住居専用地域で営業可能か確認（自治体により制限あり）",
                    "マンションの場合、管理規約で民泊が禁止されていないか確認",
                    "年間180日以内の営業（自治体により更に制限される場合あり）",
                ]),
                ("m2", "消防設備を整備", "flame.fill", .kachaDanger, [
                    "消火器の設置（各階に1本以上）",
                    "住宅用火災警報器（全居室+台所）",
                    "避難経路図の作成・掲示",
                    "消防署への「防火対象物使用開始届」提出",
                ]),
                ("m3", "必要書類を準備", "doc.on.doc.fill", .kachaAccent, [
                    "住宅宿泊事業届出書（様式第一）",
                    "住宅の図面（間取り図）",
                    "賃貸の場合: 賃貸人の承諾書",
                    "マンションの場合: 管理規約の写し",
                    "欠格事由に該当しない旨の誓約書",
                    "住民票の写し",
                ]),
                ("m4", "届出を提出", "paperplane.fill", .kachaSuccess, [
                    "管轄の都道府県（または政令市・中核市）に提出",
                    "民泊制度ポータルサイトからオンライン申請可能",
                    "届出番号（M+数字）が発行される",
                ]),
                ("m5", "運営開始", "checkmark.seal.fill", .kacha, [
                    "宿泊者名簿の作成・保管（3年間）",
                    "標識の掲示（玄関付近に届出番号）",
                    "2ヶ月ごとに宿泊日数等を報告",
                ]),
            ]
        } else {
            return [
                ("r1", "用途地域を確認", "building.2", .kacha, [
                    "商業地域・近隣商業地域・準工業地域等で営業可能",
                    "住居専用地域では原則不可",
                ]),
                ("r2", "施設基準を満たす", "wrench.and.screwdriver.fill", .kachaWarn, [
                    "客室面積: 1室33m²以上（簡易宿所は1人3.3m²以上）",
                    "消防設備: 自動火災報知設備・誘導灯・消火器",
                ]),
                ("r3", "保健所に事前相談", "cross.case.fill", .kachaAccent, [
                    "管轄の保健所に事前相談（施設図面持参）",
                ]),
                ("r4", "許可申請", "doc.text.fill", .kachaSuccess, [
                    "旅館業営業許可申請書を提出",
                    "消防法令適合通知書を添付",
                    "申請手数料: 22,000〜30,000円程度",
                ]),
                ("r5", "検査・許可", "checkmark.seal.fill", .kacha, [
                    "保健所の立入検査",
                    "許可証の交付（2〜4週間程度）",
                ]),
            ]
        }
    }

    private var totalSteps: Int { steps.count }
    private var completedSteps: Int {
        steps.filter { progress.isCompleted($0.key) }.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        // Progress header
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .stroke(Color.kachaCard, lineWidth: 6)
                                    .frame(width: 80, height: 80)
                                Circle()
                                    .trim(from: 0, to: totalSteps > 0 ? CGFloat(completedSteps) / CGFloat(totalSteps) : 0)
                                    .stroke(Color.kacha, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                    .frame(width: 80, height: 80)
                                    .rotationEffect(.degrees(-90))
                                Text("\(completedSteps)/\(totalSteps)")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundColor(.kacha)
                            }
                            Text(businessType == "minpaku" ? "民泊届出" : "旅館業許可")
                                .font(.title3).bold().foregroundColor(.white)
                            if completedSteps == totalSteps {
                                Label("全ステップ完了!", systemImage: "checkmark.seal.fill")
                                    .font(.caption).foregroundColor(.kachaSuccess)
                            } else {
                                Text("ステップ\(completedSteps + 1)に取り組みましょう")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .padding(.top, 8)

                        // Quick actions
                        HStack(spacing: 10) {
                            Button { showDocuments = true } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.badge.gearshape.fill").font(.caption)
                                    Text("書類を作成").font(.caption).bold()
                                }
                                .foregroundColor(.black)
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(Color.kacha)
                                .clipShape(Capsule())
                            }

                            if businessType == "minpaku" {
                                Link(destination: URL(string: "https://www.minpaku.ishin.jp/")!) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "globe").font(.caption)
                                        Text("オンライン申請").font(.caption).bold()
                                    }
                                    .foregroundColor(.kachaAccent)
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(Color.kachaAccent.opacity(0.12))
                                    .clipShape(Capsule())
                                }
                            }
                        }

                        // Steps with checkboxes
                        ForEach(Array(steps.enumerated()), id: \.element.key) { index, step in
                            stepCard(
                                num: index + 1,
                                step: step,
                                isCompleted: progress.isCompleted(step.key),
                                onToggle: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        progress.toggle(step.key)
                                        home.permitProgress = progress.json
                                    }
                                }
                            )
                        }

                        // Links
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

    // MARK: - Step Card

    private func stepCard(num: Int, step: (key: String, title: String, icon: String, color: Color, items: [String]), isCompleted: Bool, onToggle: @escaping () -> Void) -> some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 10) {
                // Header with checkbox
                Button(action: onToggle) {
                    HStack(spacing: 10) {
                        // Checkbox
                        Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundColor(isCompleted ? .kachaSuccess : .secondary)

                        Text("\(num)")
                            .font(.caption).bold().foregroundColor(isCompleted ? .black.opacity(0.5) : .black)
                            .frame(width: 24, height: 24)
                            .background(isCompleted ? step.color.opacity(0.4) : step.color)
                            .clipShape(Circle())

                        Image(systemName: step.icon)
                            .foregroundColor(isCompleted ? step.color.opacity(0.5) : step.color)

                        Text(step.title)
                            .font(.subheadline).bold()
                            .foregroundColor(isCompleted ? .secondary : .white)
                            .strikethrough(isCompleted)

                        Spacer()
                    }
                }

                // Items (collapsed if completed)
                if !isCompleted {
                    ForEach(step.items, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•").foregroundColor(step.color)
                            Text(item).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Links

    private var linksSection: some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "link").foregroundColor(.kachaAccent)
                    Text("参考リンク").font(.subheadline).bold().foregroundColor(.white)
                }
                if businessType == "minpaku" {
                    linkRow("民泊制度ポータルサイト", "https://www.mlit.go.jp/kankocho/minpaku/")
                    linkRow("民泊制度運営システム（オンライン申請）", "https://www.minpaku.ishin.jp/")
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

    private func linkRow(_ title: String, _ url: String) -> some View {
        Group {
            if let destination = URL(string: url) {
                Link(destination: destination) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.right.square").font(.caption).foregroundColor(.kachaAccent)
                        Text(title).font(.caption).foregroundColor(.white)
                        Spacer()
                    }
                }
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
                        .onAppear { ownerAddress = home?.address ?? "" }

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
            .navigationTitle("書類テンプレート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }.foregroundStyle(.secondary)
                }
            }
        }
    }

    private func generateDocuments() {
        let addr = ownerAddress.isEmpty ? (home?.address ?? "＿＿＿＿") : ownerAddress
        let propertyAddr = home?.address ?? "＿＿＿＿"
        let name = ownerName
        let phone = phoneNumber.isEmpty ? "＿＿＿＿" : phoneNumber
        let permitNum = home?.minpakuNumber ?? ""
        let year = Calendar.current.component(.year, from: Date()) - 2018
        let f = DateFormatter(); f.dateFormat = "M月d日"
        let today = "令和\(year)年\(f.string(from: Date()))"

        var docs: [GeneratedDoc] = []

        if businessType == "minpaku" {
            docs.append(GeneratedDoc(title: "住宅宿泊事業届出書", icon: "doc.text.fill", content: """
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
            住宅の規模: ＿＿ m²（宿泊室: ＿＿ m²）
            届出番号: \(permitNum.isEmpty ? "（届出後に記入）" : permitNum)

            【管理業者への委託】
            □ 委託する（業者名: ＿＿＿＿）
            □ 委託しない

            添付書類: 住宅図面 / 誓約書 / 住民票
            """))

            docs.append(GeneratedDoc(title: "誓約書", icon: "checkmark.seal.fill", content: """
            誓約書    \(today)

            ＿＿＿＿ 都道府県知事 殿

            私は、住宅宿泊事業法第4条各号に定める
            欠格事由のいずれにも該当しないことを誓約します。

            住所: \(addr)
            氏名: \(name)
            電話: \(phone)
            """))

            docs.append(GeneratedDoc(title: "宿泊者名簿テンプレート", icon: "list.clipboard.fill", content: """
            宿泊者名簿
            届出番号: \(permitNum.isEmpty ? "M_____" : permitNum)
            届出住宅: \(propertyAddr)

            No | 宿泊日 | 氏名 | 住所 | 国籍 | パスポート番号
            1  |        |      |      |      |
            2  |        |      |      |      |

            ※ 3年間保管義務 / 外国人はパスポート写しも保管
            """))

            docs.append(GeneratedDoc(title: "標識（玄関掲示用）", icon: "signpost.right.fill", content: """
            ┌─────────────────────────┐
            │   住宅宿泊事業          │
            │                         │
            │  届出番号: \(permitNum.isEmpty ? "M_____" : permitNum)     │
            │  届出者: \(name)          │
            └─────────────────────────┘
            ※ 玄関の見やすい場所に掲示（縦25cm×横35cm以上）
            """))
        } else {
            docs.append(GeneratedDoc(title: "旅館業営業許可申請書", icon: "doc.text.fill", content: """
            旅館業営業許可申請書

            申請年月日: \(today)

            【申請者】
            氏名: \(name)  住所: \(addr)  電話: \(phone)

            【施設】
            名称: \(home?.name ?? "＿＿＿＿")
            所在地: \(propertyAddr)
            営業の種別: □ 旅館・ホテル営業  □ 簡易宿所営業
            客室数: ＿ 室 / 収容定員: ＿ 名

            添付: 構造設備概要 / 配置図 / 消防適合通知書 / 建築適合証明
            """))
        }

        generatedDocs = docs
    }
}
