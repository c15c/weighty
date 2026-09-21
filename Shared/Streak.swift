import Foundation

struct StreakSummary: Equatable {
    var current: Int
    var longest: Int
    var loggedToday: Bool
    /// Change at the most recent weigh-in against the one before it. Negative is a loss.
    var lastChange: Double?

    /// Streak is alive but today has not been weighed yet.
    var atRisk: Bool { !loggedToday && current > 0 }

    static let empty = StreakSummary(current: 0,
                                     longest: 0,
                                     loggedToday: false,
                                     lastChange: nil)
}

enum StreakCalculator {

    /// A streak is consecutive weigh-ins that came in lower than the one before.
    ///
    /// Gaining breaks it. Missing a day does not: the streak sits where it is until
    /// the next weigh-in decides it, so skipping the scale costs you nothing and
    /// only the number itself can end the run. The first ever weigh-in has nothing
    /// to compare against, so it does not count.
    static func summary(entries: [WeightEntry],
                        now: Date = Date(),
                        calendar: Calendar = .current) -> StreakSummary {

        guard !entries.isEmpty else { return .empty }

        let sorted = entries.sorted { $0.date < $1.date }
        let today = calendar.startOfDay(for: now)
        let loggedToday = sorted.contains { calendar.isDate($0.date, inSameDayAs: today) }

        guard sorted.count >= 2 else {
            return StreakSummary(current: 0,
                                 longest: 0,
                                 loggedToday: loggedToday,
                                 lastChange: nil)
        }

        // Did each weigh-in come in under the previous one?
        var losses: [Bool] = []
        for index in 1..<sorted.count {
            losses.append(sorted[index].kilograms < sorted[index - 1].kilograms)
        }

        var current = 0
        for loss in losses.reversed() {
            if loss { current += 1 } else { break }
        }

        var longest = 0
        var run = 0
        for loss in losses {
            run = loss ? run + 1 : 0
            longest = max(longest, run)
        }

        let lastChange = sorted[sorted.count - 1].kilograms - sorted[sorted.count - 2].kilograms

        return StreakSummary(current: current,
                             longest: max(longest, current),
                             loggedToday: loggedToday,
                             lastChange: lastChange)
    }
}
