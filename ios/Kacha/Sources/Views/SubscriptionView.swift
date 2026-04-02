import SwiftUI

// MARK: - SubscriptionView
// サブスクリプションのペイウォール画面。Free / Pro / Business の3プランを表示。

struct SubscriptionView: View {
    @ObservedObject private var subscription = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlan: String = "pro"
    @State private var isRestoring = false
    @State private var showError = false
    @State private var errorText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        headerSection
                        planCards
                        featureComparison
                        actionButton
                        restoreButton
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("プラン")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.kachaBg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundColor(.secondary)
                }
            }
            .alert("エラー", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorText)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "door.left.hand.open")
                .font(.system(size: 48))
                .foregroundColor(.kacha)

            Text("KAGI プラン")
                .font(.title2).bold().foregroundColor(.white)

            Text("あなたの運営スタイルに合わせたプランを選択")
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 16)
    }

    // MARK: - Plan Cards

    private var planCards: some View {
        VStack(spacing: 12) {
            planCard(
                id: "free",
                name: "Free",
                price: "無料",
                description: "1物件の基本管理",
                icon: "person.fill",
                color: .secondary,
                isCurrentPlan: subscription.currentPlan == "free"
            )

            planCard(
                id: "pro",
                name: "Pro",
                price: proPrice,
                description: "複数物件・AI自動返信・収益分析",
                icon: "star.fill",
                color: .kacha,
                isCurrentPlan: subscription.currentPlan == "pro",
                isPopular: true
            )

            planCard(
                id: "business",
                name: "Business",
                price: businessPrice,
                description: "チーム管理・清掃管理・全機能",
                icon: "building.2.fill",
                color: .kachaAccent,
                isCurrentPlan: subscription.currentPlan == "business"
            )
        }
    }

    private var proPrice: String {
        if let product = subscription.proProduct() {
            return product.displayPrice + "/月"
        }
        return "¥980/月"
    }

    private var businessPrice: String {
        if let product = subscription.businessProduct() {
            return product.displayPrice + "/月"
        }
        return "¥2,980/月"
    }

    private func planCard(
        id: String,
        name: String,
        price: String,
        description: String,
        icon: String,
        color: Color,
        isCurrentPlan: Bool,
        isPopular: Bool = false
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedPlan = id
            }
        } label: {
            KachaCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: icon)
                            .foregroundColor(color)
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(name)
                                    .font(.headline).foregroundColor(.white)
                                if isPopular {
                                    Text("人気")
                                        .font(.caption2).bold()
                                        .foregroundColor(.kachaBg)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.kacha)
                                        .clipShape(Capsule())
                                }
                                if isCurrentPlan {
                                    Text("現在のプラン")
                                        .font(.caption2).bold()
                                        .foregroundColor(.kachaSuccess)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.kachaSuccess.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                            Text(description)
                                .font(.caption).foregroundColor(.secondary)
                        }

                        Spacer()

                        Text(price)
                            .font(.subheadline).bold()
                            .foregroundColor(color)
                    }
                }
                .padding(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(selectedPlan == id ? color : Color.clear, lineWidth: 2)
                )
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Feature Comparison

    private var featureComparison: some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("機能比較")
                    .font(.subheadline).bold().foregroundColor(.white)

                featureRow("スマートロック操作", free: true, pro: true, business: true)
                featureRow("ゲストカード生成", free: true, pro: true, business: true)
                featureRow("予約管理（Beds24連携）", free: true, pro: true, business: true)
                Divider().background(Color.kachaCardBorder)
                featureRow("複数物件", free: false, pro: true, business: true)
                featureRow("AI自動返信", free: false, pro: true, business: true)
                featureRow("収益ダッシュボード", free: false, pro: true, business: true)
                featureRow("民泊180日カウンター", free: false, pro: true, business: true)
                featureRow("レポートエクスポート", free: false, pro: true, business: true)
                Divider().background(Color.kachaCardBorder)
                featureRow("チーム管理", free: false, pro: false, business: true)
                featureRow("清掃管理", free: false, pro: false, business: true)
                featureRow("オートメーション", free: false, pro: false, business: true)
            }
            .padding(16)
        }
    }

    private func featureRow(_ name: String, free: Bool, pro: Bool, business: Bool) -> some View {
        HStack(spacing: 0) {
            Text(name)
                .font(.caption).foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            checkMark(free)
                .frame(width: 40)
            checkMark(pro)
                .frame(width: 40)
            checkMark(business)
                .frame(width: 40)
        }
    }

    @ViewBuilder
    private func checkMark(_ available: Bool) -> some View {
        if available {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.kachaSuccess)
        } else {
            Image(systemName: "minus.circle")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.4))
        }
    }

    // MARK: - Action Button

    private var actionButton: some View {
        Group {
            if selectedPlan == "free" {
                // Free プランが選択された場合は何もしない
                EmptyView()
            } else if selectedPlan == subscription.currentPlan {
                Text("現在ご利用中のプランです")
                    .font(.subheadline).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(14)
            } else {
                Button {
                    Task { await purchaseSelected() }
                } label: {
                    HStack {
                        if subscription.isPurchasing {
                            ProgressView().tint(.kachaBg)
                        }
                        Text(selectedPlan == "pro" ? "Proを始める" : "Businessを始める")
                            .font(.headline).bold()
                    }
                    .foregroundColor(.kachaBg)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(selectedPlan == "pro" ? Color.kacha : Color.kachaAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(subscription.isPurchasing)
            }
        }
    }

    // MARK: - Restore

    private var restoreButton: some View {
        Button {
            Task { await restorePurchases() }
        } label: {
            HStack(spacing: 6) {
                if isRestoring {
                    ProgressView().tint(.secondary).controlSize(.small)
                }
                Text("購入を復元")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .disabled(isRestoring)
    }

    // MARK: - Actions

    private func purchaseSelected() async {
        let productId = selectedPlan == "pro"
            ? SubscriptionManager.proMonthlyID
            : SubscriptionManager.businessMonthlyID

        do {
            try await subscription.purchase(productId)
            if subscription.currentPlan != "free" {
                dismiss()
            }
        } catch {
            errorText = error.localizedDescription
            showError = true
        }
    }

    private func restorePurchases() async {
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await subscription.restore()
        } catch {
            errorText = "復元に失敗しました: \(error.localizedDescription)"
            showError = true
        }
    }
}

// MARK: - Upgrade Prompt Banner
// 各画面で使うペイウォールバナー

struct UpgradePromptView: View {
    let title: String
    let message: String
    let requiredPlan: String  // "pro" or "business"
    @State private var showSubscription = false

    var body: some View {
        KachaCard {
            VStack(spacing: 12) {
                Image(systemName: requiredPlan == "business" ? "building.2.fill" : "star.fill")
                    .font(.system(size: 32))
                    .foregroundColor(requiredPlan == "business" ? .kachaAccent : .kacha)

                Text(title)
                    .font(.subheadline).bold().foregroundColor(.white)

                Text(message)
                    .font(.caption).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    showSubscription = true
                } label: {
                    Text("アップグレード")
                        .font(.subheadline).bold()
                        .foregroundColor(.kachaBg)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(requiredPlan == "business" ? Color.kachaAccent : Color.kacha)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $showSubscription) {
            SubscriptionView()
        }
    }
}

// MARK: - Pro Feature Overlay
// 収益ダッシュボードなどでぼかしオーバーレイとして使用

struct ProFeatureOverlay: View {
    let featureName: String
    @State private var showSubscription = false

    var body: some View {
        ZStack {
            // ぼかし背景
            Color.kachaBg.opacity(0.7)

            VStack(spacing: 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.kacha)

                Text("\(featureName)")
                    .font(.headline).foregroundColor(.white)

                Text("Pro以上のプランで利用可能")
                    .font(.caption).foregroundColor(.secondary)

                Button {
                    showSubscription = true
                } label: {
                    Text("プランを見る")
                        .font(.subheadline).bold()
                        .foregroundColor(.kachaBg)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.kacha)
                        .clipShape(Capsule())
                }
            }
        }
        .sheet(isPresented: $showSubscription) {
            SubscriptionView()
        }
    }
}
