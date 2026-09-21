import WidgetKit
import SwiftUI

// MARK: - Timeline

struct StreakTimelineEntry: TimelineEntry {
    let date: Date
    let streak: StreakSummary
    let latestKilograms: Double?
    let averageKilograms: Double?
    let goalKilograms: Double?
    let progress: Double?
    let recent: [Double]
    let unit: WeightUnit
    let sharedStorageAvailable: Bool

    /// Distance still to cover, never negative.
    var remainingKilograms: Double? {
        guard let latestKilograms, let goalKilograms else { return nil }
        return max(latestKilograms - goalKilograms, 0)
    }

    static let placeholder = StreakTimelineEntry(
        date: Date(),
        streak: StreakSummary(current: 5, longest: 9, loggedToday: true, lastChange: -0.4),
        latestKilograms: 82.4,
        averageKilograms: 82.9,
        goalKilograms: 78.0,
        progress: 0.42,
        recent: [85.1, 84.8, 84.9, 84.2, 84.0, 83.6, 83.7, 83.1, 82.8, 82.4],
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
        let latest = store.latest?.kilograms
        return StreakTimelineEntry(
            date: Date(),
            streak: store.streak,
            latestKilograms: latest,
            averageKilograms: Trend.average(entries: store.entries, days: 7),
            goalKilograms: store.goalKilograms,
            progress: Trend.progress(start: store.startingKilograms,
                                     latest: latest,
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
                .fill(LinearGradient(colors: [.orange.opacity(0.35), .orange.opacity(0.02)],
                                     startPoint: .top,
                                     endPoint: .bottom))

                if let y = goalY(in: geometry.size) {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                    .stroke(.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }

                Path { path in
                    guard let first = linePoints.first else { return }
                    path.move(to: first)
                    linePoints.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(LinearGradient(colors: [.pink, .orange],
                                       startPoint: .leading,
                                       endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                if let last = linePoints.last {
                    Circle()
                        .fill(.orange)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(.background, lineWidth: 1.5))
                        .position(last)
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
        case .systemMedium: medium
        case .accessoryCircular: circular
        case .accessoryInline: inline
        default: small
        }
    }

    // MARK: Small: streak inside a ring of progress toward the goal

    private var small: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 10)

                Circle()
                    .trim(from: 0, to: CGFloat(entry.progress ?? 0))
                    .stroke(AngularGradient(colors: [.pink, .orange, .yellow, .pink],
                                            center: .center,
                                            startAngle: .degrees(0),
                                            endAngle: .degrees(360)),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: -4) {
                    Text("\(entry.streak.current)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                    Text("STREAK")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 2)

            VStack(spacing: 1) {
                Text(goalValue)
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .monospacedDigit()
                Text(goalCaption)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "weightstreak://log"))
    }

    // MARK: Medium: streak, delta, sparkline against the goal line

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill").font(.system(size: 10))
                    Text("STREAK")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.1)
                }
                .foregroundStyle(entry.streak.current > 0 ? .orange : .secondary)

                Text("\(entry.streak.current)")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                if let change = entry.streak.lastChange {
                    deltaChip(change)
                } else {
                    Text("First weigh-in")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Text(statusText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(entry.streak.atRisk ? .orange : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 104, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.latestKilograms.map { entry.unit.formatted($0) } ?? "--")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .monospacedDigit()
                    Spacer()
                    Text(goalLine)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                if entry.recent.count > 1 {
                    Sparkline(values: entry.recent, goal: entry.goalKilograms)
                        .frame(maxHeight: .infinity)
                } else {
                    Spacer(minLength: 0)
                }

                if let progress = entry.progress {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule()
                                .fill(LinearGradient(colors: [.pink, .orange],
                                                     startPoint: .leading,
                                                     endPoint: .trailing))
                                .frame(width: geometry.size.width * CGFloat(progress))
                        }
                    }
                    .frame(height: 5)
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "weightstreak://log"))
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            Circle()
                .trim(from: 0, to: CGFloat(entry.progress ?? 0))
                .stroke(.primary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(1)
            VStack(spacing: -2) {
                Image(systemName: "flame.fill").font(.system(size: 9))
                Text("\(entry.streak.current)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "weightstreak://log"))
    }

    private var inline: some View {
        Text(inlineText)
            .widgetURL(URL(string: "weightstreak://log"))
    }

    // MARK: Pieces

    private func deltaChip(_ change: Double) -> some View {
        let losing = change < 0
        return HStack(spacing: 2) {
            Image(systemName: losing ? "arrow.down.right" : "arrow.up.right")
                .font(.system(size: 9, weight: .bold))
            Text(entry.unit.formattedDelta(change))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(losing ? .green : .secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    /// The headline number under the ring: what is left to lose.
    private var goalValue: String {
        guard entry.goalKilograms != nil else { return "No goal" }
        guard let remaining = entry.remainingKilograms else { return "--" }
        return remaining < 0.05 ? "Reached" : entry.unit.formatted(remaining)
    }

    private var goalCaption: String {
        guard entry.goalKilograms != nil else { return "set one in the app" }
        guard let remaining = entry.remainingKilograms, remaining >= 0.05 else { return "goal met" }
        return "to goal"
    }

    /// One line version for the medium layout.
    private var goalLine: String {
        guard entry.goalKilograms != nil else { return "No goal set" }
        guard let remaining = entry.remainingKilograms, remaining >= 0.05 else { return "Goal met" }
        return "\(entry.unit.formatted(remaining)) to goal"
    }

    private var statusText: String {
        if !entry.sharedStorageAvailable { return "Open app" }
        if entry.streak.loggedToday { return "Weighed in today" }
        if entry.streak.atRisk { return "Weigh in today" }
        return "Tap to log"
    }

    private var inlineText: String {
        guard let remaining = entry.remainingKilograms, remaining >= 0.05 else {
            return "Streak \(entry.streak.current)"
        }
        return "Streak \(entry.streak.current) · \(entry.unit.formatted(remaining)) to goal"
    }
}

// MARK: - Widget

struct WeightStreakWidget: Widget {
    let kind = "WeightStreakWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StreakProvider()) { entry in
            StreakWidgetView(entry: entry)
        }
        .configurationDisplayName("Weight Streak")
        .description("Consecutive weigh-ins going down, and how far you are from your goal.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryInline])
    }
}

@main
struct WeightStreakWidgetBundle: WidgetBundle {
    var body: some Widget {
        WeightStreakWidget()
    }
}
