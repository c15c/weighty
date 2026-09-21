import Foundation

struct StreakSummary: Equatable {
    var current: Int
    var longest: Int
    var loggedToday: Bool
    /// Change at the most recent weigh-in against the one before it. Negative is a loss.
    var lastChange: Double?

    var atRisk: Bool { !loggedToday && current > 0 }

    static let empty = StreakSummary(current: 0,
                                     longest: 0,
                                     loggedToday: false,
                                     lastChange: nil)
}

enum StreakCalculator {

    /// A first weigh-in starts at one. Each lower weigh-in extends the streak;
    /// a gain or equal result begins a fresh streak at one.
    static func summary(entries: [WeightEntry],
                        now: Date = Date(),
                        calendar: Calendar = .current) -> StreakSummary {

        guard !entries.isEmpty else { return .empty }

        let sorted = entries.sorted { $0.date < $1.date }
        let today = calendar.startOfDay(for: now)
        let loggedToday = sorted.contains { calendar.isDate($0.date, inSameDayAs: today) }

        var current = 1
        var longest = 1

        if sorted.count > 1 {
            for index in 1..<sorted.count {
                if sorted[index].kilograms < sorted[index - 1].kilograms {
                    current += 1
                } else {
                    current = 1
                }
                longest = max(longest, current)
            }
        }

        let lastChange: Double? = sorted.count > 1
            ? sorted[sorted.count - 1].kilograms - sorted[sorted.count - 2].kilograms
            : nil

        return StreakSummary(current: current,
                             longest: longest,
                             loggedToday: loggedToday,
                             lastChange: lastChange)
    }
}
