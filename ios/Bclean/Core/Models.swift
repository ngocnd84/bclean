import Photos
import SwiftUI

enum CleanCategory: String, CaseIterable, Identifiable, Hashable {
    case duplicates, similar, screenshots, blurry, videos, livePhotos

    var id: String { rawValue }
    var title: String { L("cat_\(rawValue)") }
    var subtitle: String { L("cat_\(rawValue)_sub") }
    var isGrouped: Bool { self == .duplicates || self == .similar }

    var systemImage: String {
        switch self {
        case .duplicates: return "square.on.square"
        case .similar: return "photo.stack"
        case .screenshots: return "iphone"
        case .blurry: return "camera.filters"
        case .videos: return "film.stack"
        case .livePhotos: return "livephoto"
        }
    }

    var color: Color {
        switch self {
        case .duplicates: return .orange
        case .similar: return .purple
        case .screenshots: return .blue
        case .blurry: return .gray
        case .videos: return .pink
        case .livePhotos: return .teal
        }
    }
}

struct MediaItem: Identifiable, Hashable {
    let id: String
    let asset: PHAsset
    /// Tổng dung lượng các file gốc của ảnh/video
    let bytes: Int64
    /// Riêng phần video đi kèm của Live Photo (phần tiết kiệm được khi chuyển ảnh tĩnh)
    let liveBytes: Int64
    /// Độ nét (phương sai Laplacian). -1 = chưa đo được
    let sharpness: Double

    init(asset: PHAsset, bytes: Int64, liveBytes: Int64 = 0, sharpness: Double = -1) {
        self.id = asset.localIdentifier
        self.asset = asset
        self.bytes = bytes
        self.liveBytes = liveBytes
        self.sharpness = sharpness
    }

    /// Tạo nhanh từ PHAsset (đọc dung lượng đồng bộ — chỉ dùng cho vài trăm mục)
    static func from(_ asset: PHAsset) -> MediaItem {
        let s = AssetSizeReader.sizes(for: asset)
        return MediaItem(asset: asset, bytes: s.total, liveBytes: s.liveVideo)
    }

    var isVideo: Bool { asset.mediaType == .video }
    var creationDate: Date? { asset.creationDate }

    static func == (lhs: MediaItem, rhs: MediaItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct MediaGroup: Identifiable {
    var items: [MediaItem]   // phần tử đầu tiên luôn là ảnh "tốt nhất"
    var id: String { items.first?.id ?? UUID().uuidString }
    var best: MediaItem? { items.first }
    var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    /// Dung lượng giải phóng được nếu giữ lại ảnh tốt nhất
    var reclaimableBytes: Int64 { items.dropFirst().reduce(0) { $0 + $1.bytes } }

    /// Chọn ảnh tốt nhất: yêu thích > đã chỉnh sửa > nét nhất > độ phân giải cao nhất
    static func make(_ raw: [MediaItem]) -> MediaGroup {
        guard let best = raw.max(by: { score($0) < score($1) }) else { return MediaGroup(items: []) }
        let rest = raw.filter { $0.id != best.id }
            .sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
        return MediaGroup(items: [best] + rest)
    }

    static func score(_ m: MediaItem) -> Double {
        var s = 0.0
        if m.asset.isFavorite { s += 10_000_000 }
        if m.asset.hasAdjustments { s += 1_000_000 }
        s += max(0, m.sharpness) * 10
        s += Double(m.asset.pixelWidth) * Double(m.asset.pixelHeight) / 10_000
        return s
    }
}

struct ScanResult {
    var duplicates: [MediaGroup] = []
    var similar: [MediaGroup] = []
    var screenshots: [MediaItem] = []
    var blurry: [MediaItem] = []
    var videos: [MediaItem] = []
    var livePhotos: [MediaItem] = []
    var totalPhotos = 0
    var totalVideos = 0
    var libraryBytes: Int64 = 0
    var scannedAt: Date?

    func groups(for c: CleanCategory) -> [MediaGroup] {
        switch c {
        case .duplicates: return duplicates
        case .similar: return similar
        default: return []
        }
    }

    func items(for c: CleanCategory) -> [MediaItem] {
        switch c {
        case .duplicates: return duplicates.flatMap(\.items)
        case .similar: return similar.flatMap(\.items)
        case .screenshots: return screenshots
        case .blurry: return blurry
        case .videos: return videos
        case .livePhotos: return livePhotos
        }
    }

    func count(for c: CleanCategory) -> Int {
        switch c {
        case .duplicates, .similar: return groups(for: c).reduce(0) { $0 + $1.items.count - 1 }
        case .videos: return videos.filter { $0.bytes >= AppConfig.largeVideoBytes }.count
        default: return items(for: c).count
        }
    }

    /// Dung lượng có thể giải phóng của từng nhóm
    func reclaimable(for c: CleanCategory) -> Int64 {
        switch c {
        case .duplicates, .similar: return groups(for: c).reduce(0) { $0 + $1.reclaimableBytes }
        case .livePhotos: return livePhotos.reduce(0) { $0 + $1.liveBytes }
        case .videos: return videos.filter { $0.bytes >= AppConfig.largeVideoBytes }.reduce(0) { $0 + $1.bytes }
        default: return items(for: c).reduce(0) { $0 + $1.bytes }
        }
    }

    /// Ước tính "an toàn" để hiển thị trên trang chủ: trùng + giống + screenshot + phần video của Live Photo
    var headlineReclaimable: Int64 {
        reclaimable(for: .duplicates) + reclaimable(for: .similar)
            + reclaimable(for: .screenshots) + reclaimable(for: .livePhotos)
    }

    mutating func remove(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        func clean(_ groups: [MediaGroup]) -> [MediaGroup] {
            groups.compactMap { g in
                let left = g.items.filter { !ids.contains($0.id) }
                guard left.count >= 2 else { return nil }
                // Nếu lỡ xoá ảnh tốt nhất thì chọn lại
                return left.first?.id == g.items.first?.id ? MediaGroup(items: left) : MediaGroup.make(left)
            }
        }
        duplicates = clean(duplicates)
        similar = clean(similar)
        screenshots.removeAll { ids.contains($0.id) }
        blurry.removeAll { ids.contains($0.id) }
        videos.removeAll { ids.contains($0.id) }
        livePhotos.removeAll { ids.contains($0.id) }
    }
}

enum BcleanError: LocalizedError {
    case videoUnavailable
    case exportFailed
    case resourceMissing

    var errorDescription: String? {
        switch self {
        case .videoUnavailable: return L("err_video_unavailable")
        case .exportFailed: return L("err_export_failed")
        case .resourceMissing: return L("err_resource_missing")
        }
    }
}

struct DeviceStorage {
    let total: Int64
    let available: Int64
    var used: Int64 { max(0, total - available) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func current() -> DeviceStorage? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey,
                                                        .volumeAvailableCapacityForImportantUsageKey]),
              let total = v.volumeTotalCapacity,
              let available = v.volumeAvailableCapacityForImportantUsage else { return nil }
        return DeviceStorage(total: Int64(total), available: available)
    }
}

enum AssetSizeReader {
    /// Đọc dung lượng thật từ PHAssetResource (không tải file về).
    static func sizes(for asset: PHAsset) -> (total: Int64, liveVideo: Int64) {
        var total: Int64 = 0
        var live: Int64 = 0
        for r in PHAssetResource.assetResources(for: asset) {
            let size = (r.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0
            total += size
            if r.type == .pairedVideo || r.type == .fullSizePairedVideo { live += size }
        }
        return (total, live)
    }
}
