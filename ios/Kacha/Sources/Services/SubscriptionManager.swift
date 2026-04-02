import Foundation
import StoreKit
import SwiftUI

// MARK: - SubscriptionManager
// StoreKit 2 を使ったサブスクリプション管理。
// Free / Pro (¥980/月) / Business (¥2,980/月) の3プラン。

@MainActor
class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    // Product IDs
    static let proMonthlyID = "com.enablerdao.kacha.pro_monthly"
    static let businessMonthlyID = "com.enablerdao.kacha.business_monthly"
    static let allProductIDs: Set<String> = [proMonthlyID, businessMonthlyID]

    @Published var currentPlan: String {
        didSet { UserDefaults.standard.set(currentPlan, forKey: "currentPlan") }
    }
    @Published var products: [Product] = []
    @Published var purchaseError: String?
    @Published var isPurchasing = false

    var isPro: Bool { currentPlan == "pro" || currentPlan == "business" || isDebugOverride }
    var isBusiness: Bool { currentPlan == "business" || isDebugOverride }

    /// DEBUG ビルドでは全機能をアンロック（開発がブロックされないように）
    private var isDebugOverride: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "debugSubscriptionOverride")
        #else
        return false
        #endif
    }

    private var updateListenerTask: Task<Void, Never>?

    private init() {
        self.currentPlan = UserDefaults.standard.string(forKey: "currentPlan") ?? "free"

        #if DEBUG
        // デバッグビルドではデフォルトでオーバーライドを有効にする
        if !UserDefaults.standard.bool(forKey: "debugSubscriptionOverrideSet") {
            UserDefaults.standard.set(true, forKey: "debugSubscriptionOverride")
            UserDefaults.standard.set(true, forKey: "debugSubscriptionOverrideSet")
        }
        #endif

        // サブスクリプション状態の変更を監視
        updateListenerTask = listenForTransactions()

        Task { await checkEntitlements() }
        Task { await loadProducts() }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Products

    func loadProducts() async {
        do {
            let storeProducts = try await Product.products(for: Self.allProductIDs)
            products = storeProducts.sorted { $0.price < $1.price }
        } catch {
            #if DEBUG
            print("[Subscription] Failed to load products: \(error)")
            #endif
        }
    }

    // MARK: - Purchase

    func purchase(_ productId: String) async throws {
        guard let product = products.first(where: { $0.id == productId }) else {
            throw SubscriptionError.productNotFound
        }

        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updatePlan(from: transaction)
            await transaction.finish()
        case .userCancelled:
            break
        case .pending:
            purchaseError = "購入が保留中です"
        @unknown default:
            break
        }
    }

    // MARK: - Restore

    func restore() async throws {
        try await AppStore.sync()
        await checkEntitlements()
    }

    // MARK: - Check Entitlements

    func checkEntitlements() async {
        var foundPlan = "free"

        // Business を先にチェック（上位プランを優先）
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }

            if transaction.productID == Self.businessMonthlyID {
                foundPlan = "business"
                break  // 最上位プランなのでこれ以上チェック不要
            } else if transaction.productID == Self.proMonthlyID {
                foundPlan = "pro"
            }
        }

        currentPlan = foundPlan
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await self?.updatePlan(from: transaction)
                await transaction.finish()
            }
        }
    }

    // MARK: - Helpers

    private func updatePlan(from transaction: StoreKit.Transaction) async {
        if transaction.revocationDate != nil {
            // 返金された場合
            currentPlan = "free"
            return
        }

        switch transaction.productID {
        case Self.businessMonthlyID:
            currentPlan = "business"
        case Self.proMonthlyID:
            currentPlan = "pro"
        default:
            break
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Plan Display Helpers

    var planDisplayName: String {
        switch currentPlan {
        case "business": return "Business"
        case "pro": return "Pro"
        default: return "Free"
        }
    }

    var planIcon: String {
        switch currentPlan {
        case "business": return "building.2.fill"
        case "pro": return "star.fill"
        default: return "person.fill"
        }
    }

    var planColor: Color {
        switch currentPlan {
        case "business": return .kachaAccent
        case "pro": return .kacha
        default: return .secondary
        }
    }

    func proProduct() -> Product? {
        products.first { $0.id == Self.proMonthlyID }
    }

    func businessProduct() -> Product? {
        products.first { $0.id == Self.businessMonthlyID }
    }
}

// MARK: - Errors

enum SubscriptionError: LocalizedError {
    case productNotFound
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .productNotFound: return "商品が見つかりませんでした"
        case .verificationFailed: return "購入の検証に失敗しました"
        }
    }
}
