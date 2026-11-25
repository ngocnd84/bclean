import Foundation
import os

/// Lớp đo lường tối giản. Hiện ghi log ra Console (Xcode).
/// Khi lên App Store: thay phần thân `log` bằng TelemetryDeck / Firebase / Mixpanel.
/// Không gửi ảnh hay tên file — chỉ gửi số đếm.
enum Analytics {
    private static let logger = Logger(subsystem: "vn.bentic.bclean", category: "analytics")

    static func log(_ event: String, _ params: [String: Any] = [:]) {
        let text = params.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
        logger.info("📊 \(event, privacy: .public) \(text, privacy: .public)")
    }
}

/// Thống kê trọn đời hiển thị cho người dùng ("Bclean đã giúp bạn giải phóng ...")
enum Stats {
    private static let freedKey = "stats_freed_bytes"
    private static let deletedKey = "stats_deleted_count"

    static var freedBytes: Int64 {
        Int64(UserDefaults.standard.double(forKey: freedKey))
    }

    static var deletedCount: Int {
        UserDefaults.standard.integer(forKey: deletedKey)
    }

    static func add(bytes: Int64, items: Int) {
        let d = UserDefaults.standard
        d.set(Double(freedBytes + bytes), forKey: freedKey)
        d.set(deletedCount + items, forKey: deletedKey)
    }
}
