import Photos
import Vision

/// Quét toàn bộ thư viện ảnh và phân loại. Chạy nền, không chặn giao diện.
struct LibraryScanner {
    typealias Progress = (Double, String) -> Void

    func run(progress: @escaping Progress) async -> ScanResult {
        var out = ScanResult()
        let cache = AnalysisCache.load()
        let analyzer = ImageAnalyzer()

        // 1. Lấy danh sách ảnh & video (sắp xếp theo ngày chụp)
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        var images: [PHAsset] = []
        PHAsset.fetchAssets(with: .image, options: opts).enumerateObjects { a, _, _ in images.append(a) }
        var videos: [PHAsset] = []
        PHAsset.fetchAssets(with: .video, options: opts).enumerateObjects { a, _, _ in videos.append(a) }
        out.totalPhotos = images.count
        out.totalVideos = videos.count

        // 2. Phân tích từng ảnh (dùng cache nếu ảnh chưa đổi)
        var records = [AnalysisRecord?](repeating: nil, count: images.count)
        var todo: [Int] = []
        for (i, a) in images.enumerated() {
            if let r = cache.record(for: a) { records[i] = r } else { todo.append(i) }
        }

        let analyzeTotal = max(1, todo.count)
        var done = 0
        progress(0.02, L("scan_analyzing_%d_%d", 0, images.count))

        await withTaskGroup(of: (Int, AnalysisRecord).self) { group in
            var cursor = 0
            let maxConcurrent = 4
            while cursor < min(maxConcurrent, todo.count) {
                let idx = todo[cursor]
                let asset = images[idx]
                group.addTask { (idx, Self.analyze(asset, analyzer: analyzer)) }
                cursor += 1
            }
            while let (idx, rec) = await group.next() {
                records[idx] = rec
                done += 1
                if done % 20 == 0 {
                    let p = 0.02 + 0.63 * Double(done) / Double(analyzeTotal)
                    progress(p, L("scan_analyzing_%d_%d", images.count - todo.count + done, images.count))
                }
                if Task.isCancelled { group.cancelAll(); break }
                if cursor < todo.count {
                    let next = todo[cursor]
                    let asset = images[next]
                    group.addTask { (next, Self.analyze(asset, analyzer: analyzer)) }
                    cursor += 1
                }
            }
        }
        for (i, a) in images.enumerated() {
            if let r = records[i] { cache.set(r, for: a) }
        }

        // 3. Ảnh trùng (dHash)
        progress(0.66, L("scan_duplicates"))
        let hashes = records.map { $0?.hash }
        let aspects = images.map { Double($0.pixelWidth) / Double(max(1, $0.pixelHeight)) }
        let dupIndexGroups = DuplicateFinder.groups(hashes: hashes,
                                                    aspects: aspects,
                                                    maxHamming: AppConfig.duplicateMaxHamming)
        let inDuplicate = Set(dupIndexGroups.flatMap { $0 })

        func item(_ i: Int) -> MediaItem {
            let r = records[i]
            return MediaItem(asset: images[i],
                             bytes: r?.bytes ?? 0,
                             liveBytes: r?.liveBytes ?? 0,
                             sharpness: r?.sharpness ?? -1)
        }

        out.duplicates = dupIndexGroups
            .map { MediaGroup.make($0.map(item)) }
            .sorted { $0.reclaimableBytes > $1.reclaimableBytes }

        // 4. Ảnh giống nhau (Vision) — chỉ xét ảnh chụp liên tiếp
        progress(0.70, L("scan_similar"))
        let candidates: [Int] = images.indices.filter { i in
            !inDuplicate.contains(i)
                && images[i].creationDate != nil
                && !images[i].mediaSubtypes.contains(.photoScreenshot)
                && records[i]?.hash != nil
        }
        let dates = candidates.map { images[$0].creationDate ?? .distantPast }
        let window = AppConfig.similarTimeWindow
        let threshold = ImageAnalyzer.similarThreshold
        let needFeatures = SimilarFinder.indicesNeedingFeatures(dates: dates, window: window)
        var features: [Int: VNFeaturePrintObservation] = [:]
        var failed = Set<Int>()

        func feature(_ local: Int) -> VNFeaturePrintObservation? {
            if let f = features[local] { return f }
            if failed.contains(local) || !needFeatures.contains(local) { return nil }
            guard let cg = analyzer.thumbnail(for: images[candidates[local]], side: 256),
                  let f = ImageAnalyzer.featurePrint(cg) else {
                failed.insert(local)
                return nil
            }
            features[local] = f
            return f
        }

        let candidateCount = max(1, candidates.count)
        let simLocalGroups = SimilarFinder.groups(
            dates: dates,
            window: window,
            onProgress: { i in
                progress(0.70 + 0.22 * Double(i) / Double(candidateCount), L("scan_similar"))
            },
            isSimilar: { a, b in
                if Task.isCancelled { return false }
                guard let fa = feature(a), let fb = feature(b),
                      let d = ImageAnalyzer.distance(fa, fb) else { return false }
                return d <= threshold
            })

        out.similar = simLocalGroups
            .map { g in MediaGroup.make(g.map { item(candidates[$0]) }) }
            .sorted { $0.reclaimableBytes > $1.reclaimableBytes }

        // 5. Ảnh chụp màn hình, ảnh mờ, Live Photo
        progress(0.93, L("scan_finishing"))
        var screenshots: [MediaItem] = []
        var blurry: [MediaItem] = []
        var live: [MediaItem] = []
        var libraryBytes: Int64 = 0
        for i in images.indices {
            let m = item(i)
            libraryBytes += m.bytes
            let subtypes = images[i].mediaSubtypes
            if subtypes.contains(.photoScreenshot) {
                screenshots.append(m)
            } else if m.sharpness >= 0 && m.sharpness < AppConfig.blurThreshold && !inDuplicate.contains(i) {
                blurry.append(m)
            }
            if subtypes.contains(.photoLive) && m.liveBytes > 0 {
                live.append(m)
            }
        }
        out.screenshots = screenshots.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
        out.blurry = blurry.sorted { $0.sharpness < $1.sharpness }
        out.livePhotos = live.sorted { $0.liveBytes > $1.liveBytes }

        // 6. Video theo dung lượng
        var videoItems: [MediaItem] = []
        for v in videos {
            let bytes: Int64
            if let r = cache.record(for: v) {
                bytes = r.bytes
            } else {
                bytes = AssetSizeReader.sizes(for: v).total
                cache.set(AnalysisRecord(mod: AnalysisCache.modKey(v), bytes: bytes, liveBytes: 0,
                                         hashBits: nil, sharpness: -1), for: v)
            }
            libraryBytes += bytes
            videoItems.append(MediaItem(asset: v, bytes: bytes))
        }
        out.videos = videoItems.sorted { $0.bytes > $1.bytes }
        out.libraryBytes = libraryBytes
        out.scannedAt = Date()

        let allIDs = Set(images.map(\.localIdentifier) + videos.map(\.localIdentifier))
        cache.save(keeping: allIDs)
        progress(1, L("scan_done"))
        return out
    }

    private static func analyze(_ asset: PHAsset, analyzer: ImageAnalyzer) -> AnalysisRecord {
        let sizes = AssetSizeReader.sizes(for: asset)
        var hash: UInt64?
        var sharp = -1.0
        if let cg = analyzer.thumbnail(for: asset, side: 256) {
            hash = ImageAnalyzer.dHash(cg)
            sharp = ImageAnalyzer.sharpness(cg)
        }
        return AnalysisRecord(mod: AnalysisCache.modKey(asset),
                              bytes: sizes.total,
                              liveBytes: sizes.liveVideo,
                              hashBits: hash.map { Int64(bitPattern: $0) },
                              sharpness: sharp)
    }
}
