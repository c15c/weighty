import SwiftUI
import Charts

struct ContentView: View {
    @EnvironmentObject private var store: WeightStore
    @Binding var showLogSheet: Bool

    var body: some View {
        TabView {
            DashboardView(showLogSheet: $showLogSheet)
                .tabItem { Label("Today", systemImage: "flame.fill") }

            JournalView()
                .tabItem { Label("Journal", systemImage: "book.closed.fill") }

            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.line.uptrend.xyaxis") }
        }
        .sheet(isPresented: $showLogSheet) {
            LogWeightView()
        }
    }
}

// MARK: - Today

struct DashboardView: View {
    @EnvironmentObject private var store: WeightStore
    @Binding var showLogSheet: Bool
    @State private var showSettings = false

    private var streak: StreakSummary { store.streak }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    TrendHeroCard()

                    if !store.sharedStorageAvailable {
                        WidgetDataNotice()
                    }

                    Button {
                        showLogSheet = true
                    } label: {
                        Label(streak.loggedToday ? "Update today's weigh-in" : "Log today's weight",
                              systemImage: streak.loggedToday ? "checkmark.circle.fill" : "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(streak.loggedToday ? .green : .accentColor)

                    StreakCard(streak: streak)
                    RateCard()
                    MilestoneCard()
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Weight Streak")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }
}

// MARK: - Trend hero

/// The trend leads and the raw reading plays a supporting role. Reacting to a
/// single morning is what makes people quit; reacting to the trend is what
/// makes them finish.
struct TrendHeroCard: View {
    @EnvironmentObject private var store: WeightStore

    private var trend: Double? { store.trendKilograms }
    private var latest: WeightEntry? { store.latest }
    private var weekChange: Double? { Trend.weekOverWeek(entries: store.entries) }

    var body: some View {
        VStack(spacing: 8) {
            Text("Trend weight")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(trend.map { store.unit.formatted($0) } ?? "--")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            if let weekChange {
                Label(store.unit.formattedDelta(weekChange) + " this week",
                      systemImage: weekChange < 0 ? "arrow.down.right" : (weekChange > 0 ? "arrow.up.right" : "arrow.right"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(weekChange < 0 ? .green : (weekChange > 0 ? .orange : .secondary))
            }

            if let latest {
                Text("Last weigh-in \(store.unit.formatted(latest.kilograms)) · \(latest.date.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let reassurance {
                Text(reassurance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    /// Spell out when a scary reading is just water.
    private var reassurance: String? {
        guard let latest = store.latest,
              let trend,
              let noise = Trend.noise(entries: store.entries) else { return nil }
        let gap = latest.kilograms - trend
        guard abs(gap) > 0.05 else { return nil }
        if abs(gap) <= noise {
            return "That reading is inside your normal daily swing of ±\(store.unit.formatted(noise)). The trend is what moved."
        }
        return gap > 0
            ? "Today read \(store.unit.formattedDelta(gap)) above your trend — usually water, not fat."
            : "Today read \(store.unit.formattedDelta(gap)) below your trend."
    }
}

// MARK: - Streak

struct StreakCard: View {
    let streak: StreakSummary

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 30))
                .foregroundStyle(streak.current > 0 ? .orange : .secondary)

            Text("\(streak.current)")
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            Text(streak.current == 1 ? "day logged" : "days logged")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if streak.criticalToday {
                Text("Log today or the streak ends")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.red)
                    .padding(.top, 2)
            } else if streak.atRisk {
                Text("Yesterday counts — one skipped day is fine")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            } else if streak.loggedToday {
                Text("Logged today")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.green)
                    .padding(.top, 2)
            }

            if streak.longest > 0 {
                Text("Best: \(streak.longest) days")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Rate and projection

struct RateCard: View {
    @EnvironmentObject private var store: WeightStore

    private var rate: Double? { store.weeklyRate }
    private var assessment: RateAssessment? {
        Trend.assessment(weeklyRate: rate, bodyweight: store.trendKilograms)
    }
    private var projection: Date? {
        Trend.projectedGoalDate(entries: store.entries, goal: store.goalKilograms)
    }
    private var plateau: Int? { Trend.plateauDays(entries: store.entries) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rate of change")
                .font(.headline)

            if let rate {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(store.unit.formattedDelta(rate, decimals: 2))
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(rate < 0 ? .green : (rate > 0 ? .orange : .primary))
                    Text("per week")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let assessment {
                    Label(assessment.label, systemImage: icon(for: assessment))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(tint(for: assessment))
                }

                if assessment == .fast {
                    Text("Above about 1% of bodyweight a week, more of the loss comes from muscle and it is harder to hold.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let projection {
                    Divider()
                    HStack {
                        Text("At this rate, goal around")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(projection.formatted(date: .abbreviated, time: .omitted))
                            .font(.footnote.weight(.semibold))
                    }
                }

                if let plateau {
                    Divider()
                    Label("Your trend has held flat for \(plateau) days. That is a genuine plateau, not a bad morning.",
                          systemImage: "equal.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Log for about a week and a reliable rate will appear here. Short windows are mostly noise.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func icon(for assessment: RateAssessment) -> String {
        switch assessment {
        case .gaining:     return "arrow.up.right.circle"
        case .maintaining: return "equal.circle"
        case .steady:      return "checkmark.circle"
        case .fast:        return "exclamationmark.triangle"
        }
    }

    private func tint(for assessment: RateAssessment) -> Color {
        switch assessment {
        case .gaining:     return .orange
        case .maintaining: return .secondary
        case .steady:      return .green
        case .fast:        return .orange
        }
    }
}

// MARK: - Milestones

struct MilestoneCard: View {
    @EnvironmentObject private var store: WeightStore

    private var trend: Double? { store.trendKilograms }
    private var next: Milestone? {
        Milestones.next(start: store.startingKilograms,
                        goal: store.goalKilograms,
                        trend: trend)
    }
    private var percentLost: Double? {
        Milestones.percentLost(start: store.startingKilograms, trend: trend)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Progress")
                .font(.headline)

            if let percentLost, percentLost > 0.05 {
                Text(String(format: "%.1f%% of starting weight lost", percentLost))
                    .font(.title3.weight(.semibold))
            }

            if let next, let trend {
                let remaining = max(trend - next.kilograms, 0)
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: milestoneProgress(next: next, trend: trend))
                        .tint(.accentColor)
                    HStack {
                        Text("Next milestone \(store.unit.formatted(next.kilograms))")
                        Spacer()
                        Text("\(store.unit.formatted(remaining)) to go")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else if store.goalKilograms == nil {
                Text("Set a goal weight in Settings to see milestones and a projected date.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Every milestone reached. Time to pick a new target.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func milestoneProgress(next: Milestone, trend: Double) -> Double {
        let previous = Milestones.lastReached(start: store.startingKilograms,
                                              goal: store.goalKilograms,
                                              trend: trend)?.kilograms
            ?? store.startingKilograms
            ?? trend
        guard previous - next.kilograms > 0.0001 else { return 0 }
        return min(max((previous - trend) / (previous - next.kilograms), 0), 1)
    }
}

// MARK: - Journal

struct JournalView: View {
    @EnvironmentObject private var store: WeightStore
    @State private var showPhotoCompare = false

    private var recent: [WeightEntry] { Array(store.entries.reversed()) }
    private var hasPhotos: Bool { store.entries.contains { !$0.photoFilenames.isEmpty } }

    var body: some View {
        NavigationStack {
            Group {
                if recent.isEmpty {
                    ContentUnavailableView("No journal entries yet",
                                           systemImage: "book.closed",
                                           description: Text("Your weigh-ins, notes, and photos will appear here."))
                } else {
                    List {
                        ForEach(recent) { entry in
                            NavigationLink {
                                EntryDetailView(entryID: entry.id)
                            } label: {
                                JournalRow(entry: entry)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Journal")
            .toolbar {
                if hasPhotos {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showPhotoCompare = true } label: {
                            Image(systemName: "rectangle.on.rectangle.angled")
                        }
                        .accessibilityLabel("Compare photos")
                    }
                }
            }
            .sheet(isPresented: $showPhotoCompare) {
                PhotoCompareView()
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for offset in offsets {
            let entry = recent[offset]
            EntryPhotoStore.delete(entry.photoFilenames)
            store.delete(entry)
        }
    }
}

struct JournalRow: View {
    @EnvironmentObject private var store: WeightStore
    let entry: WeightEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(entry.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
                Spacer()
                Text(store.unit.formatted(entry.kilograms))
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }

            if !entry.knownTags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(entry.knownTags) { tag in
                        Image(systemName: tag.symbol)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let note = entry.note, !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !entry.photoFilenames.isEmpty {
                Label("\(entry.photoFilenames.count)", systemImage: "photo")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 5)
    }
}

// MARK: - Trends

struct TrendsView: View {
    @EnvironmentObject private var store: WeightStore
    @State private var range = 30

    private let ranges = [30, 90, 365]

    var body: some View {
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    ContentUnavailableView("No trends yet",
                                           systemImage: "chart.line.uptrend.xyaxis",
                                           description: Text("Log your first weigh-in to begin."))
                } else {
                    ScrollView {
                        VStack(spacing: 18) {
                            Picker("Range", selection: $range) {
                                Text("30 days").tag(30)
                                Text("3 months").tag(90)
                                Text("Year").tag(365)
                            }
                            .pickerStyle(.segmented)

                            TrendChartCard(days: range)
                            StatsCard()
                            InsightsCard()
                        }
                        .padding()
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("Trends")
        }
    }
}

/// Real dates on the x-axis, the smoothed line as the subject, and a shaded
/// band showing normal daily variation so an ordinary jump reads as ordinary.
struct TrendChartCard: View {
    @EnvironmentObject private var store: WeightStore
    let days: Int

    private var points: [TrendPoint] {
        Trend.series(entries: store.entries, days: days)
    }
    private var noise: Double { Trend.noise(entries: store.entries) ?? 0.4 }

    private var goal: Double? { store.goalKilograms }

    private var domain: ClosedRange<Double> {
        var values = points.flatMap { point -> [Double] in
            var out = [point.trend - noise, point.trend + noise]
            if let actual = point.actual { out.append(actual) }
            return out
        }
        if let goal { values.append(goal) }
        guard let low = values.min(), let high = values.max(), high > low else {
            let center = store.trendKilograms ?? 80
            return (center - 1)...(center + 1)
        }
        let pad = max((high - low) * 0.08, 0.2)
        return store.unit.display(low - pad)...store.unit.display(high + pad)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(days == 30 ? "Last 30 days" : (days == 90 ? "Last 3 months" : "Last year"))
                .font(.headline)

            if points.count > 1 {
                Chart {
                    ForEach(points) { point in
                        AreaMark(x: .value("Date", point.date),
                                 yStart: .value("Low", store.unit.display(point.trend - noise)),
                                 yEnd: .value("High", store.unit.display(point.trend + noise)))
                            .foregroundStyle(Color.accentColor.opacity(0.12))
                    }

                    ForEach(points) { point in
                        LineMark(x: .value("Date", point.date),
                                 y: .value("Trend", store.unit.display(point.trend)))
                            .foregroundStyle(Color.accentColor)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                            .interpolationMethod(.monotone)
                    }

                    ForEach(points.filter { $0.actual != nil }) { point in
                        PointMark(x: .value("Date", point.date),
                                  y: .value("Weigh-in", store.unit.display(point.actual ?? 0)))
                            .symbolSize(18)
                            .foregroundStyle(Color.secondary.opacity(0.55))
                    }

                    if let goal {
                        RuleMark(y: .value("Goal", store.unit.display(goal)))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(Color.green)
                            .annotation(position: .top, alignment: .leading) {
                                Text("Goal")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                    }
                }
                .chartYScale(domain: domain)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 220)

                HStack(spacing: 14) {
                    legend(color: .accentColor, text: "Trend")
                    legend(color: Color.accentColor.opacity(0.25), text: "Normal daily swing")
                    legend(color: Color.secondary.opacity(0.55), text: "Weigh-ins")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else {
                Text("Add another weigh-in to see your trend line.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 4)
            Text(text)
        }
    }
}

// MARK: - Insights

struct InsightsCard: View {
    @EnvironmentObject private var store: WeightStore

    private var insights: [TagInsight] { Insights.tagInsights(entries: store.entries) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What moves your scale")
                .font(.headline)

            if insights.isEmpty {
                Text("Tag a few weigh-ins — alcohol, salty meal, travel, poor sleep — and Weight Streak will show what each one is worth on the scale.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(insights.prefix(5)) { insight in
                    HStack(spacing: 10) {
                        Image(systemName: insight.tag.symbol)
                            .frame(width: 22)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(insight.tag.label)
                                .font(.subheadline.weight(.medium))
                            Text("\(insight.occurrences) days tagged")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text(store.unit.formattedDelta(insight.deviation, decimals: 2))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(insight.deviation > 0 ? .orange : .green)
                    }
                }

                Text("Measured against your trend on those mornings. These swings are almost always water, and they pass.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Stats

struct StatsCard: View {
    @EnvironmentObject private var store: WeightStore

    private var trend: Double? { store.trendKilograms }
    private var change: Double? { Trend.weekOverWeek(entries: store.entries) }
    private var progress: Double? {
        Trend.progress(start: store.startingKilograms,
                       latest: trend,
                       goal: store.goalKilograms)
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                stat("Trend", trend.map { store.unit.formatted($0) } ?? "--")
                Divider()
                stat("Latest", store.latest.map { store.unit.formatted($0.kilograms) } ?? "--")
                Divider()
                stat("vs last week", change.map { store.unit.formattedDelta($0) } ?? "--",
                     tint: change.map { $0 < 0 ? Color.green : ($0 > 0 ? .orange : .primary) })
            }
            .frame(maxWidth: .infinity)

            if let progress, let goal = store.goalKilograms {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: progress)
                        .tint(.accentColor)
                    HStack {
                        Text("\(Int(progress * 100))% to goal")
                        Spacer()
                        Text(store.unit.formatted(goal))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func stat(_ title: String, _ value: String, tint: Color? = nil) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint ?? .primary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Shared container notice

struct WidgetDataNotice: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("Widget cannot read your data")
                    .font(.subheadline.weight(.semibold))
                Text("The shared container was not provisioned during signing. The app itself still works normally.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
