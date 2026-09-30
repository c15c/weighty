import Foundation

/// How far back "change" looks on Today, in the Journal and in widgets.
enum RatePeriod: Int, CaseIterable, Identifiable, Codable {
    case week = 7
    case fortnight = 14
    case threeWeeks = 21
    case month = 30
    case quarter = 90

    var id: Int { rawValue }
    var days: Int { rawValue }

    var label: String {
        switch self {
        case .week:       return "Last 7 days"
        case .fortnight:  return "Last 14 days"
        case .threeWeeks: return "Last 21 days"
        case .month:      return "Last 30 days"
        case .quarter:    return "Last 90 days"
        }
    }
}

enum WeekStart: Int, CaseIterable, Identifiable, Codable {
    case system = 0
    case sunday = 1
    case monday = 2
    case saturday = 7

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .system:   return "System"
        case .sunday:   return "Sunday"
        case .monday:   return "Monday"
        case .saturday: return "Saturday"
        }
    }

    var calendar: Calendar {
        var calendar = Calendar.current
        if self != .system { calendar.firstWeekday = rawValue }
        return calendar
    }
}

/// What a weigh-in's up/down dot and delta are measured against.
enum IndicatorBasis: String, CaseIterable, Identifiable, Codable {
    case previous
    case trend

    var id: String { rawValue }

    var label: String {
        switch self {
        case .previous: return "Previous weigh-in"
        case .trend:    return "Trend weight"
        }
    }
}

enum ReminderStyle: String, CaseIterable, Identifiable, Codable {
    case simple
    case streak
    case minimal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .simple:  return "Simple"
        case .streak:  return "Streak"
        case .minimal: return "Minimal"
        }
    }

    func title(streak: Int) -> String {
        switch self {
        case .simple:  return "Weigh-in"
        case .streak:  return streak > 0 ? "Day \(streak + 1)" : "Weigh-in"
        case .minimal: return "⚖️"
        }
    }

    func body(streak: Int) -> String {
        switch self {
        case .simple:  return "Log today's weight."
        case .streak:  return streak > 0 ? "\(streak)-day streak." : "Log today's weight."
        case .minimal: return ""
        }
    }
}

/// Profile values carried in backups. Optional so older backups restore cleanly.
struct ProfileSettings: Codable, Equatable {
    var heightCentimeters: Double?
    var baselineKilograms: Double?
    var ratePeriodDays: Int?
    var weekStart: Int?
    var indicatorBasis: String?
}
