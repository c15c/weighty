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

    /// Compact facts for the on-device model. Numbers live here so generated
    /// copy cannot invent a rate the app does not already have.
    static func snapshot(entries: [WeightEntry],
                         goal: Double?,
                         now: Date = Date(),
                         calendar: Calendar = .current) -> InsightSnapshot {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        let time = DateFormatter()
        time.dateFormat = "HH:mm"

        let latest = entries.sorted { $0.date < $1.date }.last
        let projection = Trend.projectedGoalDate(entries: entries, goal: goal, now: now, calendar: calendar)

        let tagLines = tagInsights(entries: entries, now: now, calendar: calendar).prefix(6).map {
            InsightSnapshot.TagEffect(id: $0.tag.id,
                                      label: $0.tag.label,
                                      deviation: $0.deviation,
                                      occurrences: $0.occurrences)
        }

        let notes = entries.suffix(10).reversed().map { entry -> InsightSnapshot.Note in
            InsightSnapshot.Note(
                id: entry.id.uuidString,
                date: iso.string(from: entry.date),
                kilograms: entry.kilograms,
                tags: entry.resolvedTags.map(\.label).joined(separator: ","),
                note: String((entry.note ?? "").prefix(180))
            )
        }

        return InsightSnapshot(
            trend: Trend.current(entries: entries, now: now, calendar: calendar),
            latest: latest?.kilograms,
            latestAt: latest?.loggedAt.map { "\(iso.string(from: $0)) \(time.string(from: $0))" }
                ?? latest.map { iso.string(from: $0.date) },
            weekChange: Trend.weekOverWeek(entries: entries, now: now, calendar: calendar),
            thisWeekAverage: Trend.calendarWeekAverage(entries: entries, weeksAgo: 0, now: now, calendar: calendar),
            lastWeekAverage: Trend.calendarWeekAverage(entries: entries, weeksAgo: 1, now: now, calendar: calendar),
            weeklyRate: Trend.weeklyRate(entries: entries, now: now, calendar: calendar),
            noise: Trend.noise(entries: entries, now: now, calendar: calendar),
            inNoise: Trend.withinNoise(entries: entries, now: now, calendar: calendar),
            plateauDays: Trend.plateauDays(entries: entries, now: now, calendar: calendar),
            goal: goal,
            projectedDate: projection.map { iso.string(from: $0) },
            established: Trend.isEstablished(entries: entries, now: now, calendar: calendar),
            streak: StreakCalculator.summary(entries: entries, now: now, calendar: calendar).current,
            tagEffects: Array(tagLines),
            recent: Array(notes)
        )
    }
}

struct InsightSnapshot: Equatable {
    struct TagEffect: Equatable {
        var id: String
        var label: String
        var deviation: Double
        var occurrences: Int
    }

    struct Note: Equatable {
        var id: String
        var date: String
        var kilograms: Double
        var tags: String
        var note: String
    }

    var trend: Double?
    var latest: Double?
    var latestAt: String?
    var weekChange: Double?
    var thisWeekAverage: Double?
    var lastWeekAverage: Double?
    var weeklyRate: Double?
    var noise: Double?
    var inNoise: Bool?
    var plateauDays: Int?
    var goal: Double?
    var projectedDate: String?
    var established: Bool
    var streak: Int
    var tagEffects: [TagEffect]
    var recent: [Note]

    func promptText() -> String {
        func n(_ value: Double?, digits: Int = 2) -> String {
            guard let value else { return "na" }
            return String(format: "%.\(digits)f", value)
        }
        var lines = [
            "TREND_KG \(n(trend))",
            "LATEST_KG \(n(latest))",
            "LATEST_AT \(latestAt ?? "na")",
            "WEEK_CHANGE_KG \(n(weekChange))",
            "THIS_WEEK_AVG_KG \(n(thisWeekAverage))",
            "LAST_WEEK_AVG_KG \(n(lastWeekAverage))",
            "RATE_KG_PER_WEEK \(n(weeklyRate))",
            "NOISE_KG \(n(noise))",
            "IN_NOISE \(inNoise.map { $0 ? "true" : "false" } ?? "na")",
            "PLATEAU_DAYS \(plateauDays.map(String.init) ?? "na")",
            "GOAL_KG \(n(goal))",
            "PROJECTED \(projectedDate ?? "na")",
            "ESTABLISHED \(established)",
            "STREAK_DAYS \(streak)"
        ]
        lines.append("TAG_EFFECTS")
        if tagEffects.isEmpty {
            lines.append("none")
        } else {
            for tag in tagEffects {
                lines.append("\(tag.label): \(n(tag.deviation)) n=\(tag.occurrences)")
            }
        }
        lines.append("RECENT")
        for item in recent {
            lines.append("\(item.date) \(n(item.kilograms, digits: 1)) tags=\(item.tags.isEmpty ? "-" : item.tags) note=\(item.note.isEmpty ? "-" : item.note)")
        }
        return lines.joined(separator: "\n")
    }
}
