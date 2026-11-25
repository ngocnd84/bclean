import SwiftUI

/// Luồng xoá dùng chung: kiểm tra hạn mức → xoá → báo kết quả / mở paywall.
@MainActor
final class DeletionFlow: ObservableObject {
    @Published var isWorking = false
    @Published var showPaywall = false
    @Published var paywallReason: String?
    @Published var success: String?
    @Published var error: String?

    func handle(_ outcome: DeleteOutcome, converted: Bool = false) {
        switch outcome {
        case .done(let count, let bytes):
            success = converted
                ? L("done_converted_%d_%@", count, Fmt.bytes(bytes))
                : L("done_deleted_%d_%@", count, Fmt.bytes(bytes))
        case .needsPro(let remaining):
            paywallReason = remaining > 0
                ? L("quota_remaining_%d", remaining)
                : L("quota_used_up")
            showPaywall = true
            Analytics.log("paywall_view", ["source": "quota"])
        case .cancelled:
            break
        case .failed(let message):
            error = message
        }
    }

    func delete(_ items: [MediaItem], library: LibraryStore, isPro: Bool) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        let outcome = await library.delete(items, isPro: isPro)
        handle(outcome)
        if case .done = outcome { return true }
        return false
    }

    func convertLive(_ items: [MediaItem], library: LibraryStore, isPro: Bool) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        let outcome = await library.convertLive(items, isPro: isPro)
        handle(outcome, converted: true)
        if case .done = outcome { return true }
        return false
    }
}

private struct DeletionFlowModifier: ViewModifier {
    @ObservedObject var flow: DeletionFlow
    @EnvironmentObject var store: StoreManager

    func body(content: Content) -> some View {
        content
            .overlay {
                if flow.isWorking {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        ProgressView().controlSize(.large).padding(24)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .sheet(isPresented: $flow.showPaywall) {
                PaywallView(reason: flow.paywallReason)
                    .environmentObject(store)
            }
            .alert(L("done_title"), isPresented: Binding(
                get: { flow.success != nil },
                set: { if !$0 { flow.success = nil } })) {
                Button(L("ok"), role: .cancel) {}
            } message: {
                Text((flow.success ?? "") + "\n\n" + L("done_recently_deleted_tip"))
            }
            .alert(L("error_title"), isPresented: Binding(
                get: { flow.error != nil },
                set: { if !$0 { flow.error = nil } })) {
                Button(L("ok"), role: .cancel) {}
            } message: {
                Text(flow.error ?? "")
            }
    }
}

extension View {
    func deletionFlow(_ flow: DeletionFlow) -> some View {
        modifier(DeletionFlowModifier(flow: flow))
    }
}

/// Thanh hành động dưới đáy khi có mục được chọn
struct SelectionBar: View {
    let count: Int
    let bytes: Int64
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let secondaryTitle, let secondaryAction {
                Button(action: secondaryAction) {
                    Text(secondaryTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(Theme.teal)
            }
            Button(action: onDelete) {
                Text(L("delete_n_%d_%@", count, Fmt.bytes(bytes)))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.danger)
            .disabled(count == 0)
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 52))
                .foregroundStyle(Theme.gradient)
            Text(title).font(.title3.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
