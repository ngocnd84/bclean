import CoreGraphics
import Photos
import UIKit
import Vision

/// Phân tích ảnh hoàn toàn trên máy: dHash (ảnh trùng), độ nét (ảnh mờ), Vision feature print (ảnh giống).
struct ImageAnalyzer {
    private let manager = PHImageManager.default()

    /// Lấy thumbnail nhỏ, đồng bộ, KHÔNG tải từ iCloud. Gọi từ luồng nền.
    func thumbnail(for asset: PHAsset, side: CGFloat = 256) -> CGImage? {
        let opts = PHImageRequestOptions()
        opts.isSynchronous = true
        opts.deliveryMode = .highQualityFormat
        opts.resizeMode = .fast
        opts.isNetworkAccessAllowed = false
        var result: CGImage?
        manager.requestImage(for: asset,
                             targetSize: CGSize(width: side, height: side),
                             contentMode: .aspectFit,
                             options: opts) { image, _ in
            result = image?.cgImage
        }
        return result
    }

    // MARK: - dHash 64-bit

    static func dHash(_ image: CGImage) -> UInt64? {
        let w = 9, h = 8
        guard let px = grayscale(image, width: w, height: h) else { return nil }
        var hash: UInt64 = 0
        var bit: UInt64 = 0
        for y in 0..<h {
            for x in 0..<(w - 1) {
                if px[y * w + x] > px[y * w + x + 1] { hash |= (UInt64(1) << bit) }
                bit += 1
            }
        }
        return hash
    }

    // MARK: - Độ nét (phương sai Laplacian)

    static func sharpness(_ image: CGImage) -> Double {
        let n = 128
        guard let p = grayscale(image, width: n, height: n) else { return -1 }
        var sum = 0.0, sumSq = 0.0, count = 0.0
        for y in 1..<(n - 1) {
            for x in 1..<(n - 1) {
                let i = y * n + x
                let lap = Double(p[i - n]) + Double(p[i + n]) + Double(p[i - 1]) + Double(p[i + 1]) - 4 * Double(p[i])
                sum += lap
                sumSq += lap * lap
                count += 1
            }
        }
        let mean = sum / count
        return sumSq / count - mean * mean
    }

    // MARK: - Vision feature print

    static func featurePrint(_ image: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            return nil
        }
    }

    static func distance(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Float? {
        var d: Float = 0
        do {
            try a.computeDistance(&d, to: b)
            return d
        } catch {
            return nil
        }
    }

    /// Ngưỡng phụ thuộc phiên bản model Vision trên máy
    static var similarThreshold: Float {
        VNGenerateImageFeaturePrintRequest().revision >= 2
            ? AppConfig.similarThresholdRev2
            : AppConfig.similarThresholdRev1
    }

    // MARK: - Helpers

    static func grayscale(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var buffer = [UInt8](repeating: 0, count: width * height)
        let space = CGColorSpaceCreateDeviceGray()
        let ok: Bool = buffer.withUnsafeMutableBytes { ptr -> Bool in
            guard let ctx = CGContext(data: ptr.baseAddress,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: width,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return ok ? buffer : nil
    }
}

/// Bộ nhớ đệm kết quả phân tích → lần quét sau nhanh gấp nhiều lần.
struct AnalysisRecord: Codable {
    var mod: Double
    var bytes: Int64
    var liveBytes: Int64
    var hashBits: Int64?
    var sharpness: Double

    var hash: UInt64? { hashBits.map { UInt64(bitPattern: $0) } }
}

final class AnalysisCache {
    private(set) var entries: [String: AnalysisRecord]

    private init(entries: [String: AnalysisRecord]) {
        self.entries = entries
    }

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("bclean-analysis-v1.json")
    }

    static func load() -> AnalysisCache {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONDecoder().decode([String: AnalysisRecord].self, from: data) else {
            return AnalysisCache(entries: [:])
        }
        return AnalysisCache(entries: entries)
    }

    static func modKey(_ asset: PHAsset) -> Double {
        asset.modificationDate?.timeIntervalSince1970 ?? 0
    }

    func record(for asset: PHAsset) -> AnalysisRecord? {
        guard let r = entries[asset.localIdentifier], r.mod == Self.modKey(asset) else { return nil }
        return r
    }

    func set(_ record: AnalysisRecord, for asset: PHAsset) {
        entries[asset.localIdentifier] = record
    }

    func save(keeping ids: Set<String>) {
        entries = entries.filter { ids.contains($0.key) }
        let url = Self.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
