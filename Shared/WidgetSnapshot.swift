import Foundation

/// Everything any widget needs, computed once per timeline refresh. The app's
/// Widgets tab builds the same snapshot so previews match the real widgets.
struct WidgetSnapshot {
    var now: Date
    var unit: WeightUnit
    var streak: StreakSummary

    var trend: Double?
    var latest: Double?
    var latestDate: Date?
    var weeklyRate: Double?
    var percentPerMonth: Double?

    var goal: Double?
    var start: Double?
    var progress: Double?
    var lost: Double?
    var remaining: Double?

    var period: PeriodStats

    var bmi: Double?
    var healthyRange: ClosedRange<Double>?

    var week: [DayCell]
    var recentDays: [DayCell]
    var monthLeading: Int
    var month: [DayCell]
    var monthAverage: Double?
    var monthChange: Double?
    var chart: [TrendPoint]
    var weekdaySymbols: [String]

    var sharedStorageAvailable: Bool

    var comparison: WeightComparison? { Comparisons.best(for: lost) }

    static func make(store: WeightStore, now: Date = Date()) -> WidgetSnapshot {
        make(entries: store.entries,
             unit: store.unit,
             goal: store.goalKilograms,
             baseline: store.baselineKilograms,
             heightCentimeters: store.heightCentimeters,
             ratePeriod: store.ratePeriod,
             weekStart: store.weekStart,
             indicatorBasis: store.indicatorBasis,
             sharedStorageAvailable: store.sharedStorageAvailable,
             now: now)
    }

    static func make(entries: [WeightEntry],
                     unit: WeightUnit,
                     goal: Double?,
                     baseline: Double?,
                     heightCentimeters: Double?,
                     ratePeriod: RatePeriod,
                     weekStart: WeekStart,
                     indicatorBasis: IndicatorBasis,
                     sharedStorageAvailable: Bool,
                     now: Date = Date()) -> WidgetSnapshot {
        let calendar = weekStart.calendar
        let sorted = entries.sorted { $0.date < $1.date }
        let changes = Indicators.changes(entries: sorted, basis: indicatorBasis, calendar: calendar)
        let trend = Trend.current(entries: sorted, now: now, calendar: calendar)
        let rate = Trend.weeklyRate(entries: sorted, now: now, calendar: calendar)
        let start = baseline ?? sorted.first?.kilograms
        let month = WeightCalendar.month(containing: now, entries: sorted, changes: changes,
                                         now: now, calendar: calendar)
        let monthStats = WeightCalendar.monthStats(containing: now, entries: sorted, calendar: calendar)

        var symbols = calendar.veryShortWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        if shift > 0, shift < symbols.count {
            symbols = Array(symbols[shift...] + symbols[..<shift])
        }

        return WidgetSnapshot(
            now: now,
            unit: unit,
            streak: StreakCalculator.summary(entries: sorted, now: now, calendar: calendar),
            trend: trend,
            latest: sorted.last?.kilograms,
            latestDate: sorted.last?.date,
            weeklyRate: rate,
            percentPerMonth: Periods.percentPerMonth(weeklyRate: rate, bodyweight: trend),
            goal: goal,
            start: start,
            progress: Trend.progress(start: start, latest: trend, goal: goal),
            lost: start.flatMap { s in trend.map { s - $0 } },
            remaining: goal.flatMap { g in trend.map { max($0 - g, 0) } },
            period: Periods.stats(entries: sorted, days: ratePeriod.days, now: now, calendar: calendar),
            bmi: BMI.value(kilograms: trend, heightCentimeters: heightCentimeters),
            healthyRange: BMI.healthyRange(heightCentimeters: heightCentimeters),
            week: WeightCalendar.week(containing: now, entries: sorted, changes: changes,
                                      now: now, calendar: calendar),
            recentDays: WeightCalendar.recent(7, entries: sorted, changes: changes,
                                              now: now, calendar: calendar),
            monthLeading: month.leading,
            month: month.days,
            monthAverage: monthStats.average,
            monthChange: monthStats.change,
            chart: Trend.series(entries: sorted, days: 30, now: now, calendar: calendar),
            weekdaySymbols: symbols,
            sharedStorageAvailable: sharedStorageAvailable
        )
    }

    /// Believable sample data for the widget gallery and placeholders.
    static var placeholder: WidgetSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let wobble: [Double] = [0.3, -0.2, 0.5, 0.1, -0.4, 0.2, 0.6, -0.1, 0.0, 0.4, -0.3, 0.2]
        var entries: [WeightEntry] = []
        for offset in 0..<45 where offset % 9 != 4 {
            guard let day = calendar.date(byAdding: .day, value: -(44 - offset), to: today) else { continue }
            let value = 91.0 - Double(offset) * 0.09 + wobble[offset % wobble.count]
            entries.append(WeightEntry(date: day, kilograms: (value * 10).rounded() / 10, loggedAt: day))
        }
        return make(entries: entries,
                    unit: .kilograms,
                    goal: 80,
                    baseline: nil,
                    heightCentimeters: 182,
                    ratePeriod: .threeWeeks,
                    weekStart: .monday,
                    indicatorBasis: .previous,
                    sharedStorageAvailable: true)
    }
}
