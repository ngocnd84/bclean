import Photos
import SwiftUI

enum DeleteOutcome {
    case done(count: Int, bytes: Int64)
    case needsPro(remaining: Int)
    case cancelled
    case failed(String)
}

enum CompressOutcome {
    case done(newBytes: Int64, saved: Int64)
    case needsPro
    case notSmaller
    case cancelled
    case failed(String)
}

/// Trạng thái thư viện ảnh + kết quả quét, dùng chung cho toàn app.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var authStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var isScanning = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var progressText = ""
    @Published private(set) var result = ScanResult()
    @Published private(set) var deviceStorage = DeviceStorage.current()

    private var scanTask: Task<Void, Never>?

    var hasAccess: Bool { authStatus == .authorized || authStatus == .limited }
    var isLimited: Bool { authStatus == .limited }
    var isDenied: Bool { authStatus == .denied || authStatus == .restricted }

    // MARK: - Quyền truy cập

    func refreshAuth() {
        authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func refreshDeviceStorage() {
        deviceStorage = DeviceStorage.current()
    }

    func requestAccess() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authStatus = status
        Analytics.log("permission_result", ["status": status.rawValue])
    }

    // MARK: - Quét

    func startScanIfNeeded() {
        if result.scannedAt == nil && !isScanning { startScan() }
    }

    func startScan() {
        guard hasAccess, !isScanning else { return }
        isScanning = true
        progress = 0
        progressText = L("scan_preparing")
        let started = Date()

        let report: LibraryScanner.Progress = { [weak self] p, text in
            Task { @MainActor [weak self] in
                guard let self, self.isScanning else { return }
                self.progress = max(self.progress, p)
                self.progressText = text
            }
        }

        scanTask = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) { () -> ScanResult in
                await LibraryScanner().run(progress: report)
            }
            let r = await worker.value
            guard let self else { return }
            self.result = r
            self.isScanning = false
            self.progress = 1
            self.deviceStorage = DeviceStorage.current()
            Analytics.log("scan_completed", [
                "seconds": Int(Date().timeIntervalSince(started)),
                "photos": r.totalPhotos,
                "videos": r.totalVideos,
                "dup_groups": r.duplicates.count,
                "similar_groups": r.similar.count,
                "reclaimable_mb": r.headlineReclaimable / 1_048_576
            ])
        }
    }

    // MARK: - Xoá

    func delete(_ items: [MediaItem], isPro: Bool) async -> DeleteOutcome {
        guard !items.isEmpty else { return .cancelled }
        if !isPro && !FreeQuota.deletes.canUse(items.count) {
            Analytics.log("quota_hit", ["type": "delete", "wanted": items.count])
            return .needsPro(remaining: FreeQuota.deletes.remaining)
        }
        do {
            try await PhotoActions.delete(items.map(\.asset))
            if !isPro { FreeQuota.deletes.consume(items.count) }
            let bytes = items.reduce(Int64(0)) { $0 + $1.bytes }
            result.remove(ids: Set(items.map(\.id)))
            Stats.add(bytes: bytes, items: items.count)
            refreshDeviceStorage()
            Analytics.log("delete_done", ["count": items.count, "mb": bytes / 1_048_576, "pro": isPro])
            return .done(count: items.count, bytes: bytes)
        } catch {
            if PhotoActions.isUserCancel(error) { return .cancelled }
            return .failed(error.localizedDescription)
        }
    }

    func convertLive(_ items: [MediaItem], isPro: Bool) async -> DeleteOutcome {
        guard !items.isEmpty else { return .cancelled }
        if !isPro && !FreeQuota.deletes.canUse(items.count) {
            return .needsPro(remaining: FreeQuota.deletes.remaining)
        }
        do {
            let n = try await PhotoActions.convertLiveToStill(items.map(\.asset))
            if !isPro { FreeQuota.deletes.consume(n) }
            let saved = items.reduce(Int64(0)) { $0 + $1.liveBytes }
            result.remove(ids: Set(items.map(\.id)))
            Stats.add(bytes: saved, items: 0)
            Analytics.log("live_converted", ["count": n, "mb": saved / 1_048_576])
            return .done(count: n, bytes: saved)
        } catch {
            if PhotoActions.isUserCancel(error) { return .cancelled }
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Nén video

    func compress(_ item: MediaItem,
                  level: CompressionLevel,
                  deleteOriginal: Bool,
                  isPro: Bool,
                  progress: @escaping (Double) -> Void) async -> CompressOutcome {
        if !isPro && !FreeQuota.compress.canUse(1) {
            Analytics.log("quota_hit", ["type": "compress"])
            return .needsPro
        }
        var tempURL: URL?
        do {
            let url = try await VideoCompressor.export(item.asset, level: level) { p in
                Task { @MainActor in progress(p) }
            }
            tempURL = url
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let newBytes = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            guard newBytes > 0, newBytes < item.bytes else {
                try? FileManager.default.removeItem(at: url)
                return .notSmaller
            }
            try await PhotoActions.saveVideo(url, like: item.asset, deleteOriginal: deleteOriginal)
            if !isPro { FreeQuota.compress.consume(1) }
            let saved = item.bytes - newBytes
            if deleteOriginal {
                result.remove(ids: [item.id])
                Stats.add(bytes: saved, items: 0)
            }
            Analytics.log("video_compressed", ["level": level.rawValue, "saved_mb": saved / 1_048_576])
            return .done(newBytes: newBytes, saved: saved)
        } catch {
            if let tempURL { try? FileManager.default.removeItem(at: tempURL) }
            if PhotoActions.isUserCancel(error) { return .cancelled }
            return .failed(error.localizedDescription)
        }
    }

    func resetCache() {
        AnalysisCache.clear()
        result = ScanResult()
    }
}
