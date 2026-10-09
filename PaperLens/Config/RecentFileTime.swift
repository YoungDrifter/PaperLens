import Foundation

/// Legacy history has no timestamp; never invent an opening date for it.
enum RecentFileTime {
    static func label(for date: Date?, relativeTo now: Date) -> String {
        guard let date else { return "Earlier" }
        if now.timeIntervalSince(date) < 60 { return "Just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
