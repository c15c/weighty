import Foundation

/// What a tag is worth in kilograms: how far readings on tagged days sit from
/// the trend, compared with untagged days.
struct TagInsight: Identifiable, Equatable {
    let tag: TagDefinition
    /// Positive means those days read heavier than the trend.
    let deviation: Double
    let occurrences: Int

    var id: String { tag.id }
}

enum Insights {

    /// Tags need a few samples before the number means anything.
    static let minimumOccurrences = 3

    /// Correlate context tags against residuals from the smoothed trend.
    ///
    /// This is the payoff for tagging: it turns "the scale jumped" into "the
    /// scale always jumps the morning after a salty meal, and it comes back."
    static func tagInsights(entries: [WeightEntry],
                            now: Date = Date(),
                            calendar: Calendar = .current) -> [TagInsight] {
        let points = Trend.series(entries: entries, now: now, calendar: calendar)
        guard !points.isEmpty else { return [] }

        var residualByDay: [Date: Double] = [:]
        for point in points {
            if let actual = point.actual {
                residualByDay[point.date] = actual - point.trend
            }
        }
        guard residualByDay.count >= 8 else { return [] }

        var taggedDays: Set<Date> = []
        var sums: [String: (total: Double, count: Int)] = [:]

        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)
            guard let residual = residualByDay[day] else { continue }
            guard !entry.tags.isEmpty else { continue }
            taggedDays.insert(day)
            for tag in entry.tags {
                let existing = sums[tag] ?? (0, 0)
                sums[tag] = (existing.total + residual, existing.count + 1)
            }
        }

        let baselineDays = residualByDay.filter { !taggedDays.contains($0.key) }
        let baseline = baselineDays.isEmpty
            ? 0
            : baselineDays.values.reduce(0, +) / Double(baselineDays.count)

        return sums
            .filter { $0.value.count >= minimumOccurrences }
            .map { tag, value in
                TagInsight(tag: TagCatalog.definition(for: tag),
                           deviation: value.total / Double(value.count) - baseline,
                           occurrences: value.count)
            }
            .filter { abs($0.deviation) >= 0.15 }
            .sorted { abs($0.deviation) > abs($1.deviation) }
    }

    /// Typical weigh-in hour, used to schedule the reminder when the habit
    /// already happens instead of at an arbitrary time.
    static func usualWeighInTime(entries: [WeightEntry],
                                 calendar: Calendar = .current) -> DateComponents? {
        let minutes = entries
            .compactMap(\.loggedAt)
            .suffix(30)
            .map { date -> Int in
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
            .sorted()
        guard minutes.count >= 5 else { return nil }

        let median = minutes[minutes.count / 2]
        var components = DateComponents()
        components.hour = median / 60
        components.minute = median % 60
        return components
    }

    /// Guard against a fat-fingered reading. One 8.42 instead of 84.2 permanently
    /// distorts the trend, the streak and every chart.
    static func isImplausible(kilograms: Double,
                              entries: [WeightEntry],
                              now: Date = Date()) -> Bool {
        guard kilograms > 0 else { return true }
        guard let reference = Trend.current(entries: entries, now: now)
                ?? entries.sorted(by: { $0.date < $1.date }).last?.kilograms
        else { return kilograms < 20 || kilograms > 400 }
        return abs(kilograms - reference) > 5
    }
}
