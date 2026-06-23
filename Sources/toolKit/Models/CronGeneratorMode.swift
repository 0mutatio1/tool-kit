import Foundation

enum CronGeneratorMode: String, CaseIterable, Identifiable {
    case everyNMinutes
    case hourly
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyNMinutes: return "Interval"
        case .hourly: return "Hourly"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }
}
