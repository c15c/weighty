import WidgetKit
import SwiftUI

// MARK: - Timeline

struct StreakTimelineEntry: TimelineEntry {
    let date: Date
    let streak: StreakSummary
    let trendKilograms: Double?
    let latestKilograms: Double?
    let weeklyRate: Double?
    let goalKilograms: Double?
    let progress: Double?
    let recent: [Double]
    let unit: WeightUnit
    let sharedStorageAvailable: Bool

    /// Distance still to cover, never negative.
    var remainingKilograms: Double? {
        guard let trendKilograms, let goalKilograms else { return nil }
        return max(trendKilograms - goalKilograms, 0)
    }

    static let placeholder = StreakTimelineEntry(
        date: Date(),
        streak: StreakSummary(current: 12,
                              longest: 21,
                              loggedToday: false,
                              usingGrace: false,
                              daysSinceLastLog: 1,
                              lastChange: -0.4),
        trendKilograms: 82.7,
        latestKilograms: 82.4,
        weeklyRate: -0.42,
        goalKilograms: 78.0,
        progress: 0.42,
        recent: [85.1, 84.9, 84.7, 84.5, 84.2, 84.0, 83.8, 83.4, 83.1, 82.7],
        unit: .kilograms,
        sharedStorageAvailable: true
    )
}

struct StreakProvider: TimelineProvider {

    func placeholder(in context: Context) -> StreakTimelineEntry { .placeholder }

    func getSnapshot(in context: Context,
                     completion: @escaping (StreakTimelineEntry) -> Void) {
        completion(context.isPreview ? .placeholder : current())
    }

    func getTimeline(in context: Context,
                     completion: @escaping (Timeline<StreakTimelineEntry>) -> Void) {
        // Refresh hourly so the "weigh in today" prompt appears after midnight.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [current()], policy: .after(next)))
    }

    private func current() -> StreakTimelineEntry {
        let store = WeightStore()
        return StreakTimelineEntry(
            date: Date(),
            streak: store.streak,
            trendKilograms: store.trendKilograms,
            latestKilograms: store.latest?.kilograms,
            weeklyRate: store.weeklyRate,
            goalKilograms: store.goalKilograms,
            progress: Trend.progress(start: store.startingKilograms,
                                     latest: store.trendKilograms,
                                     goal: store.goalKilograms),
            recent: Trend.recentValues(entries: store.entries, days: 30),
            unit: store.unit,
            sharedStorageAvailable: store.sharedStorageAvailable
        )
    }
}

// MARK: - Sparkline

/// Hand drawn rather than charted, so the widget carries no framework it does not need.
struct Sparkline: View {
    let values: [Double]
    let goal: Double?

    private var bounds: (low: Double, high: Double) {
        var low = values.min() ?? 0
        var high = values.max() ?? 1
        if let goal {
            low = Swift.min(low, goal)
            high = Swift.max(high, goal)
        }
        // A flat line would divide by zero, so give it a little air.
        if high - low < 0.2 {
            low -= 0.1
            high += 0.1
        }
        return (low, high)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let (low, high) = bounds
        let span = high - low
        return values.enumerated().map { index, value in
            CGPoint(x: size.width * CGFloat(index) / CGFloat(values.count - 1),
                    y: size.height - size.height * CGFloat((value - low) / span))
        }
    }

    private func goalY(in size: CGSize) -> CGFloat? {
        guard let goal else { return nil }
        let (low, high) = bounds
        return size.height - size.height * CGFloat((goal - low) / (high - low))
    }

    var body: some View {
        GeometryReader { geometry in
            let linePoints = points(in: geometry.size)

            ZStack {
                Path { path in
                    guard let first = linePoints.first, let last = linePoints.last else { return }
                    path.move(to: CGPoint(x: first.x, y: geometry.size.height))
                    linePoints.forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: last.x, y: geometry.size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [Color.accentColor.opacity(0.35),
                                              Color.accentColor.opacity(0.02)],
                                     startPoint: .top,
                                     endPoint: .bottom))

                Path { path in
                    guard let first = linePoints.first else { return }
                    path.move(to: first)
                    linePoints.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(Color.accentColor,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                if let y = goalY(in: geometry.size) {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                    .stroke(Color.green.opacity(0.7),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
        }
    }
}

// MARK: - Views

struct StreakWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StreakTimelineEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryInline:   inline
        case .systemMedium:      medium
        default:                 small
        }
    }

    // Trend first, everywhere. The raw reading never leads.
    private var small: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("TREND")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(entry.trendKilograms.map { entry.unit.formatted($0) } ?? "--")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            if let rate = entry.weeklyRate {
                Text("\(entry.unit.formattedDelta(rate, decimals: 2))/wk")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(rate < 0 ? .green : (rate > 0 ? .orange : .secondary))
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.caption2)
                    .foregroundStyle(entry.streak.current > 0 ? .orange : .secondary)
                Text("\(entry.streak.current)d")
                    .font(.caption2.weight(.semibold))
                Spacer()
                if entry.streak.loggedToday {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "weightstreak://log"))
    }

    private var medium: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("TREND")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(entry.trendKilograms.map { entry.unit.formatted($0) } ?? "--")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let rate = entry.weeklyRate {
                    Text("\(entry.unit.formattedDelta(rate, decimals: 2)) per week")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(rate < 0 ? .green : (rate > 0 ? .orange : .secondary))
                        .lineLimit(1)
                }

                Spacer(minLength: 2)

                HStack(spacing: 5) {
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(entry.streak.current > 0 ? .orange : .secondary)
                    Text("\(entry.streak.current) day\(entry.streak.current == 1 ? "" : "s")")
                        .font(.caption2.weight(.semibold))
                    if entry.streak.loggedToday {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }

                Text(entry.streak.loggedToday ? "Tap to update" : "Tap to log today")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if entry.recent.count > 1 {
                VStack(alignment: .trailing, spacing: 4) {
                    Sparkline(values: entry.recent, goal: entry.goalKilograms)
                        .frame(height: 78)
                    if let remaining = entry.remainingKilograms, remaining > 0.05 {
                        Text("\(entry.unit.formatted(remaining)) to goal")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 150)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "weightstreak://log"))
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "flame.fill")
                    .font(.caption2)
                Text("\(entry.streak.current)")
                    .font(.headline.weight(.bold))
                    .monospacedDigit()
            }
        }
        .widgetURL(URL(string: "weightstreak://log"))
    }

    private var inline: some View {
        let trend = entry.trendKilograms.map { entry.unit.formatted($0) } ?? "--"
        let rate = entry.weeklyRate.map { " · \(entry.unit.formattedDelta($0, decimals: 2))/wk" } ?? ""
        return Text("\(trend)\(rate)")
            .widgetURL(URL(string: "weightstreak://log"))
    }
}

// MARK: - Widget

struct WeightStreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeightStreakWidget", provider: StreakProvider()) { entry in
            StreakWidgetView(entry: entry)
        }
        .configurationDisplayName("Weight Streak")
        .description("Your trend weight, weekly rate, and streak. Tap to log.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryInline])
    }
}

@main
struct WeightStreakWidgetBundle: WidgetBundle {
    var body: some Widget {
        WeightStreakWidget()
    }
}
