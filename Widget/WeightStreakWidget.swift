import WidgetKit
import SwiftUI

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // Hourly, so day-based widgets roll over shortly after midnight.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [current()], policy: .after(next)))
    }

    private func current() -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .make(store: WeightStore()))
    }
}

// MARK: - Backgrounds

private extension View {
    func systemWidget() -> some View {
        self
            .containerBackground(for: .widget) { Color(.systemBackground) }
            .widgetURL(URL(string: "weightstreak://log"))
    }

    func circularWidget() -> some View {
        self
            .containerBackground(for: .widget) { AccessoryWidgetBackground() }
            .widgetURL(URL(string: "weightstreak://log"))
    }

    func clearWidget() -> some View {
        self
            .containerBackground(for: .widget) { Color.clear }
            .widgetURL(URL(string: "weightstreak://log"))
    }
}

// MARK: - Streak

struct StreakFamilyView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            StreakCircularWidgetView(s: entry.snapshot).circularWidget()
        case .accessoryInline:
            let s = entry.snapshot
            let rate = s.weeklyRate.map { " · \(s.unit.formattedDelta($0, decimals: 2))/wk" } ?? ""
            Text("\(s.trend.map { s.unit.formatted($0) } ?? "--")\(rate)").clearWidget()
        case .systemMedium:
            StreakMediumWidgetView(s: entry.snapshot).systemWidget()
        default:
            StreakSmallWidgetView(s: entry.snapshot).systemWidget()
        }
    }
}

struct WeightStreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeightStreakWidget", provider: SnapshotProvider()) { entry in
            StreakFamilyView(entry: entry)
        }
        .configurationDisplayName("Trend & Streak")
        .description("Trend weight, weekly rate and streak.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryInline])
    }
}

// MARK: - Today

struct TodayFamilyView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            WeightCircularGaugeView(s: entry.snapshot).circularWidget()
        default:
            TodayGaugeWidgetView(s: entry.snapshot).systemWidget()
        }
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeightToday", provider: SnapshotProvider()) { entry in
            TodayFamilyView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Today's weight against your recent range.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

// MARK: - Week bars

struct WeekFamilyView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            WeekBarsAccessoryView(s: entry.snapshot).clearWidget()
        default:
            WeekBarsWidgetView(s: entry.snapshot).systemWidget()
        }
    }
}

struct WeekBarsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeightWeekBars", provider: SnapshotProvider()) { entry in
            WeekFamilyView(entry: entry)
        }
        .configurationDisplayName("This Week")
        .description("Each weigh-in this week.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

// MARK: - Week list

struct WeekListWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeightWeekList", provider: SnapshotProvider()) { entry in
            WeekListWidgetView(s: entry.snapshot).systemWidget()
        }
        .configurationDisplayName("Last 7 Days")
        .description("The past week's readings.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Chart

struct ChartWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeightChart", provider: SnapshotProvider()) { entry in
            WeightChartWidgetView(s: entry.snapshot).systemWidget()
        }
        .configurationDisplayName("Body Weight")
        .description("Weigh-ins over the last 30 days.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Comparison

struct ComparisonWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeightComparison", provider: SnapshotProvider()) { entry in
            ComparisonWidgetView(s: entry.snapshot).systemWidget()
        }
        .configurationDisplayName("Weight Change")
        .description("What you've lost or gained, as an everyday object.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - BMI

struct BMIWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeightBMI", provider: SnapshotProvider()) { entry in
            BMIWidgetView(s: entry.snapshot).systemWidget()
        }
        .configurationDisplayName("BMI")
        .description("BMI from trend weight, with WHO category.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Calendar

struct CalendarFamilyView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        switch family {
        case .systemMedium:
            CalendarMediumWidgetView(s: entry.snapshot).systemWidget()
        default:
            CalendarSmallWidgetView(s: entry.snapshot).systemWidget()
        }
    }
}

struct CalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeightCalendar", provider: SnapshotProvider()) { entry in
            CalendarFamilyView(entry: entry)
        }
        .configurationDisplayName("Weight Calendar")
        .description("This month's weigh-ins, average and change.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Goal

struct GoalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeightGoal", provider: SnapshotProvider()) { entry in
            GoalRingWidgetView(s: entry.snapshot).systemWidget()
        }
        .configurationDisplayName("Weight Goal")
        .description("Progress from your baseline to your goal.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Monthly rate

struct RateFamilyView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ChangeCircularView(s: entry.snapshot).circularWidget()
        default:
            RateGaugeWidgetView(s: entry.snapshot).systemWidget()
        }
    }
}

struct RateWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeightRate", provider: SnapshotProvider()) { entry in
            RateFamilyView(entry: entry)
        }
        .configurationDisplayName("Rate")
        .description("Monthly rate as a percentage of bodyweight.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

// MARK: - Bundle

struct CoreWidgets: WidgetBundle {
    var body: some Widget {
        WeightStreakWidget()
        TodayWidget()
        WeekBarsWidget()
        WeekListWidget()
        ChartWidget()
    }
}

struct MoreWidgets: WidgetBundle {
    var body: some Widget {
        ComparisonWidget()
        BMIWidget()
        CalendarWidget()
        GoalWidget()
        RateWidget()
    }
}

@main
struct WeightStreakWidgetBundle: WidgetBundle {
    var body: some Widget {
        CoreWidgets().body
        MoreWidgets().body
    }
}
