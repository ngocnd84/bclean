import SwiftUI

/// Tab "Video": danh sách video theo dung lượng, chọn để xoá hoặc chạm để nén.
struct VideoListView: View {
    var body: some View {
        NavigationStack {
            VideoListContent()
        }
    }
}

struct VideoListContent: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var store: StoreManager
    @StateObject private var flow = DeletionFlow()
    @State private var selected = Set<String>()
    @State private var compressing: MediaItem?

    var body: some View {
        let videos = library.result.videos
        Group {
            if library.isScanning && videos.isEmpty {
                ProgressView(L("scanning"))
            } else if videos.isEmpty {
                EmptyStateView(icon: "film", title: L("videos_empty_title"), message: L("videos_empty_body"))
            } else {
                List {
                    Section {
                        ForEach(videos) { item in
                            row(item)
                        }
                    } header: {
                        Text(L("videos_header_%d_%@", videos.count, Fmt.bytes(videos.reduce(Int64(0)) { $0 + $1.bytes })))
                    } footer: {
                        Text(L("videos_footer"))
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(L("cat_videos"))
        .safeAreaInset(edge: .bottom) {
            if !selected.isEmpty {
                let chosen = videos.filter { selected.contains($0.id) }
                SelectionBar(count: chosen.count, bytes: chosen.reduce(Int64(0)) { $0 + $1.bytes }, onDelete: {
                    Task {
                        if await flow.delete(chosen, library: library, isPro: store.isPro) { selected.removeAll() }
                    }
                })
            }
        }
        .sheet(item: $compressing) { item in
            CompressSheet(item: item)
                .environmentObject(library)
                .environmentObject(store)
        }
        .deletionFlow(flow)
    }

    private func row(_ item: MediaItem) -> some View {
        HStack(spacing: 12) {
            Button {
                if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
            } label: {
                Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected.contains(item.id) ? Theme.danger : Color.secondary)
            }
            .buttonStyle(.borderless)

            ThumbnailView(asset: item.asset, side: 64)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(Fmt.bytes(item.bytes)).font(.headline)
                Text("\(Fmt.duration(item.asset.duration)) · \(Fmt.date(item.creationDate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                compressing = item
            } label: {
                Label(L("compress"), systemImage: "arrow.down.right.and.arrow.up.left")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .padding(8)
                    .background(Theme.teal.opacity(0.14), in: Circle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.teal)
            .accessibilityLabel(L("compress"))
        }
        .padding(.vertical, 2)
    }
}

struct CompressSheet: View {
    let item: MediaItem
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var store: StoreManager
    @Environment(\.dismiss) private var dismiss

    @State private var level: CompressionLevel = .balanced
    @State private var deleteOriginal = true
    @State private var working = false
    @State private var progress: Double = 0
    @State private var resultText: String?
    @State private var errorText: String?
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        ThumbnailView(asset: item.asset, side: 90)
                            .frame(width: 90, height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("original_%@", Fmt.bytes(item.bytes))).font(.headline)
                            Text("\(item.asset.pixelWidth)×\(item.asset.pixelHeight) · \(Fmt.duration(item.asset.duration))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Picker(L("compress_level"), selection: $level) {
                        ForEach(CompressionLevel.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(level.detail).font(.footnote).foregroundStyle(.secondary)
                    HStack {
                        Text(L("estimated_after"))
                        Spacer()
                        Text("~" + Fmt.bytes(level.estimate(for: item))).bold()
                    }
                    Toggle(L("delete_original"), isOn: $deleteOriginal)
                } footer: {
                    Text(L("compress_footer"))
                }

                if working {
                    Section {
                        ProgressView(value: progress) { Text(L("compressing")) }
                    }
                }
                if let resultText {
                    Section { Label(resultText, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.teal) }
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(Theme.danger) }
                }

                Section {
                    Button {
                        Task { await run() }
                    } label: {
                        Text(resultText == nil ? L("compress_now") : L("done"))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(working)
                }
            }
            .navigationTitle(L("compress_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("close")) { dismiss() }.disabled(working)
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(reason: L("quota_compress_used_up")).environmentObject(store)
            }
        }
        .interactiveDismissDisabled(working)
    }

    private func run() async {
        if resultText != nil { dismiss(); return }
        working = true
        errorText = nil
        progress = 0
        let outcome = await library.compress(item, level: level, deleteOriginal: deleteOriginal, isPro: store.isPro) { p in
            progress = p
        }
        working = false
        switch outcome {
        case .done(let newBytes, let saved):
            resultText = L("compress_done_%@_%@", Fmt.bytes(newBytes), Fmt.bytes(saved))
        case .needsPro:
            showPaywall = true
            Analytics.log("paywall_view", ["source": "compress"])
        case .notSmaller:
            errorText = L("compress_not_smaller")
        case .cancelled:
            break
        case .failed(let message):
            errorText = message
        }
    }
}
