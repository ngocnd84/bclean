import SwiftUI

struct CategoryDetailView: View {
    let category: CleanCategory

    var body: some View {
        switch category {
        case .duplicates, .similar:
            GroupedMediaView(category: category)
        case .videos:
            VideoListContent()
        default:
            MediaGridView(category: category)
        }
    }
}

// MARK: - Lưới ảnh (screenshot, ảnh mờ, Live Photo)

enum SortOrder: String, CaseIterable, Identifiable {
    case largest, oldest, newest
    var id: String { rawValue }
    var title: String { L("sort_\(rawValue)") }
}

struct MediaGridView: View {
    let category: CleanCategory
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var store: StoreManager
    @StateObject private var flow = DeletionFlow()
    @State private var selected = Set<String>()
    @State private var sort: SortOrder = .largest

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    private var items: [MediaItem] {
        let base = library.result.items(for: category)
        switch sort {
        case .largest: return base.sorted { weight($0) > weight($1) }
        case .oldest: return base.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
        case .newest: return base.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        }
    }

    private func weight(_ m: MediaItem) -> Int64 {
        category == .livePhotos ? m.liveBytes : m.bytes
    }

    private var selectedItems: [MediaItem] { items.filter { selected.contains($0.id) } }

    var body: some View {
        let list = items
        Group {
            if list.isEmpty {
                EmptyStateView(icon: "checkmark.seal.fill", title: L("empty_title"), message: L("empty_body"))
            } else {
                ScrollView {
                    Text(category.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(list) { item in
                            MediaCell(item: item, selected: selected.contains(item.id))
                                .onTapGesture { toggle(item.id) }
                                .contextMenu { Button(L("select")) { toggle(item.id) } } preview: { AssetPreview(item: item) }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 140)
                }
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker(L("sort"), selection: $sort) {
                        ForEach(SortOrder.allCases) { Text($0.title).tag($0) }
                    }
                    Button(selected.count == list.count ? L("deselect_all") : L("select_all")) {
                        selected = selected.count == list.count ? [] : Set(list.map(\.id))
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !selected.isEmpty {
                bottomBar(selectedItems)
            }
        }
        .deletionFlow(flow)
    }

    private func bottomBar(_ chosen: [MediaItem]) -> SelectionBar {
        let bytes = chosen.reduce(Int64(0)) { $0 + $1.bytes }
        guard category == .livePhotos else {
            return SelectionBar(count: chosen.count, bytes: bytes, onDelete: { delete(chosen) })
        }
        let liveBytes = chosen.reduce(Int64(0)) { $0 + $1.liveBytes }
        return SelectionBar(count: chosen.count,
                            bytes: bytes,
                            secondaryTitle: L("convert_still_%@", Fmt.bytes(liveBytes)),
                            secondaryAction: { convert(chosen) },
                            onDelete: { delete(chosen) })
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func delete(_ chosen: [MediaItem]) {
        Task {
            if await flow.delete(chosen, library: library, isPro: store.isPro) { selected.removeAll() }
        }
    }

    private func convert(_ chosen: [MediaItem]) {
        Task {
            if await flow.convertLive(chosen, library: library, isPro: store.isPro) { selected.removeAll() }
        }
    }
}

// MARK: - Nhóm ảnh trùng / giống nhau

struct GroupedMediaView: View {
    let category: CleanCategory
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var store: StoreManager
    @StateObject private var flow = DeletionFlow()
    @State private var selected = Set<String>()
    @State private var didAutoSelect = false

    private var groups: [MediaGroup] { library.result.groups(for: category) }

    var body: some View {
        let groups = self.groups
        Group {
            if groups.isEmpty {
                EmptyStateView(icon: "checkmark.seal.fill", title: L("empty_title"), message: L("empty_body"))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        Text(category.subtitle + " " + L("group_hint"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        ForEach(groups) { group in
                            groupSection(group)
                        }
                    }
                    .padding()
                    .padding(.bottom, 120)
                }
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(L("smart_select")) { autoSelect(groups) }
                    Button(L("deselect_all")) { selected.removeAll() }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .onAppear {
            if !didAutoSelect { autoSelect(groups); didAutoSelect = true }
        }
        .safeAreaInset(edge: .bottom) {
            if !selected.isEmpty {
                let chosen = groups.flatMap(\.items).filter { selected.contains($0.id) }
                SelectionBar(count: chosen.count, bytes: chosen.reduce(Int64(0)) { $0 + $1.bytes }, onDelete: {
                    Task {
                        if await flow.delete(chosen, library: library, isPro: store.isPro) {
                            selected.subtract(chosen.map(\.id))
                        }
                    }
                })
            }
        }
        .deletionFlow(flow)
    }

    private func autoSelect(_ groups: [MediaGroup]) {
        selected = Set(groups.flatMap { $0.items.dropFirst().map(\.id) })
    }

    @ViewBuilder
    private func groupSection(_ group: MediaGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("group_header_%d_%@", group.items.count, Fmt.date(group.best?.creationDate)))
                    .font(.subheadline.bold())
                Spacer()
                let allSelected = group.items.dropFirst().allSatisfy { selected.contains($0.id) }
                Button(allSelected ? L("deselect") : L("select")) {
                    let ids = group.items.dropFirst().map(\.id)
                    if allSelected { selected.subtract(ids) } else { selected.formUnion(ids) }
                }
                .font(.footnote.bold())
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                        MediaCell(item: item,
                                  selected: selected.contains(item.id),
                                  badge: index == 0 ? L("best") : nil)
                            .frame(width: 112, height: 112)
                            .onTapGesture {
                                if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                            }
                            .contextMenu { Button(L("select")) { selected.insert(item.id) } } preview: { AssetPreview(item: item) }
                    }
                }
            }
        }
        .padding(12)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
    }
}
