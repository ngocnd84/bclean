import Foundation

/// Mọi thông số kinh doanh & kỹ thuật có thể chỉnh nằm ở đây.
enum AppConfig {
    // MARK: - In-App Purchase (phải khớp 100% với App Store Connect)
    static let weeklyID = "vn.bentic.bclean.weekly"
    static let yearlyID = "vn.bentic.bclean.yearly"
    static let lifetimeID = "vn.bentic.bclean.lifetime"
    static let productOrder = [yearlyID, weeklyID, lifetimeID]

    // MARK: - Gói miễn phí (mô hình "freemium hào phóng")
    /// Số ảnh/video được xoá miễn phí mỗi ngày
    static let freeDeletesPerDay = 30
    /// Số video được nén miễn phí mỗi ngày
    static let freeCompressPerDay = 2

    // MARK: - Thuật toán (cần tinh chỉnh trên máy thật)
    /// Ảnh chụp cách nhau tối đa bao nhiêu giây thì xét "ảnh giống nhau"
    static let similarTimeWindow: TimeInterval = 90
    /// Ngưỡng khoảng cách Vision feature print (revision 1 — iOS 16)
    static let similarThresholdRev1: Float = 12.0
    /// Ngưỡng khoảng cách Vision feature print (revision 2 — iOS 17+)
    static let similarThresholdRev2: Float = 0.45
    /// Ảnh trùng: số bit khác nhau tối đa của dHash 64-bit (≤ 3)
    static let duplicateMaxHamming = 3
    /// Ảnh mờ: phương sai Laplacian dưới ngưỡng này
    static let blurThreshold: Double = 60
    /// Video từ bao nhiêu MB thì coi là "video nặng"
    static let largeVideoBytes: Int64 = 50 * 1024 * 1024

    // MARK: - Pháp lý & hỗ trợ (thay bằng domain thật trước khi nộp App Store)
    static let termsURL = URL(string: "https://bclean.vn/terms")!
    static let privacyURL = URL(string: "https://bclean.vn/privacy")!
    static let supportEmail = "support@bclean.vn"
    static let appStoreID = "0000000000" // điền sau khi tạo app trên App Store Connect
}
