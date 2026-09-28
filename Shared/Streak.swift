import Foundation

struct StreakSummary: Equatable {
    /// Consecutive days weighed, allowing a single skipped day.
    var current: Int
    var longest: Int
    var loggedToday: Bool
    /// Whether the run is currently leaning on its skipped-day allowance.
    var usingGrace: Bool
    var daysSinceLastLog: Int?
    /// Change at the most recent weigh-in against the one before it. Negative is a loss.
    var lastChange: Double?

    /// Alive but unlogged today: worth a nudge, not a warning.
    var atRisk: Bool { current > 0 && !loggedToday }

    /// One more missed day ends the run.
    var criticalToday: Bool { current > 0 && !loggedToday && usingGrace }

    static let empty = StreakSummary(current: 0,
                                     longest: 0,
                                     loggedToday: false,
                                     usingGrace: false,
                                     daysSinceLastLog: nil,
                                     lastChange: nil)
}

enum StreakCalculator {

    /// The streak counts the habit, not the outcome.
    ///
    /// Daily weight swings a kilo or more on water, sodium and glycogen alone, so
    /// a "lower every day" streak is unwinnable and teaches people that they are
    /// failing while they are in fact losing. What actually drives loss is
    /// stepping on the scale, so that is what is rewarded here. One missed day is
    /// forgiven; two in a row ends the run.
    static func summary(entries: [WeightEntry],
                        now: Date = Date(),
                        calendar: Calendar = .current) -> StreakSummary {

        guard !entries.isEmpty else { return .empty }

        let sorted = entries.sorted { $0.date < $1.date }
        let today = calendar.startOfDay(for: now)
        let logged = Set(sorted.map { calendar.startOfDay(for: $0.date) })
        let loggedToday = logged.contains(today)

        let lastChange: Double? = sorted.count > 1
            ? sorted[sorted.count - 1].kilograms - sorted[sorted.count - 2].kilograms
            : nil

        let daysSinceLastLog = logged.max().flatMap {
            calendar.dateComponents([.day], from: $0, to: today).day
        }

        return StreakSummary(current: currentRun(logged: logged,
                                                 today: today,
                                                 calendar: calendar),
                             longest: longestRun(logged: logged, calendar: calendar),
                             loggedToday: loggedToday,
                             usingGrace: !loggedToday && logged.contains(
                                calendar.date(byAdding: .day, value: -1, to: today) ?? today),
                             daysSinceLastLog: daysSinceLastLog,
                             lastChange: lastChange)
    }

    /// Walk back from today counting logged days, stopping at two misses in a row.
    private static func currentRun(logged: Set<Date>,
                                   today: Date,
                                   calendar: Calendar) -> Int {
        guard !logged.isEmpty else { return 0 }

        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        // Missing both today and yesterday means the run has already ended.
        guard logged.contains(today) || logged.contains(yesterday) else { return 0 }

        var count = 0
        var misses = 0
        var day = today

        while misses < 2 {
            if logged.contains(day) {
                count += 1
                misses = 0
            } else {
                misses += 1
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    private static func longestRun(logged: Set<Date>, calendar: Calendar) -> Int {
        guard let first = logged.min(), let last = logged.max() else { return 0 }

        var best = 0
        var count = 0
        var misses = 0
        var day = first

        while day <= last {
            if logged.contains(day) {
                count += 1
                misses = 0
                best = max(best, count)
            } else {
                misses += 1
                if misses >= 2 {
                    count = 0
                    misses = 0
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return best
    }
}
