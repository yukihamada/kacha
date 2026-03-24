import SwiftUI
import SwiftData

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("activeHomeId") private var activeHomeId = ""
    @Environment(\.modelContext) private var modelContext

    @State private var currentPage = 0
    @State private var facilityInput = ""

    private let pages: [(icon: String, title: String, subtitle: String, features: [(String, String)], color: Color)] = [
        (
            icon: "house.fill",
            title: "カチャ",
            subtitle: "開いた、ウェルカム。",
            features: [
                ("lock.fill", "スマートロックを遠隔操作"),
                ("lightbulb.fill", "照明をシーンで一括制御"),
                ("wifi", "ゲストにWi-Fi情報をシェア"),
            ],
            color: .kacha
        ),
        (
            icon: "person.badge.plus",
            title: "安全にシェア",
            subtitle: "友達やゲストに期限付きアクセスを提供",
            features: [
                ("lock.shield.fill", "E2E暗号化でデータを保護"),
                ("calendar.badge.clock", "いつからいつまでを指定"),
                ("xmark.circle", "いつでもワンタップで取り消し"),
            ],
            color: .kachaAccent
        ),
        (
            icon: "door.left.hand.open",
            title: "はじめましょう",
            subtitle: "家の名前を入力してスタート",
            features: [],
            color: .kachaSuccess
        )
    ]

    var body: some View {
        ZStack {
            Color.kachaBg.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        pageView(page, isLast: index == pages.count - 1)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)

                // Page indicator
                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Capsule()
                            .fill(currentPage == index ? Color.kacha : Color.white.opacity(0.3))
                            .frame(width: currentPage == index ? 24 : 8, height: 8)
                            .animation(.spring(), value: currentPage)
                    }
                }
                .padding(.vertical, 20)

                // Navigation
                HStack {
                    if currentPage > 0 {
                        Button("戻る") { withAnimation { currentPage -= 1 } }
                            .foregroundColor(.secondary).frame(width: 80)
                    } else {
                        Spacer().frame(width: 80)
                    }
                    Spacer()
                    Button {
                        if currentPage < pages.count - 1 {
                            withAnimation { currentPage += 1 }
                        } else {
                            completeOnboarding()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(currentPage == pages.count - 1 ? "はじめる" : "次へ").bold()
                            Image(systemName: currentPage == pages.count - 1 ? "door.left.hand.open" : "arrow.right")
                        }
                        .foregroundColor(.kachaBg)
                        .padding(.horizontal, 28).padding(.vertical, 14)
                        .background(
                            currentPage == pages.count - 1 && facilityInput.isEmpty
                            ? Color.kacha.opacity(0.4) : Color.kacha
                        )
                        .clipShape(Capsule())
                    }
                    .disabled(currentPage == pages.count - 1 && facilityInput.isEmpty)
                    Spacer().frame(width: 80)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }

    private func pageView(_ page: (icon: String, title: String, subtitle: String, features: [(String, String)], color: Color), isLast: Bool) -> some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle().fill(page.color.opacity(0.12)).frame(width: 120, height: 120)
                Image(systemName: page.icon).font(.system(size: 52)).foregroundColor(page.color)
            }

            VStack(spacing: 8) {
                Text(page.title).font(.title).bold().foregroundColor(.white)
                Text(page.subtitle).font(.body).foregroundColor(.secondary)
            }

            if !page.features.isEmpty {
                VStack(spacing: 14) {
                    ForEach(page.features, id: \.0) { icon, text in
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10).fill(page.color.opacity(0.12))
                                    .frame(width: 40, height: 40)
                                Image(systemName: icon).font(.system(size: 18)).foregroundColor(page.color)
                            }
                            Text(text).font(.subheadline).foregroundColor(.white)
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 40)
            }

            if isLast {
                VStack(alignment: .leading, spacing: 8) {
                    Text("家の名前").font(.caption).foregroundColor(.secondary)
                    TextField("例: 我が家、山田家、渋谷の部屋", text: $facilityInput)
                        .font(.subheadline).foregroundColor(.white)
                        .padding(14)
                        .background(Color.kachaCard)
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(facilityInput.isEmpty ? Color.kachaCardBorder : Color.kacha, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 32)
            }

            Spacer()
            Spacer()
        }
    }

    private func completeOnboarding() {
        let name = facilityInput.trimmingCharacters(in: .whitespaces)
        let home = Home(name: name.isEmpty ? "私の家" : name)
        modelContext.insert(home)
        try? modelContext.save()
        activeHomeId = home.id
        home.syncToAppStorage()
        hasCompletedOnboarding = true
    }
}
