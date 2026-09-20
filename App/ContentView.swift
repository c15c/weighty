import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: WeightStore
    @Binding var showLogSheet: Bool
    @State private var showSettings = false

    private var streak: StreakSummary { store.streak }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    StreakCard(streak: streak)

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

                    StatsCard()

                    if store.entries.count > 1 {
                        TrendCard()
                    }

                    HistorySection()
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Weight Streak")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showLogSheet) {
                LogWeightView().environmentObject(store)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView().environmentObject(store)
            }
        }
    }
}

// MARK: - Streak

struct StreakCard: View {
    let streak: StreakSummary

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 34))
                .foregroundStyle(streak.current > 0 ? .orange : .secondary)

            Text("\(streak.current)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            Text(streak.current == 1 ? "day streak" : "day streak")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if streak.atRisk {
                Text("Log today to keep it")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.orange)
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
        .padding(.vertical, 24)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Stats

struct StatsCard: View {
    @EnvironmentObject private var store: WeightStore

    private var average: Double? { Trend.average(entries: store.entries, days: 7) }
    private var change: Double? { Trend.weekOverWeek(entries: store.entries) }
    private var progress: Double? {
        Trend.progress(start: store.startingKilograms,
                       latest: store.latest?.kilograms,
                       goal: store.goalKilograms)
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                stat("Latest", store.latest.map { store.unit.formatted($0.kilograms) } ?? "--")
                Divider()
                stat("7 day avg", average.map { store.unit.formatted($0) } ?? "--")
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

// MARK: - Trend

struct TrendCard: View {
    @EnvironmentObject private var store: WeightStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last 30 days")
                .font(.caption)
                .foregroundStyle(.secondary)
            Sparkline(values: Trend.recentValues(entries: store.entries))
                .frame(height: 70)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct Sparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            if values.count > 1 {
                let minValue = values.min() ?? 0
                let maxValue = values.max() ?? 1
                let range = max(maxValue - minValue, 0.5)

                Path { path in
                    for (index, value) in values.enumerated() {
                        let x = geo.size.width * CGFloat(index) / CGFloat(values.count - 1)
                        let y = geo.size.height * (1 - CGFloat((value - minValue) / range))
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(Color.accentColor,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// MARK: - History

struct HistorySection: View {
    @EnvironmentObject private var store: WeightStore

    private var recent: [WeightEntry] { store.entries.reversed().prefix(14).map { $0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("History")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            if recent.isEmpty {
                Text("No weigh-ins yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                ForEach(recent) { entry in
                    HStack {
                        Text(entry.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                            .font(.callout)
                        Spacer()
                        Text(store.unit.formatted(entry.kilograms))
                            .font(.callout.weight(.medium))
                            .monospacedDigit()
                    }
                    .padding(.vertical, 10)
                    .contextMenu {
                        Button("Delete", role: .destructive) { store.delete(entry) }
                    }
                    if entry.id != recent.last?.id { Divider() }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
