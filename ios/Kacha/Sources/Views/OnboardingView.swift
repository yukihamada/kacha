import SwiftUI
import SwiftData

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("activeHomeId") private var activeHomeId = ""
    @Environment(\.modelContext) private var modelContext

    @State private var currentPage = 0
    @State private var facilityInput = ""

    private let pages: [(icon: String, title: String, description: String, color: Color)] = [
        (
            icon: "homekit",
            title: "カチャとは",
            description: "自分の家のスマートデバイスを一元管理するアプリです。SwitchBotとPhilips Hueに対応し、外出先からも鍵・照明・カーテンをコントロールできます。民泊として貸し出す場合は設定からオンにするだけ。",
            color: .kacha
        ),
        (
            icon: "lock.shield.fill",
            title: "デバイス連携",
            description: "SwitchBot APIキーを設定すればスマートロックを遠隔操作。Philips HueブリッジをWi-Fiで自動検索し、おやすみシーンや外出シーンをワンタップで切り替えられます。",
            color: .kachaAccent
        ),
        (
            icon: "house.fill",
            title: "あなたの家を設定",
            description: "家の名前を入力してスタートしましょう。民泊出品はあとから設定でオンにできます。",
            color: .kachaSuccess
        )
    ]

    var body: some View {
        ZStack {
            Color.kachaBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Page content
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        OnboardingPageView(
                            icon: page.icon,
                            title: page.title,
                            description: page.description,
                            color: page.color,
                            isLast: index == pages.count - 1,
                            facilityInput: $facilityInput
                        )
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

                // Navigation buttons
                HStack {
                    if currentPage > 0 {
                        Button("戻る") {
                            withAnimation { currentPage -= 1 }
                        }
                        .foregroundColor(.secondary)
                        .frame(width: 80)
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
                            Text(currentPage == pages.count - 1 ? "はじめる" : "次へ")
                                .bold()
                            Image(systemName: currentPage == pages.count - 1
                                  ? "door.left.hand.open"
                                  : "arrow.right")
                        }
                        .foregroundColor(.kachaBg)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(
                            currentPage == pages.count - 1 && facilityInput.isEmpty
                            ? Color.kacha.opacity(0.4)
                            : Color.kacha
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

struct OnboardingPageView: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    let isLast: Bool
    @Binding var facilityInput: String

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 120, height: 120)
                Image(systemName: icon)
                    .font(.system(size: 52))
                    .foregroundColor(color)
            }

            VStack(spacing: 12) {
                Text(title)
                    .font(.title).bold()
                    .foregroundColor(.white)

                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if isLast {
                VStack(alignment: .leading, spacing: 8) {
                    Text("施設名")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("例: 我が家、山田家、渋谷の部屋", text: $facilityInput)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(14)
                        .background(Color.kachaCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(facilityInput.isEmpty ? Color.kachaCardBorder : Color.kacha, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 32)
            }

            Spacer()
            Spacer()
        }
    }
}
