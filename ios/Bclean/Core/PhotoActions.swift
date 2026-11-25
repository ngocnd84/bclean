import AVFoundation
import Photos

/// Các thao tác GHI vào thư viện ảnh. iOS luôn hiện hộp thoại xác nhận trước khi xoá.
enum PhotoActions {
    static func delete(_ assets: [PHAsset]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
    }

    /// Người dùng bấm "Không cho phép" ở hộp thoại xoá của iOS
    static func isUserCancel(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.code == 3072 || ns.code == NSUserCancelledError
    }

    /// Live Photo → ảnh tĩnh: tạo ảnh mới từ phần ảnh (giữ ngày chụp, vị trí, yêu thích), rồi xoá bản Live.
    /// Trả về số ảnh đã chuyển.
    static func convertLiveToStill(_ assets: [PHAsset]) async throws -> Int {
        var files: [(PHAsset, URL)] = []
        let tmp = FileManager.default.temporaryDirectory
        for asset in assets {
            let resources = PHAssetResource.assetResources(for: asset)
            guard let res = resources.first(where: { $0.type == .fullSizePhoto })
                    ?? resources.first(where: { $0.type == .photo }) else { continue }
            let ext = (res.originalFilename as NSString).pathExtension
            let url = tmp.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext.isEmpty ? "heic" : ext)
            let opts = PHAssetResourceRequestOptions()
            opts.isNetworkAccessAllowed = true
            try await PHAssetResourceManager.default().writeData(for: res, toFile: url, options: opts)
            files.append((asset, url))
        }
        guard !files.isEmpty else { throw BcleanError.resourceMissing }
        let prepared = files

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let move = PHAssetResourceCreationOptions()
                move.shouldMoveFile = true
                for (original, url) in prepared {
                    let req = PHAssetCreationRequest.forAsset()
                    req.addResource(with: .photo, fileURL: url, options: move)
                    req.creationDate = original.creationDate
                    req.location = original.location
                    req.isFavorite = original.isFavorite
                }
                PHAssetChangeRequest.deleteAssets(prepared.map { $0.0 } as NSArray)
            }
        } catch {
            prepared.forEach { try? FileManager.default.removeItem(at: $0.1) }
            throw error
        }
        return prepared.count
    }

    /// Lưu video đã nén vào thư viện (giữ ngày, vị trí, yêu thích) và tuỳ chọn xoá bản gốc.
    static func saveVideo(_ url: URL, like original: PHAsset, deleteOriginal: Bool) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let move = PHAssetResourceCreationOptions()
            move.shouldMoveFile = true
            let req = PHAssetCreationRequest.forAsset()
            req.addResource(with: .video, fileURL: url, options: move)
            req.creationDate = original.creationDate
            req.location = original.location
            req.isFavorite = original.isFavorite
            if deleteOriginal {
                PHAssetChangeRequest.deleteAssets([original] as NSArray)
            }
        }
    }
}

enum CompressionLevel: String, CaseIterable, Identifiable {
    case light, balanced, strong

    var id: String { rawValue }
    var title: String { L("compress_\(rawValue)") }
    var detail: String { L("compress_\(rawValue)_detail") }

    var preset: String {
        switch self {
        case .light: return AVAssetExportPresetHEVC1920x1080
        case .balanced: return AVAssetExportPreset1280x720
        case .strong: return AVAssetExportPreset960x540
        }
    }

    /// Bitrate ước tính (bit/giây) để dự báo dung lượng mà không cần tải video
    var estimatedBitrate: Double {
        switch self {
        case .light: return 7_000_000
        case .balanced: return 4_500_000
        case .strong: return 2_500_000
        }
    }

    func estimate(for item: MediaItem) -> Int64 {
        let est = Int64(item.asset.duration * (estimatedBitrate + 128_000) / 8)
        return min(est, item.bytes)
    }
}

enum VideoCompressor {
    static func loadAVAsset(_ asset: PHAsset) async throws -> AVAsset {
        try await withCheckedThrowingContinuation { cont in
            let opts = PHVideoRequestOptions()
            opts.isNetworkAccessAllowed = true
            opts.deliveryMode = .highQualityFormat
            opts.version = .current
            PHImageManager.default().requestAVAsset(forVideo: asset, options: opts) { av, _, _ in
                if let av {
                    cont.resume(returning: av)
                } else {
                    cont.resume(throwing: BcleanError.videoUnavailable)
                }
            }
        }
    }

    /// Nén video ra file tạm .mp4. `progress` nhận giá trị 0…1.
    static func export(_ asset: PHAsset,
                       level: CompressionLevel,
                       progress: @escaping (Double) -> Void) async throws -> URL {
        let av = try await loadAVAsset(asset)
        guard let session = AVAssetExportSession(asset: av, presetName: level.preset) else {
            throw BcleanError.exportFailed
        }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        session.outputURL = out
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        let poller = Task.detached {
            while !Task.isCancelled {
                progress(Double(session.progress))
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        await session.export()
        poller.cancel()

        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: out)
            throw session.error ?? BcleanError.exportFailed
        }
        progress(1)
        return out
    }
}

/// Chia thư viện theo tháng cho chế độ "Lướt ảnh".
struct MonthBucket: Identifiable, Hashable {
    let id: String          // yyyy-MM
    let title: String
    let assets: [PHAsset]

    static func == (l: MonthBucket, r: MonthBucket) -> Bool { l.id == r.id && l.assets.count == r.assets.count }
    func hash(into h: inout Hasher) { h.combine(id) }

    static func build() -> [MonthBucket] {
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.predicate = NSPredicate(format: "mediaType == %d || mediaType == %d",
                                     PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        let cal = Calendar.current
        var order: [String] = []
        var map: [String: (Date, [PHAsset])] = [:]
        PHAsset.fetchAssets(with: opts).enumerateObjects { a, _, _ in
            let date = a.creationDate ?? Date(timeIntervalSince1970: 0)
            let c = cal.dateComponents([.year, .month], from: date)
            let key = String(format: "%04ld-%02ld", c.year ?? 0, c.month ?? 0)
            if map[key] == nil {
                order.append(key)
                map[key] = (date, [])
            }
            map[key]?.1.append(a)
        }
        return order.compactMap { key in
            guard let (date, assets) = map[key] else { return nil }
            return MonthBucket(id: key, title: Fmt.monthTitle(date), assets: assets)
        }
    }
}

/// Ghi nhớ đã lướt tới đâu trong mỗi tháng
enum SwipeProgress {
    static func load(_ id: String) -> Int { UserDefaults.standard.integer(forKey: "swipe_\(id)") }
    static func save(_ id: String, _ index: Int) { UserDefaults.standard.set(index, forKey: "swipe_\(id)") }
    static func reset(_ id: String) { UserDefaults.standard.removeObject(forKey: "swipe_\(id)") }
}
