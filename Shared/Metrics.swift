import Foundation

// MARK: - Direction indicators

enum WeightDirection: Equatable {
    case down
    case up
    case flat
}

struct EntryChange: Equatable {
    var direction: WeightDirection
    /// Signed kilograms against the basis. Nil for the very first weigh-in.
    var delta: Double?
}

enum Indicators {

    static let flatThreshold = 0.05

    static func direction(for delta: Double?) -> WeightDirection {
        guard let delta else { return .flat }
        if delta <= -flatThreshold { return .down }
        if delta >= flatThreshold { return .up }
        return .flat
    }

    /// Up/down for every entry, against the previous weigh-in or against the
    /// trend as it stood the day before.
    static func changes(entries: [WeightEntry],
                        basis: IndicatorBasis,
                        calendar: Calendar = .current) -> [UUID: EntryChange] {
        let sorted = entries.sorted { $0.date < $1.date }
        var result: [UUID: EntryChange] = [:]

        switch basis {
        case .previous:
            var previous: Double?
            for entry in sorted {
                let delta = previous.map { entry.kilograms - $0 }
                result[entry.id] = EntryChange(direction: direction(for: delta), delta: delta)
                previous = entry.kilograms
            }
        case .trend:
            var trendByDay: [Date: Double] = [:]
            for point in Trend.series(entries: sorted, calendar: calendar) {
                trendByDay[point.date] = point.trend
            }
            for entry in sorted {
                let day = calendar.startOfDay(for: entry.date)
                let before = calendar.date(byAdding: .day, value: -1, to: day).flatMap { trendByDay[$0] }
                let delta = before.map { entry.kilograms - $0 }
                result[entry.id] = EntryChange(direction: direction(for: delta), delta: delta)
            }
        }
        return result
    }
}

// MARK: - BMI

enum BMICategory: Int, CaseIterable, Identifiable {
    case underweight
    case healthy
    case overweight
    case obese1
    case obese2
    case obese3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .underweight: return "Underweight"
        case .healthy:     return "Healthy"
        case .overweight:  return "Overweight"
        case .obese1:      return "Obese I"
        case .obese2:      return "Obese II"
        case .obese3:      return "Obese III"
        }
    }

    /// WHO adult cut-offs.
    var range: ClosedRange<Double> {
        switch self {
        case .underweight: return 0...18.4
        case .healthy:     return 18.5...24.9
        case .overweight:  return 25.0...29.9
        case .obese1:      return 30.0...34.9
        case .obese2:      return 35.0...39.9
        case .obese3:      return 40.0...99
        }
    }

    var rangeLabel: String {
        switch self {
        case .underweight: return "< 18.5"
        case .obese3:      return "≥ 40.0"
        default:           return String(format: "%.1f – %.1f", range.lowerBound, range.upperBound)
        }
    }
}

enum BMI {

    /// The span drawn on BMI bars.
    static let scale: ClosedRange<Double> = 15...40

    static func value(kilograms: Double?, heightCentimeters: Double?) -> Double? {
        guard let kilograms, let heightCentimeters, heightCentimeters > 50, kilograms > 0 else { return nil }
        let metres = heightCentimeters / 100
        return kilograms / (metres * metres)
    }

    static func category(_ bmi: Double) -> BMICategory {
        switch bmi {
        case ..<18.5: return .underweight
        case ..<25:   return .healthy
        case ..<30:   return .overweight
        case ..<35:   return .obese1
        case ..<40:   return .obese2
        default:      return .obese3
        }
    }

    /// Weight range that sits inside the WHO healthy band for this height.
    static func healthyRange(heightCentimeters: Double?) -> ClosedRange<Double>? {
        guard let heightCentimeters, heightCentimeters > 50 else { return nil }
        let metres = heightCentimeters / 100
        return (18.5 * metres * metres)...(24.9 * metres * metres)
    }

    /// Position of a BMI value along `scale`, 0...1.
    static func position(_ bmi: Double) -> Double {
        min(max((bmi - scale.lowerBound) / (scale.upperBound - scale.lowerBound), 0), 1)
    }
}

// MARK: - Calendar cells

struct DayCell: Identifiable, Equatable {
    let date: Date
    let kilograms: Double?
    let direction: WeightDirection?
    let entryID: UUID?
    let isToday: Bool
    let isFuture: Bool

    var id: Date { date }
}

struct WeekGroup: Identifiable {
    let interval: DateInterval
    let entries: [WeightEntry]

    var id: Date { interval.start }

    var average: Double? {
        guard !entries.isEmpty else { return nil }
        return entries.map(\.kilograms).reduce(0, +) / Double(entries.count)
    }
}

enum WeightCalendar {

    static func cells(for days: [Date],
                      entries: [WeightEntry],
                      changes: [UUID: EntryChange],
                      now: Date,
                      calendar: Calendar) -> [DayCell] {
        var byDay: [Date: WeightEntry] = [:]
        for entry in entries { byDay[calendar.startOfDay(for: entry.date)] = entry }
        let today = calendar.startOfDay(for: now)
        return days.map { date in
            let day = calendar.startOfDay(for: date)
            let entry = byDay[day]
            return DayCell(date: day,
                           kilograms: entry?.kilograms,
                           direction: entry.flatMap { changes[$0.id]?.direction },
                           entryID: entry?.id,
                           isToday: day == today,
                           isFuture: day > today)
        }
    }

    /// Every day of the month containing `date`, plus how many blank cells
    /// precede the first day for the configured start of week.
    static func month(containing date: Date,
                      entries: [WeightEntry],
                      changes: [UUID: EntryChange],
                      now: Date = Date(),
                      calendar: Calendar) -> (leading: Int, days: [DayCell]) {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return (0, []) }
        var days: [Date] = []
        var day = interval.start
        while day < interval.end {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        return (leading, cells(for: days, entries: entries, changes: changes, now: now, calendar: calendar))
    }

    /// The seven days of the week containing `date`.
    static func week(containing date: Date,
                     entries: [WeightEntry],
                     changes: [UUID: EntryChange],
                     now: Date = Date(),
                     calendar: Calendar) -> [DayCell] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return [] }
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
        return cells(for: days, entries: entries, changes: changes, now: now, calendar: calendar)
    }

    /// The last `count` days ending today, oldest first.
    static func recent(_ count: Int,
                       entries: [WeightEntry],
                       changes: [UUID: EntryChange],
                       now: Date = Date(),
                       calendar: Calendar) -> [DayCell] {
        let today = calendar.startOfDay(for: now)
        let days = (0..<count).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        return cells(for: days, entries: entries, changes: changes, now: now, calendar: calendar)
    }

    /// Entries bucketed by calendar week, oldest week first.
    static func weekGroups(entries: [WeightEntry], calendar: Calendar) -> [WeekGroup] {
        var buckets: [Date: (DateInterval, [WeightEntry])] = [:]
        for entry in entries {
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: entry.date) else { continue }
            buckets[interval.start, default: (interval, [])].1.append(entry)
        }
        return buckets.values
            .map { WeekGroup(interval: $0.0, entries: $0.1.sorted { $0.date < $1.date }) }
            .sorted { $0.interval.start < $1.interval.start }
    }

    /// Mean of the month's weigh-ins, and change from the last reading before
    /// the month (or the month's first reading) to the latest one in it.
    static func monthStats(containing date: Date,
                           entries: [WeightEntry],
                           calendar: Calendar) -> (average: Double?, change: Double?) {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return (nil, nil) }
        let sorted = entries.sorted { $0.date < $1.date }
        let inMonth = sorted.filter { interval.contains($0.date) }
        guard let last = inMonth.last else { return (nil, nil) }
        let average = inMonth.map(\.kilograms).reduce(0, +) / Double(inMonth.count)
        let reference = sorted.last { $0.date < interval.start } ?? inMonth.first
        let change = reference.map { last.kilograms - $0.kilograms }
        return (average, inMonth.count > 1 || reference?.id != last.id ? change : nil)
    }
}

// MARK: - Period stats

struct PeriodStats: Equatable {
    let days: Int
    /// Change in trend weight across the period.
    let change: Double?
    let low: Double?
    let high: Double?
    let readings: [Double]
}

enum Periods {
    static func stats(entries: [WeightEntry],
                      days: Int,
                      now: Date = Date(),
                      calendar: Calendar = .current) -> PeriodStats {
        let points = Trend.series(entries: entries, now: now, calendar: calendar)
        let window = Array(points.suffix(days + 1))
        let change: Double?
        if window.count > 1, let first = window.first?.trend, let last = window.last?.trend {
            change = last - first
        } else {
            change = nil
        }
        let readings = points.suffix(days).compactMap(\.actual)
        return PeriodStats(days: days,
                           change: change,
                           low: readings.min(),
                           high: readings.max(),
                           readings: readings)
    }

    /// Monthly rate as a percentage of bodyweight. Negative is a loss.
    static func percentPerMonth(weeklyRate: Double?, bodyweight: Double?) -> Double? {
        guard let weeklyRate, let bodyweight, bodyweight > 0 else { return nil }
        return weeklyRate * (30.0 / 7.0) / bodyweight * 100
    }
}

// MARK: - Weight comparisons

struct WeightComparison: Equatable {
    let emoji: String
    let name: String
    let kilograms: Double
}

enum Comparisons {
    static let all: [WeightComparison] = [
        WeightComparison(emoji: "🥚", name: "an egg", kilograms: 0.06),
        WeightComparison(emoji: "🍌", name: "a banana", kilograms: 0.12),
        WeightComparison(emoji: "⚾", name: "a baseball", kilograms: 0.15),
        WeightComparison(emoji: "🍎", name: "an apple", kilograms: 0.18),
        WeightComparison(emoji: "📱", name: "a phone", kilograms: 0.2),
        WeightComparison(emoji: "🥭", name: "a mango", kilograms: 0.25),
        WeightComparison(emoji: "🥤", name: "a can of soft drink", kilograms: 0.39),
        WeightComparison(emoji: "⚽", name: "a soccer ball", kilograms: 0.43),
        WeightComparison(emoji: "🧈", name: "a block of butter", kilograms: 0.5),
        WeightComparison(emoji: "🏀", name: "a basketball", kilograms: 0.62),
        WeightComparison(emoji: "🍞", name: "a loaf of bread", kilograms: 0.7),
        WeightComparison(emoji: "🍍", name: "a pineapple", kilograms: 1.0),
        WeightComparison(emoji: "🍷", name: "a bottle of wine", kilograms: 1.25),
        WeightComparison(emoji: "🥾", name: "a pair of hiking boots", kilograms: 1.5),
        WeightComparison(emoji: "💻", name: "a laptop", kilograms: 1.8),
        WeightComparison(emoji: "🍗", name: "a whole chicken", kilograms: 2.0),
        WeightComparison(emoji: "🐇", name: "a rabbit", kilograms: 2.5),
        WeightComparison(emoji: "🎒", name: "a backpack", kilograms: 3.0),
        WeightComparison(emoji: "👶", name: "a newborn baby", kilograms: 3.5),
        WeightComparison(emoji: "🎸", name: "an electric guitar", kilograms: 3.8),
        WeightComparison(emoji: "🐈", name: "a cat", kilograms: 4.5),
        WeightComparison(emoji: "🎃", name: "a pumpkin", kilograms: 5.5),
        WeightComparison(emoji: "🍉", name: "a watermelon", kilograms: 6.5),
        WeightComparison(emoji: "🎳", name: "a bowling ball", kilograms: 7.0),
        WeightComparison(emoji: "🦃", name: "a turkey", kilograms: 8.0),
        WeightComparison(emoji: "🚲", name: "a bicycle", kilograms: 10.0),
        WeightComparison(emoji: "🛞", name: "a car tyre", kilograms: 11.0),
        WeightComparison(emoji: "🧒", name: "a toddler", kilograms: 13.0),
        WeightComparison(emoji: "🐕", name: "a kelpie", kilograms: 15.0),
        WeightComparison(emoji: "⛽", name: "a full jerry can", kilograms: 20.0),
        WeightComparison(emoji: "🧳", name: "a checked suitcase", kilograms: 23.0),
        WeightComparison(emoji: "🦮", name: "a labrador", kilograms: 30.0),
        WeightComparison(emoji: "🦘", name: "a kangaroo", kilograms: 35.0),
        WeightComparison(emoji: "🐐", name: "a goat", kilograms: 45.0)
    ]

    /// The heaviest object not exceeding the amount lost or gained.
    static func best(for change: Double?) -> WeightComparison? {
        guard let change else { return nil }
        let amount: Double = abs(change)
        guard amount >= all[0].kilograms else { return nil }
        return all.last { $0.kilograms <= amount + 0.0001 }
    }
}
