import Foundation

struct StreakSummary: Equatable {
    var current: Int
    var longest: Int
    var loggedToday: Bool

    /// Streak is alive but today has not been logged yet.
    var atRisk: Bool { !loggedToday && current > 0 }

    static let empty = StreakSummary(current: 0, longest: 0, loggedToday: false)
}

enum StreakCalculator {

    /// A streak is consecutive calendar days with at least one weigh-in.
    /// Today counts as "not yet broken" until it rolls over, so the number
    /// on the widget does not drop to zero just because it is 7am.
    static func summary(entries: [WeightEntry],
                        now: Date = Date(),
                        calendar: Calendar = .current) -> StreakSummary {

        guard !entries.isEmpty else { return .empty }

        let days = Set(entries.map { calendar.startOfDay(for: $0.date) })
        let today = calendar.startOfDay(for: now)
        let loggedToday = days.contains(today)

        var current = 0
        var cursor = loggedToday
            ? today
            : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)

        while days.contains(cursor) {
            current += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        var longest = 0
        var run = 0
        var previousDay: Date?
        for day in days.sorted() {
            if let p = previousDay,
               let expected = calendar.date(byAdding: .day, value: 1, to: p),
               calendar.isDate(expected, inSameDayAs: day) {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previousDay = day
        }

        return StreakSummary(current: current,
                             longest: max(longest, current),
                             loggedToday: loggedToday)
    }
}
