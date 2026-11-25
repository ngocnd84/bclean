import StoreKit
import SwiftUI

/// Thanh toán trong app bằng StoreKit 2 (không cần server).
@MainActor
final class StoreManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedIDs: Set<String> = []
    @Published private(set) var trialEligible = true
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    #if DEBUG
    /// Chỉ có trong bản thử nghiệm: giả lập đã mua Pro để test
    @Published var debugForcePro = UserDefaults.standard.bool(forKey: "debug_force_pro") {
        didSet { UserDefaults.standard.set(debugForcePro, forKey: "debug_force_pro") }
    }
    #endif

    var isPro: Bool {
        #if DEBUG
        if debugForcePro { return true }
        #endif
        return !purchasedIDs.isEmpty
    }

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task.detached { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let t) = update { await t.finish() }
                await self?.refreshEntitlements()
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    func product(_ id: String) -> Product? { products.first { $0.id == id } }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let list = try await Product.products(for: AppConfig.productOrder)
            products = list.sorted {
                (AppConfig.productOrder.firstIndex(of: $0.id) ?? 99) < (AppConfig.productOrder.firstIndex(of: $1.id) ?? 99)
            }
            if let group = products.first(where: { $0.subscription != nil })?.subscription?.subscriptionGroupID {
                trialEligible = await Product.SubscriptionInfo.isEligibleForIntroOffer(for: group)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        var ids = Set<String>()
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let t) = entitlement,
               t.revocationDate == nil,
               AppConfig.productOrder.contains(t.productID) {
                ids.insert(t.productID)
            }
        }
        purchasedIDs = ids
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        Analytics.log("purchase_start", ["product": product.id])
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    errorMessage = L("store_unverified")
                    return false
                }
                await transaction.finish()
                await refreshEntitlements()
                Analytics.log("purchase_success", ["product": product.id])
                return true
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = error.localizedDescription
        }
        await refreshEntitlements()
        if purchasedIDs.isEmpty { errorMessage = L("store_nothing_to_restore") }
    }

    // MARK: - Hiển thị

    static func periodText(_ product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return L("period_lifetime") }
        switch period.unit {
        case .day: return period.value == 7 ? L("period_week") : L("period_days_%d", period.value)
        case .week: return L("period_week")
        case .month: return L("period_month")
        case .year: return L("period_year")
        @unknown default: return ""
        }
    }

    static func trialText(_ product: Product) -> String? {
        guard let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        let p = offer.period
        let days: Int
        switch p.unit {
        case .day: days = p.value
        case .week: days = p.value * 7
        case .month: days = p.value * 30
        case .year: days = p.value * 365
        @unknown default: days = p.value
        }
        return L("trial_days_%d", days)
    }

    /// % tiết kiệm của gói năm so với trả theo tuần
    var yearlySavingPercent: Int? {
        guard let w = product(AppConfig.weeklyID), let y = product(AppConfig.yearlyID) else { return nil }
        let weekly = NSDecimalNumber(decimal: w.price).doubleValue * 52
        let yearly = NSDecimalNumber(decimal: y.price).doubleValue
        guard weekly > 0, yearly < weekly else { return nil }
        return Int(((1 - yearly / weekly) * 100).rounded())
    }
}
