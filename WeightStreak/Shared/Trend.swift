import Foundation

enum Trend {

    /// Rolling average over the trailing `days` window. Daily weight is noisy,
    /// so the average is the number worth reacting to, not the raw reading.
    static func average(entries: [WeightEntry],
                        days: Int,
                        ending: Date = Date(),
                        calendar: Calendar = .current) -> Double? {
        let end = calendar.startOfDay(for: ending)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) else { return nil }
        let window = entries.filter { $0.date >= start && $0.date <= end }
        guard !window.isEmpty else { return nil }
        return window.map(\.kilograms).reduce(0, +) / Double(window.count)
    }

    /// This week's rolling average minus last week's.
    static func weekOverWeek(entries: [WeightEntry],
                             now: Date = Date(),
                             calendar: Calendar = .current) -> Double? {
        guard let thisWeek = average(entries: entries, days: 7, ending: now),
              let priorEnd = calendar.date(byAdding: .day, value: -7, to: now),
              let lastWeek = average(entries: entries, days: 7, ending: priorEnd)
        else { return nil }
        return thisWeek - lastWeek
    }

    /// 0...1 progress from the first recorded weigh-in toward the goal.
    static func progress(start: Double?, latest: Double?, goal: Double?) -> Double? {
        guard let start, let latest, let goal, abs(start - goal) > 0.0001 else { return nil }
        let raw = (start - latest) / (start - goal)
        return min(max(raw, 0), 1)
    }

    static func recentValues(entries: [WeightEntry], days: Int = 30, now: Date = Date(),
                             calendar: Calendar = .current) -> [Double] {
        let cutoff = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) ?? now
        return entries.filter { $0.date >= cutoff }.map(\.kilograms)
    }
}
