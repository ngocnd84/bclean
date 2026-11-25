import SwiftUI

enum Theme {
    static let accent = Color("AccentColor")
    static let teal = Color(red: 0.05, green: 0.65, blue: 0.62)
    static let blue = Color(red: 0.16, green: 0.45, blue: 0.96)
    static let danger = Color(red: 0.92, green: 0.26, blue: 0.27)
    static let gradient = LinearGradient(colors: [teal, blue],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let pageBackground = Color(.systemGroupedBackground)
}

/// Chuỗi đa ngôn ngữ (vi/en) — xem Resources/*.lproj/Localizable.strings
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), locale: Locale.current, arguments: args)
}

enum Fmt {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, value), countStyle: .file)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    static func monthTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return f.string(from: date).capitalized(with: Locale.current)
    }
}
