import Photos
import SwiftUI

/// Tab "Lướt ảnh": dọn theo từng tháng, vuốt trái để xoá, phải để giữ.
struct SwipeMonthsView: View {
    @EnvironmentObject var library: LibraryStore
    @State private var months: [MonthBucket] = []
    @State private var loading = true
    @State private var refreshToken = 0

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView()
                } else if months.isEmpty {
                    EmptyStateView(icon: "photo", title: L("swipe_empty_title"), message: L("swipe_empty_body"))
                } else {
                    List {
                        Section {
                            ForEach(months) { m in
                                NavigationLink(value: m) {
                                    monthRow(m)
                                }
                            }
                        } header: {
                            Text(L("swipe_header"))
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(L("tab_swipe"))
            .navigationDestination(for: MonthBucket.self) { m in
                SwipeSessionView(bucket: m) { refreshToken += 1 }
            }
            .task(id: refreshToken) { await load() }
        }
    }

    private func monthRow(_ m: MonthBucket) -> some View {
        let done = min(SwipeProgress.load(m.id), m.assets.count)
        return HStack(spacing: 12) {
            if let first = m.assets.first {
                ThumbnailView(asset: first, side: 52)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(m.title).font(.headline)
                Text(L("swipe_month_count_%d", m.assets.count)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if done >= m.assets.count {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.teal)
            } else if done > 0 {
                Text("\(done)/\(m.assets.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }

    private func load() async {
        guard library.hasAccess else { loading = false; return }
        let built = await Task.detached(priority: .userInitiated) { MonthBucket.build() }.value
        months = built
        loading = false
    }
}

struct SwipeSessionView: View {
    let bucket: MonthBucket
    var onChanged: () -> Void = {}

    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var store: StoreManager
    @StateObject private var flow = DeletionFlow()
    @State private var index = 0
    @State private var marked: [PHAsset] = []
    @State private var history: [Bool] = []   // true = đánh dấu xoá
    @State private var drag: CGSize = .zero
    @State private var showReview = false
    @State private var didLoad = false

    private var assets: [PHAsset] { bucket.assets }
    private var finished: Bool { index >= assets.count }

    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: Double(min(index, assets.count)), total: Double(max(assets.count, 1)))
                .padding(.horizontal)
            Text("\(min(index + 1, assets.count)) / \(assets.count) · " + L("marked_%d", marked.count))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)

            ZStack {
                if finished {
                    EmptyStateView(icon: "checkmark.seal.fill",
                                   title: L("swipe_finished_title"),
                                   message: marked.isEmpty ? L("swipe_finished_none") : L("swipe_finished_body_%d", marked.count))
                } else {
                    if index + 1 < assets.count {
                        card(assets[index + 1])
                            .scaleEffect(0.95)
                            .opacity(0.6)
                    }
                    card(assets[index])
                        .offset(drag)
                        .rotationEffect(.degrees(Double(drag.width) / 22))
                        .overlay(alignment: .topLeading) { stamp(L("stamp_delete"), color: Theme.danger, visible: drag.width < -40) }
                        .overlay(alignment: .topTrailing) { stamp(L("stamp_keep"), color: Theme.teal, visible: drag.width > 40) }
                        .gesture(
                            DragGesture()
                                .onChanged { drag = $0.translation }
                                .onEnded { v in
                                    if v.translation.width < -110 { decide(delete: true) }
                                    else if v.translation.width > 110 { decide(delete: false) }
                                    else { withAnimation(.spring()) { drag = .zero } }
                                }
                        )
                        .id(assets[index].localIdentifier)
                        .transition(.opacity)
                }
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal)

            HStack(spacing: 28) {
                circleButton("xmark", color: Theme.danger, label: L("stamp_delete")) { decide(delete: true) }
                    .disabled(finished)
                circleButton("arrow.uturn.backward", color: .gray, label: L("undo"), small: true) { undo() }
                    .disabled(history.isEmpty)
                circleButton("heart.fill", color: Theme.teal, label: L("stamp_keep")) { decide(delete: false) }
                    .disabled(finished)
            }

            Button {
                if marked.isEmpty { commitProgress() } else { showReview = true }
            } label: {
                Text(marked.isEmpty ? L("swipe_save_progress") : L("review_delete_%d", marked.count))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(marked.isEmpty ? Theme.teal : Theme.danger)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .navigationTitle(bucket.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(L("swipe_restart")) {
                        SwipeProgress.reset(bucket.id)
                        index = 0; marked = []; history = []
                        onChanged()
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            let saved = SwipeProgress.load(bucket.id)
            index = saved >= assets.count ? 0 : saved
        }
        .sheet(isPresented: $showReview) {
            ReviewDeleteView(assets: marked) { finalList in
                Task {
                    let items = finalList.map { MediaItem.from($0) }
                    if await flow.delete(items, library: library, isPro: store.isPro) {
                        marked.removeAll()
                        history.removeAll()
                        commitProgress()
                    }
                }
            }
            .environmentObject(store)
        }
        .deletionFlow(flow)
    }

    private func card(_ asset: PHAsset) -> some View {
        ThumbnailView(asset: asset, side: 700, fit: true, allowNetwork: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 6) {
                    if asset.mediaType == .video {
                        Image(systemName: "play.fill")
                        Text(Fmt.duration(asset.duration))
                    }
                    Text(Fmt.date(asset.creationDate))
                }
                .font(.caption.bold())
                .padding(8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(12)
            }
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    private func stamp(_ text: String, color: Color, visible: Bool) -> some View {
        Text(text)
            .font(.title.weight(.heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 4))
            .rotationEffect(.degrees(visible && color == Theme.danger ? 12 : -12))
            .padding(24)
            .opacity(visible ? 1 : 0)
    }

    private func circleButton(_ icon: String, color: Color, label: String, small: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(small ? .title3.bold() : .title.bold())
                .foregroundStyle(color)
                .frame(width: small ? 52 : 68, height: small ? 52 : 68)
                .background(Color(.secondarySystemBackground), in: Circle())
        }
        .accessibilityLabel(label)
    }

    private func decide(delete: Bool) {
        guard !finished else { return }
        if delete { marked.append(assets[index]) }
        history.append(delete)
        withAnimation(.easeOut(duration: 0.18)) {
            drag = .zero
            index += 1
        }
    }

    private func undo() {
        guard let last = history.popLast(), index > 0 else { return }
        if last { _ = marked.popLast() }
        withAnimation { index -= 1 }
    }

    private func commitProgress() {
        SwipeProgress.save(bucket.id, index)
        onChanged()
        Analytics.log("swipe_progress", ["month": bucket.id, "index": index])
    }
}

/// Xem lại trước khi xoá — bỏ chọn những ảnh muốn giữ
struct ReviewDeleteView: View {
    let assets: [PHAsset]
    let onConfirm: ([PHAsset]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var keep = Set<String>()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(L("review_hint")).font(.footnote).foregroundStyle(.secondary).padding(.horizontal).padding(.top, 8)
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(assets, id: \.localIdentifier) { a in
                        let isDeleting = !keep.contains(a.localIdentifier)
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(ThumbnailView(asset: a, side: 140))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: isDeleting ? "trash.circle.fill" : "heart.circle.fill")
                                    .font(.title2)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, isDeleting ? Theme.danger : Theme.teal)
                                    .padding(6)
                            }
                            .opacity(isDeleting ? 1 : 0.5)
                            .onTapGesture {
                                if keep.contains(a.localIdentifier) { keep.remove(a.localIdentifier) } else { keep.insert(a.localIdentifier) }
                            }
                    }
                }
                .padding(4)
                .padding(.bottom, 100)
            }
            .navigationTitle(L("review_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("close")) { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                let toDelete = assets.filter { !keep.contains($0.localIdentifier) }
                Button {
                    dismiss()
                    onConfirm(toDelete)
                } label: {
                    Text(L("delete_count_%d", toDelete.count))
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.danger)
                .disabled(toDelete.isEmpty)
                .padding()
                .background(.bar)
            }
        }
    }
}
