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
    let unit: WeightUnit

    static let placeholder = StreakTimelineEntry(
        date: Date(),
        streak: StreakSummary(current: 12, longest: 21, loggedToday: true),
        latestKilograms: 82.4,
        averageKilograms: 82.9,
        goalKilograms: 78.0,
        progress: 0.42,
        unit: .kilograms
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
        // Refresh hourly so the "log today" prompt appears after midnight.
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
            unit: store.unit
        )
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

    private var small: some View {
        VStack(spacing: 2) {
            Image(systemName: "flame.fill")
                .font(.title3)
                .foregroundStyle(entry.streak.current > 0 ? .orange : .secondary)
            Text("\(entry.streak.current)")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
            Text(statusText)
                .font(.caption2)
                .foregroundStyle(entry.streak.atRisk ? .orange : .secondary)
                .multilineTextAlignment(.center)
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "weightstreak://log"))
    }

    private var medium: some View {
        HStack(spacing: 18) {
            VStack(spacing: 2) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(entry.streak.current > 0 ? .orange : .secondary)
                Text("\(entry.streak.current)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("day streak")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 92)

            VStack(alignment: .leading, spacing: 8) {
                row("Latest", entry.latestKilograms.map { entry.unit.formatted($0) } ?? "--")
                row("7 day avg", entry.averageKilograms.map { entry.unit.formatted($0) } ?? "--")

                if let progress = entry.progress {
                    ProgressView(value: progress)
                        .tint(.accentColor)
                    Text("\(Int(progress * 100))% to goal")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(statusText)
                        .font(.caption2)
                        .foregroundStyle(entry.streak.atRisk ? .orange : .secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "weightstreak://log"))
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "flame.fill").font(.caption2)
                Text("\(entry.streak.current)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "weightstreak://log"))
    }

    private var inline: some View {
        Text("\(entry.streak.current) day streak")
            .widgetURL(URL(string: "weightstreak://log"))
    }

    private var statusText: String {
        if entry.streak.loggedToday { return "Logged today" }
        if entry.streak.atRisk { return "Log to keep it" }
        return "Tap to start"
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
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
        .description("Your logging streak and trend toward your goal.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryInline])
    }
}

@main
struct WeightStreakWidgetBundle: WidgetBundle {
    var body: some Widget {
        WeightStreakWidget()
    }
}
