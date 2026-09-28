import Foundation

/// One resampled day of the series. `actual` is nil on days with no weigh-in,
/// while `trend` always carries a value so the line and the axis stay honest
/// about elapsed time rather than plotting entries evenly spaced.
struct TrendPoint: Identifiable, Equatable {
    let date: Date
    let actual: Double?
    let trend: Double

    var id: Date { date }
}

enum RateAssessment: Equatable {
    case gaining
    case maintaining
    case steady
    case fast

    var label: String {
        switch self {
        case .gaining:     return "Trending up"
        case .maintaining: return "Holding steady"
        case .steady:      return "Sustainable loss"
        case .fast:        return "Faster than recommended"
        }
    }
}

enum Trend {

    /// Exponential smoothing factor. 0.1 is the long-standing Hacker's Diet value:
    /// slow enough to ignore a salty dinner, fast enough to show a real change
    /// inside a week.
    static let smoothing = 0.1

    // MARK: - Series

    /// Day-by-day smoothed series from the first weigh-in through `now`.
    ///
    /// Daily weight is mostly water, so the raw reading is noise around a slow
    /// signal. The trend is the number worth reacting to. Gaps are handled by
    /// compounding the smoothing factor, so the first weigh-in after a two-week
    /// break moves the trend further than one taken the next morning.
    static func series(entries: [WeightEntry],
                       now: Date = Date(),
                       calendar: Calendar = .current) -> [TrendPoint] {
        let sorted = entries.sorted { $0.date < $1.date }
        guard let first = sorted.first else { return [] }

        var byDay: [Date: Double] = [:]
        for entry in sorted {
            byDay[calendar.startOfDay(for: entry.date)] = entry.kilograms
        }

        let start = calendar.startOfDay(for: first.date)
        let end = max(calendar.startOfDay(for: now),
                      calendar.startOfDay(for: sorted[sorted.count - 1].date))

        var points: [TrendPoint] = []
        var trend = first.kilograms
        var daysSinceReading = 0
        var day = start

        while day <= end {
            let actual = byDay[day]
            if let actual {
                // Compound the factor across skipped days, capped so a long gap
                // does not snap the trend onto a single noisy reading.
                let steps = min(daysSinceReading + 1, 14)
                let alpha = min(1 - pow(1 - smoothing, Double(steps)), 0.6)
                trend += (actual - trend) * alpha
                daysSinceReading = 0
            } else {
                daysSinceReading += 1
            }
            points.append(TrendPoint(date: day, actual: actual, trend: trend))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return points
    }

    static func series(entries: [WeightEntry],
                       days: Int,
                       now: Date = Date(),
                       calendar: Calendar = .current) -> [TrendPoint] {
        let all = series(entries: entries, now: now, calendar: calendar)
        guard days > 0,
              let cutoff = calendar.date(byAdding: .day,
                                         value: -(days - 1),
                                         to: calendar.startOfDay(for: now))
        else { return all }
        return all.filter { $0.date >= cutoff }
    }

    /// Today's smoothed weight.
    static func current(entries: [WeightEntry],
                        now: Date = Date(),
                        calendar: Calendar = .current) -> Double? {
        series(entries: entries, now: now, calendar: calendar).last?.trend
    }

    // MARK: - Rate of change

    /// Kilograms per week, from a least-squares fit over the trailing window of
    /// the smoothed series. Negative is a loss.
    static func weeklyRate(entries: [WeightEntry],
                           days: Int = 21,
                           now: Date = Date(),
                           calendar: Calendar = .current) -> Double? {
        let window = series(entries: entries, days: days, now: now, calendar: calendar)
        guard window.count >= 8 else { return nil }

        let values = window.map(\.trend)
        let n = Double(values.count)
        let meanX = (n - 1) / 2
        let meanY = values.reduce(0, +) / n

        var numerator = 0.0
        var denominator = 0.0
        for (index, value) in values.enumerated() {
            let dx = Double(index) - meanX
            numerator += dx * (value - meanY)
            denominator += dx * dx
        }
        guard denominator > 0 else { return nil }
        return (numerator / denominator) * 7
    }

    /// 0.5–1% of bodyweight per week is the usual sustainable band. Losing faster
    /// predicts lean-mass loss and rebound, so it is worth flagging rather than
    /// celebrating.
    static func assessment(weeklyRate: Double?, bodyweight: Double?) -> RateAssessment? {
        guard let weeklyRate else { return nil }
        guard let bodyweight, bodyweight > 0 else {
            return weeklyRate > 0.1 ? .gaining : (weeklyRate < -0.1 ? .steady : .maintaining)
        }
        let percent = (-weeklyRate / bodyweight) * 100
        if percent < -0.1 { return .gaining }
        if percent < 0.1 { return .maintaining }
        if percent > 1.0 { return .fast }
        return .steady
    }

    /// When the current rate would reach the goal. Nil when the goal is met,
    /// the trend is flat, or the trend is moving the wrong way.
    static func projectedGoalDate(entries: [WeightEntry],
                                  goal: Double?,
                                  now: Date = Date(),
                                  calendar: Calendar = .current) -> Date? {
        guard let goal,
              let trend = current(entries: entries, now: now, calendar: calendar),
              let rate = weeklyRate(entries: entries, now: now, calendar: calendar)
        else { return nil }

        let remaining = trend - goal
        guard abs(remaining) > 0.05 else { return nil }
        // Only project when the trend actually points at the goal.
        guard (remaining > 0 && rate < -0.02) || (remaining < 0 && rate > 0.02) else { return nil }

        let weeks = remaining / -rate
        guard weeks > 0, weeks < 260 else { return nil }
        return calendar.date(byAdding: .day, value: Int((weeks * 7).rounded()), to: now)
    }

    // MARK: - Noise

    /// Standard deviation of readings around the trend: the honest width of a
    /// normal daily swing for this person.
    static func noise(entries: [WeightEntry],
                      days: Int = 60,
                      now: Date = Date(),
                      calendar: Calendar = .current) -> Double? {
        let residuals = series(entries: entries, days: days, now: now, calendar: calendar)
            .compactMap { point -> Double? in
                guard let actual = point.actual else { return nil }
                return actual - point.trend
            }
        guard residuals.count >= 5 else { return nil }
        let mean = residuals.reduce(0, +) / Double(residuals.count)
        let variance = residuals
            .map { ($0 - mean) * ($0 - mean) }
            .reduce(0, +) / Double(residuals.count)
        return max(sqrt(variance), 0.15)
    }

    /// True when the latest reading is inside normal daily variation, which is
    /// the moment people usually panic for no reason.
    static func withinNoise(entries: [WeightEntry],
                            now: Date = Date(),
                            calendar: Calendar = .current) -> Bool? {
        guard let latest = entries.sorted(by: { $0.date < $1.date }).last,
              let trend = current(entries: entries, now: now, calendar: calendar),
              let noise = noise(entries: entries, now: now, calendar: calendar)
        else { return nil }
        return abs(latest.kilograms - trend) <= noise
    }

    /// Days the trend has stayed inside a half-noise band: a real plateau, as
    /// opposed to three heavy mornings in a row.
    static func plateauDays(entries: [WeightEntry],
                            now: Date = Date(),
                            calendar: Calendar = .current) -> Int? {
        let points = series(entries: entries, days: 90, now: now, calendar: calendar)
        guard points.count >= 14, let latest = points.last?.trend else { return nil }
        let band = max((noise(entries: entries, now: now, calendar: calendar) ?? 0.4) / 2, 0.15)

        var days = 0
        for point in points.reversed() {
            if abs(point.trend - latest) <= band { days += 1 } else { break }
        }
        return days >= 14 ? days : nil
    }

    // MARK: - Goal progress

    /// 0...1 progress from the starting weight toward the goal, measured on the
    /// trend so a single bad morning never erases visible progress.
    static func progress(start: Double?, latest: Double?, goal: Double?) -> Double? {
        guard let start, let latest, let goal, abs(start - goal) > 0.0001 else { return nil }
        let raw = (start - latest) / (start - goal)
        return min(max(raw, 0), 1)
    }

    // MARK: - Compatibility helpers

    /// Trailing simple average. Kept for CSV-style summaries; prefer `current`.
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

    /// Change in the smoothed trend over the past seven days.
    static func weekOverWeek(entries: [WeightEntry],
                             now: Date = Date(),
                             calendar: Calendar = .current) -> Double? {
        let points = series(entries: entries, now: now, calendar: calendar)
        guard let latest = points.last?.trend, points.count > 7 else { return nil }
        return latest - points[points.count - 8].trend
    }

    static func recentValues(entries: [WeightEntry],
                             days: Int = 30,
                             now: Date = Date(),
                             calendar: Calendar = .current) -> [Double] {
        series(entries: entries, days: days, now: now, calendar: calendar).map(\.trend)
    }

    /// True once the smoothed series has enough actual weigh-ins that rate and
    /// projection are not just the first noisy week.
    static func isEstablished(entries: [WeightEntry],
                              now: Date = Date(),
                              calendar: Calendar = .current) -> Bool {
        let points = series(entries: entries, now: now, calendar: calendar)
        let readings = points.filter { $0.actual != nil }.count
        return points.count >= 14 && readings >= 8
    }

    /// Mean of actual weigh-ins in the calendar week `weeksAgo` weeks before `now`.
    /// `weeksAgo` 0 is the current week.
    static func calendarWeekAverage(entries: [WeightEntry],
                                    weeksAgo: Int,
                                    now: Date = Date(),
                                    calendar: Calendar = .current) -> Double? {
        let today = calendar.startOfDay(for: now)
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today),
              let start = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: thisWeek.start),
              let end = calendar.date(byAdding: .day, value: 7, to: start)
        else { return nil }
        let weights = entries
            .filter { $0.date >= start && $0.date < end }
            .map(\.kilograms)
        guard !weights.isEmpty else { return nil }
        return weights.reduce(0, +) / Double(weights.count)
    }
}
