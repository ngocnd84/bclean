import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var store: StoreManager
    @Environment(\.openURL) private var openURL
    @State private var showPaywall = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    StorageCard(storage: library.deviceStorage,
                                reclaimable: library.result.headlineReclaimable,
                                scanned: library.result.scannedAt != nil)

                    if library.isLimited { limitedBanner }

                    if library.isScanning {
                        ScanProgressCard(progress: library.progress, text: library.progressText)
                    } else if library.result.scannedAt == nil {
                        Button { library.startScan() } label: {
                            Label(L("scan_start"), systemImage: "sparkle.magnifyingglass")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(CleanCategory.allCases) { c in
                            NavigationLink(value: c) {
                                CategoryCard(category: c,
                                             count: library.result.count(for: c),
                                             bytes: library.result.reclaimable(for: c),
                                             loading: library.isScanning)
                            }
                            .buttonStyle(.plain)
                            .disabled(library.isScanning)
                        }
                    }

                    if !store.isPro {
                        ProBanner { showPaywall = true; Analytics.log("paywall_view", ["source": "banner"]) }
                    }

                    if Stats.freedBytes > 0 {
                        Label(L("stats_freed_%@_%d", Fmt.bytes(Stats.freedBytes), Stats.deletedCount),
                              systemImage: "leaf.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding()
            }
            .background(Theme.pageBackground)
            .navigationTitle("Bclean")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if library.result.scannedAt != nil && !library.isScanning {
                        Button { library.startScan() } label: { Image(systemName: "arrow.clockwise") }
                            .accessibilityLabel(L("scan_again"))
                    }
                }
            }
            .navigationDestination(for: CleanCategory.self) { CategoryDetailView(category: $0) }
            .onAppear { library.startScanIfNeeded() }
            .sheet(isPresented: $showPaywall) { PaywallView(reason: nil) }
        }
    }

    private var limitedBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(L("limited_title")).font(.subheadline.bold())
                Text(L("limited_body")).font(.footnote).foregroundStyle(.secondary)
                Button(L("open_settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(.footnote.bold())
            }
            Spacer(minLength: 0)
        }
        .padding()
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct StorageCard: View {
    let storage: DeviceStorage?
    let reclaimable: Int64
    let scanned: Bool

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.25), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: storage?.usedFraction ?? 0)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int(((storage?.usedFraction ?? 0) * 100).rounded()))%")
                        .font(.title2.bold())
                    Text(L("used")).font(.caption2)
                }
            }
            .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: 6) {
                if let storage {
                    Text(L("storage_used_%@_%@", Fmt.bytes(storage.used), Fmt.bytes(storage.total)))
                        .font(.subheadline.weight(.semibold))
                    Text(L("storage_free_%@", Fmt.bytes(storage.available)))
                        .font(.footnote)
                        .opacity(0.9)
                }
                Divider().overlay(Color.white.opacity(0.4))
                Text(scanned ? L("can_free") : L("scan_to_find"))
                    .font(.footnote)
                    .opacity(0.9)
                if scanned {
                    Text(Fmt.bytes(reclaimable))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct ScanProgressCard: View {
    let progress: Double
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("scanning")).font(.headline)
                Spacer()
                Text("\(Int(progress * 100))%").font(.headline.monospacedDigit())
            }
            ProgressView(value: progress)
            Text(text).font(.footnote).foregroundStyle(.secondary)
            Text(L("scan_private_note")).font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct CategoryCard: View {
    let category: CleanCategory
    let count: Int
    let bytes: Int64
    let loading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: category.systemImage)
                    .font(.title3)
                    .foregroundStyle(category.color)
                    .frame(width: 40, height: 40)
                    .background(category.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                Spacer()
                if loading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
                }
            }
            Text(category.title)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(loading ? " " : L("cat_count_%d_%@", count, Fmt.bytes(bytes)))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct ProBanner: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "crown.fill")
                    .font(.title2)
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("pro_banner_title")).font(.subheadline.bold())
                    Text(L("pro_banner_body_%d", FreeQuota.deletes.remaining))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding()
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}
