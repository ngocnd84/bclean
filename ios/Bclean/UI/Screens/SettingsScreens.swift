import StoreKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var store: StoreManager
    @Environment(\.openURL) private var openURL
    @State private var showPaywall = false
    @State private var confirmReset = false

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if store.isPro {
                        Label(L("pro_active"), systemImage: "crown.fill").foregroundStyle(.orange)
                    } else {
                        Button { showPaywall = true; Analytics.log("paywall_view", ["source": "settings"]) } label: {
                            Label(L("upgrade_pro"), systemImage: "crown.fill")
                        }
                        LabeledContent(L("free_deletes_left"), value: "\(FreeQuota.deletes.remaining)/\(FreeQuota.deletes.limit)")
                        LabeledContent(L("free_compress_left"), value: "\(FreeQuota.compress.remaining)/\(FreeQuota.compress.limit)")
                    }
                    Button(L("restore_purchases")) { Task { await store.restore() } }
                }

                Section(L("section_help")) {
                    NavigationLink { TipsView() } label: {
                        Label(L("tips_title"), systemImage: "lightbulb")
                    }
                    Button {
                        if let url = URL(string: "photos-redirect://") { openURL(url) }
                    } label: {
                        Label(L("open_photos_app"), systemImage: "photo")
                    }
                    Button {
                        if let url = URL(string: "mailto:\(AppConfig.supportEmail)?subject=Bclean%20\(version)") { openURL(url) }
                    } label: {
                        Label(L("contact_support"), systemImage: "envelope")
                    }
                    Button {
                        if let url = URL(string: "https://apps.apple.com/app/id\(AppConfig.appStoreID)?action=write-review") { openURL(url) }
                    } label: {
                        Label(L("rate_app"), systemImage: "star")
                    }
                }

                Section(L("section_data")) {
                    Button(L("rescan")) { library.startScan() }
                        .disabled(library.isScanning)
                    Button(L("reset_cache"), role: .destructive) { confirmReset = true }
                        .disabled(library.isScanning)
                }

                Section {
                    Link(L("privacy_policy"), destination: AppConfig.privacyURL)
                    Link(L("terms_of_use"), destination: AppConfig.termsURL)
                    LabeledContent(L("version"), value: version)
                } footer: {
                    Text(L("privacy_footer"))
                }

                #if DEBUG
                Section("Developer (DEBUG)") {
                    Toggle("Giả lập đã mua Pro", isOn: $store.debugForcePro)
                    Button("Reset hạn mức miễn phí hôm nay") {
                        UserDefaults.standard.removeObject(forKey: "quota_delete_count")
                        UserDefaults.standard.removeObject(forKey: "quota_compress_count")
                    }
                    Button("Xem lại Onboarding") { UserDefaults.standard.set(false, forKey: "onboarded") }
                }
                #endif
            }
            .navigationTitle(L("tab_settings"))
            .sheet(isPresented: $showPaywall) { PaywallView(reason: nil) }
            .confirmationDialog(L("reset_cache_confirm"), isPresented: $confirmReset, titleVisibility: .visible) {
                Button(L("reset_cache"), role: .destructive) {
                    library.resetCache()
                    library.startScan()
                }
            }
            .alert(L("notice"), isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } })) {
                Button(L("ok"), role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }
}

/// Mẹo giải phóng dung lượng ngoài ảnh — trung thực về những gì app KHÔNG làm được trên iOS.
struct TipsView: View {
    private struct Tip: Identifiable {
        let icon: String
        let key: String
        var id: String { key }
    }

    private let tips: [Tip] = [
        Tip(icon: "trash", key: "tip_recent"),
        Tip(icon: "bubble.left.and.bubble.right", key: "tip_zalo"),
        Tip(icon: "message", key: "tip_messages"),
        Tip(icon: "square.and.arrow.down.on.square", key: "tip_offload"),
        Tip(icon: "icloud", key: "tip_icloud"),
        Tip(icon: "safari", key: "tip_safari")
    ]

    var body: some View {
        List {
            Section {
                ForEach(tips) { tip in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: tip.icon)
                            .font(.title3)
                            .foregroundStyle(Theme.teal)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L(tip.key + "_title")).font(.headline)
                            Text(L(tip.key + "_body")).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } footer: {
                Text(L("tips_footer"))
            }
        }
        .navigationTitle(L("tips_title"))
    }
}

struct PaywallView: View {
    let reason: String?
    @EnvironmentObject var store: StoreManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var selectedID = AppConfig.yearlyID
    @State private var purchasing = false

    private let features = ["pw_feat_unlimited", "pw_feat_compress", "pw_feat_live", "pw_feat_private", "pw_feat_support"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(.yellow)
                        .padding(.top, 8)
                    Text(L("pw_title"))
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                    if let reason {
                        Text(reason)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.danger)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(features, id: \.self) { f in
                            Label(L(f), systemImage: "checkmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Theme.teal, .primary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if store.products.isEmpty {
                        VStack(spacing: 10) {
                            if store.isLoading { ProgressView() }
                            Text(L("pw_no_products")).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button(L("retry")) { Task { await store.loadProducts() } }
                        }
                        .padding()
                    } else {
                        VStack(spacing: 10) {
                            ForEach(store.products, id: \.id) { p in
                                productRow(p)
                            }
                        }
                    }

                    Button {
                        Task { await buy() }
                    } label: {
                        Group {
                            if purchasing { ProgressView().tint(.white) } else { Text(ctaTitle).font(.headline) }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(purchasing || store.product(selectedID) == nil)

                    HStack(spacing: 16) {
                        Button(L("restore_purchases")) { Task { await store.restore(); if store.isPro { dismiss() } } }
                        Button(L("terms_of_use")) { openURL(AppConfig.termsURL) }
                        Button(L("privacy_policy")) { openURL(AppConfig.privacyURL) }
                    }
                    .font(.caption)

                    Text(L("pw_legal"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.secondary) }
                        .accessibilityLabel(L("close"))
                }
            }
        }
    }

    private var ctaTitle: String {
        guard let p = store.product(selectedID) else { return L("pw_continue") }
        if store.trialEligible, StoreManager.trialText(p) != nil { return L("pw_start_trial") }
        return L("pw_continue")
    }

    private func productRow(_ p: Product) -> some View {
        let isSelected = p.id == selectedID
        return Button { selectedID = p.id } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.accent : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title(for: p)).font(.headline)
                        if p.id == AppConfig.yearlyID, let pct = store.yearlySavingPercent {
                            Text(L("pw_save_%d", pct))
                                .font(.caption2.bold())
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.danger, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    if store.trialEligible, let trial = StoreManager.trialText(p) {
                        Text(trial).font(.caption).foregroundStyle(Theme.teal)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(p.displayPrice).font(.headline)
                    Text(StoreManager.periodText(p)).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? Theme.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private func title(for p: Product) -> String {
        switch p.id {
        case AppConfig.weeklyID: return L("plan_weekly")
        case AppConfig.yearlyID: return L("plan_yearly")
        case AppConfig.lifetimeID: return L("plan_lifetime")
        default: return p.displayName
        }
    }

    private func buy() async {
        guard let p = store.product(selectedID) else { return }
        purchasing = true
        let ok = await store.purchase(p)
        purchasing = false
        if ok { dismiss() }
    }
}
