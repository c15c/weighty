import SwiftUI
import Charts

// MARK: - Today

struct TodayView: View {
    @EnvironmentObject private var store: WeightStore
    @Binding var showLogSheet: Bool

    @State private var confettiStart: Date?
    @State private var pendingCelebration = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        let s = WidgetSnapshot.make(store: store)
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TodayHero(s: s, highlight: LowHighlight.evaluate(entries: store.entries))

                    if !store.sharedStorageAvailable {
                        WidgetDataNotice()
                    }

                    LogButton(loggedToday: s.streak.loggedToday) {
                        showLogSheet = true
                    }

                    WeekStrip(s: s)

                    LazyVGrid(columns: columns, spacing: 12) {
                        StreakTile(streak: s.streak)
                        ChangeTile(s: s)
                        RateTile(s: s)
                        if let bmi = s.bmi {
                            BMITile(bmi: bmi)
                        } else {
                            GoalTile(s: s)
                        }
                    }

                    MomentumCard(s: s)
                    MilestoneCard()
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Text(Date(), format: .dateTime.weekday(.wide).day().month(.abbreviated)))
        }
        .overlay {
            if let confettiStart {
                ConfettiBurst(start: confettiStart)
                    .id(confettiStart)
            }
        }
        .sensoryFeedback(.success, trigger: confettiStart)
        .onChange(of: store.entries) { old, new in
            let calendar = Calendar.current
            guard let after = new.first(where: { calendar.isDateInToday($0.date) }) else { return }
            if let before = old.first(where: { calendar.isDateInToday($0.date) }),
               before.kilograms == after.kilograms {
                return
            }
            if showLogSheet {
                pendingCelebration = true
            } else {
                celebrate(after: 0)
            }
        }
        .onChange(of: showLogSheet) { _, open in
            guard !open, pendingCelebration else { return }
            pendingCelebration = false
            celebrate(after: 0.35)
        }
    }

    private func celebrate(after delay: Double) {
        Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            let start = Date()
            confettiStart = start
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            if confettiStart == start {
                confettiStart = nil
            }
        }
    }
}

// MARK: - Hero

struct TodayHero: View {
    @EnvironmentObject private var store: WeightStore
    let s: WidgetSnapshot
    let highlight: LowHighlight?

    @State private var shown = false

    private var losing: Bool { (s.period.change ?? 0) <= 0 }
    private var loggedThisWeek: Int { s.week.filter { $0.kilograms != nil }.count }

    private var backgroundColors: [Color] {
        if losing {
            return [Color(red: 0.04, green: 0.13, blue: 0.36), Color(red: 0.14, green: 0.38, blue: 0.86)]
        }
        return [Color(red: 0.32, green: 0.07, blue: 0.20), Color(red: 0.86, green: 0.32, blue: 0.36)]
    }

    private var latestLine: String? {
        guard let kilograms = s.latest, let date = s.latestDate else { return nil }
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(date) {
            day = "Today"
        } else if calendar.isDateInYesterday(date) {
            day = "Yesterday"
        } else {
            day = date.formatted(.dateTime.day().month(.abbreviated))
        }
        let time: String = store.latest?.loggedAt.map { " " + $0.formatted(date: .omitted, time: .shortened) } ?? ""
        return "Last weigh-in \(s.unit.formatted(kilograms)) · \(day)\(time)"
    }

    var body: some View {
        let goalProgress: Double = shown ? (s.progress ?? 0) : 0
        let weekProgress: Double = shown ? Double(loggedThisWeek) / 7 : 0
        VStack(spacing: 14) {
            ZStack {
                ActivityRing(progress: goalProgress,
                             lineWidth: 16,
                             colors: [Color(red: 0.35, green: 0.85, blue: 1.0), Color.white])
                    .frame(width: 214, height: 214)
                ActivityRing(progress: weekProgress,
                             lineWidth: 12,
                             colors: [Color.orange, Color.yellow])
                    .frame(width: 172, height: 172)
                VStack(spacing: 0) {
                    Text("TREND")
                        .font(.caption2.weight(.bold))
                        .tracking(1.5)
                        .opacity(0.7)
                    Text(s.unit.number(s.trend))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(s.unit.short)
                        .font(.headline)
                        .opacity(0.7)
                }
                .foregroundStyle(.white)
                .frame(width: 130)
            }
            .padding(.top, 4)

            HStack(spacing: 8) {
                if let change = s.period.change {
                    HeroChip(icon: Indicators.direction(for: change).arrow,
                             text: "\(s.unit.formattedDelta(change)) · \(s.period.days)d")
                }
                if s.goal != nil {
                    HeroChip(icon: "target", text: "\(Int(((s.progress ?? 0) * 100).rounded()))%", dot: Color(red: 0.35, green: 0.85, blue: 1.0))
                }
                HeroChip(icon: "calendar", text: "\(loggedThisWeek)/7", dot: .orange)
            }

            if let highlight {
                HeroChip(icon: "star.fill", text: highlight.label, prominent: true)
            }

            if let latestLine {
                Text(latestLine)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal)
        .background(LinearGradient(colors: backgroundColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: backgroundColors[1].opacity(0.35), radius: 18, y: 8)
        .onAppear {
            withAnimation(.spring(duration: 1.3, bounce: 0.2).delay(0.15)) {
                shown = true
            }
        }
    }
}

struct ActivityRing: View {
    var progress: Double
    var lineWidth: CGFloat
    var colors: [Color]

    var body: some View {
        let clamped = CGFloat(Swift.min(Swift.max(progress, 0), 1))
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.13), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(AngularGradient(colors: colors, center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
    }
}

struct HeroChip: View {
    let icon: String
    let text: String
    var dot: Color? = nil
    var prominent = false

    var body: some View {
        HStack(spacing: 5) {
            if let dot {
                Circle()
                    .fill(dot)
                    .frame(width: 7, height: 7)
            }
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
            Text(text)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(prominent ? Color.black : Color.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(prominent ? Color.yellow : Color.white.opacity(0.16), in: Capsule())
    }
}

// MARK: - Log button

struct LogButton: View {
    let loggedToday: Bool
    let action: () -> Void

    @State private var pulse = false

    private var colors: [Color] {
        loggedToday ? [Color.weightGoal, Color(red: 0.12, green: 0.62, blue: 0.55)] : [Color.orange, Color.pink]
    }

    var body: some View {
        let glow: Bool = pulse && !loggedToday
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: loggedToday ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.title2)
                Text(loggedToday ? "Update today's weigh-in" : "Log today's weight")
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing), in: Capsule())
            .shadow(color: colors[0].opacity(glow ? 0.6 : 0.25), radius: glow ? 16 : 6, y: 4)
        }
        .buttonStyle(PressableStyle())
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

// MARK: - Week strip

struct WeekStrip: View {
    let s: WidgetSnapshot

    private var average: Double? {
        let values = s.week.compactMap(\.kilograms)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week")
                    .font(.headline)
                Spacer()
                if let average {
                    Text("avg \(s.unit.formatted(average))")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 4) {
                ForEach(Array(s.week.enumerated()), id: \.offset) { index, cell in
                    WeekDayColumn(symbol: index < s.weekdaySymbols.count ? s.weekdaySymbols[index] : "",
                                  cell: cell,
                                  unit: s.unit)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct WeekDayColumn: View {
    let symbol: String
    let cell: DayCell
    let unit: WeightUnit

    var body: some View {
        let tint: Color = cell.direction?.color ?? Color.secondary
        let logged = cell.kilograms != nil
        VStack(spacing: 6) {
            Text(symbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(cell.isToday ? Color.primary : Color.secondary)
            ZStack {
                Circle()
                    .fill(logged ? tint.opacity(0.2) : Color.weightEmpty)
                if logged {
                    Image(systemName: (cell.direction ?? .flat).arrow)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(tint)
                }
            }
            .frame(width: 34, height: 34)
            .overlay(Circle().strokeBorder(cell.isToday ? Color.primary.opacity(0.6) : Color.clear, lineWidth: 1.5))
            Text(cell.kilograms.map { unit.number($0) } ?? "–")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .opacity(cell.isFuture ? 0.45 : 1)
    }
}

// MARK: - Tiles

struct TodayTile<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    let content: Content

    init(_ title: String, icon: String, tint: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(tint)
            content
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .padding(14)
        .background(LinearGradient(colors: [tint.opacity(0.24), tint.opacity(0.05)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct StreakTile: View {
    let streak: StreakSummary

    private var status: String {
        if streak.loggedToday { return "Logged today" }
        if streak.criticalToday { return "Ends today" }
        if streak.current > 0 { return "Not logged today" }
        return ""
    }

    private var statusColor: Color {
        if streak.loggedToday { return .weightGoal }
        if streak.criticalToday { return .red }
        return .orange
    }

    var body: some View {
        TodayTile("Streak", icon: "flame.fill", tint: .orange) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(streak.current)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(streak.current == 1 ? "day" : "days")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if !status.isEmpty {
                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
            }
            Text("Best \(streak.longest)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct ChangeTile: View {
    let s: WidgetSnapshot

    private var gained: Bool { (s.lost ?? 0) < 0 }

    private var name: String {
        guard let comparison = s.comparison else { return "No change yet" }
        let first: String = comparison.name.prefix(1).uppercased()
        let rest = String(comparison.name.dropFirst())
        return first + rest
    }

    var body: some View {
        TodayTile(gained ? "Gained" : "Shed",
                  icon: "scalemass.fill",
                  tint: gained ? Color.weightUp : Color.weightDown) {
            Text(s.comparison?.emoji ?? "⚖️")
                .font(.system(size: 34))
            Text(name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if let lost = s.lost {
                Text(s.unit.formattedDelta(-lost))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct RateTile: View {
    let s: WidgetSnapshot

    private let sweep = 220.0
    private let maximum = 5.0

    var body: some View {
        let percent = s.percentPerMonth
        let losing = (percent ?? 0) <= 0
        let tint: Color = losing ? Color.weightDown : Color.weightUp
        let fraction: Double = Swift.min(abs(percent ?? 0) / maximum, 1)
        TodayTile("Monthly rate", icon: "gauge.with.dots.needle.33percent", tint: tint) {
            ZStack {
                GaugeArc(sweep: sweep, inset: 5)
                    .stroke(tint.opacity(0.2), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                GaugeArc(to: fraction, sweep: sweep, inset: 5)
                    .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                Text(percent.map { String(format: "%.1f%%", abs($0)) } ?? "--")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .offset(y: 6)
            }
            .frame(height: 62)
            Text(percent == nil ? "Not enough data" : (losing ? "Losing per month" : "Gaining per month"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct BMITile: View {
    let bmi: Double

    var body: some View {
        let category = BMI.category(bmi)
        TodayTile("BMI", icon: "figure.stand", tint: category.color) {
            Text(String(format: "%.1f", bmi))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
            BMIBar(bmi: bmi)
                .frame(height: 6)
                .padding(.vertical, 2)
            Text(category.label)
                .font(.caption.weight(.semibold))
        }
    }
}

struct GoalTile: View {
    let s: WidgetSnapshot

    var body: some View {
        TodayTile("Goal", icon: "target", tint: .weightGoal) {
            if let goal = s.goal {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(s.unit.number(s.remaining))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("\(s.unit.short) to go")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: Swift.min(Swift.max(s.progress ?? 0, 0), 1))
                    .tint(Color.weightGoal)
                Text("Goal \(s.unit.formatted(goal))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("--")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
            }
        }
    }
}

// MARK: - 30-day momentum

struct MomentumCard: View {
    let s: WidgetSnapshot

    private var points: [TrendPoint] { s.chart }
    private var readings: [TrendPoint] { s.chart.filter { $0.actual != nil } }

    private var change: Double? {
        guard points.count > 1, let first = points.first, let last = points.last else { return nil }
        return last.trend - first.trend
    }

    private var domain: ClosedRange<Double> {
        let trends: [Double] = points.map { s.unit.display($0.trend) }
        let actuals: [Double] = readings.compactMap { $0.actual }.map { s.unit.display($0) }
        let values: [Double] = trends + actuals
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let pad: Double = Swift.max((high - low) * 0.15, 0.3)
        return (low - pad)...(high + pad)
    }

    var body: some View {
        let tint: Color = Indicators.direction(for: change).color
        let domain = self.domain
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("30 days")
                    .font(.headline)
                Spacer()
                if let change {
                    Label(s.unit.formattedDelta(change), systemImage: Indicators.direction(for: change).arrow)
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                }
            }
            if points.count > 1 {
                Chart {
                    ForEach(points) { point in
                        AreaMark(x: .value("Date", point.date),
                                 yStart: .value("Base", domain.lowerBound),
                                 yEnd: .value("Trend", s.unit.display(point.trend)))
                            .foregroundStyle(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0.0)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("Date", point.date),
                                 y: .value("Trend", s.unit.display(point.trend)))
                            .foregroundStyle(tint)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                            .interpolationMethod(.catmullRom)
                    }
                    ForEach(readings) { point in
                        PointMark(x: .value("Date", point.date),
                                  y: .value("Weight", s.unit.display(point.actual ?? 0)))
                            .foregroundStyle(tint.opacity(0.45))
                            .symbolSize(16)
                    }
                }
                .chartYScale(domain: domain)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3))
                }
                .frame(height: 150)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Highlights

enum LowHighlight: Equatable {
    case allTime
    case since(Date)

    var label: String {
        switch self {
        case .allTime:
            return "Lowest ever"
        case .since(let date):
            return "Lowest since \(date.formatted(.dateTime.day().month(.abbreviated).year()))"
        }
    }

    /// Whether the latest weigh-in is the lowest in a while.
    static func evaluate(entries: [WeightEntry], now: Date = Date()) -> LowHighlight? {
        let sorted = entries.sorted { $0.date < $1.date }
        guard sorted.count >= 5, let latest = sorted.last else { return nil }
        let calendar = Calendar.current
        let age = calendar.dateComponents([.day], from: latest.date, to: now).day ?? 0
        guard age <= 3 else { return nil }
        let earlier = sorted.dropLast()
        guard let lower = earlier.last(where: { $0.kilograms <= latest.kilograms }) else { return .allTime }
        let gap = calendar.dateComponents([.day], from: lower.date, to: latest.date).day ?? 0
        return gap >= 14 ? .since(lower.date) : nil
    }
}

// MARK: - Confetti

struct ConfettiBurst: View {
    let start: Date

    @State private var pieces: [ConfettiPiece] = (0..<90).map { _ in ConfettiPiece.random() }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = CGFloat(timeline.date.timeIntervalSince(start))
                for piece in pieces {
                    piece.draw(in: context, canvas: size, time: elapsed)
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

struct ConfettiPiece {
    let originX: CGFloat
    let velocityX: CGFloat
    let velocityY: CGFloat
    let spin: Double
    let width: CGFloat
    let height: CGFloat
    let color: Color

    static let palette: [Color] = [.weightDown, .weightGoal, .orange, .pink, .yellow, .purple]

    static func random() -> ConfettiPiece {
        ConfettiPiece(originX: CGFloat.random(in: 0.2...0.8),
                      velocityX: CGFloat.random(in: (-240)...240),
                      velocityY: CGFloat.random(in: (-950)...(-450)),
                      spin: Double.random(in: (-720)...720),
                      width: CGFloat.random(in: 6...11),
                      height: CGFloat.random(in: 3...6),
                      color: palette.randomElement() ?? .orange)
    }

    func draw(in context: GraphicsContext, canvas: CGSize, time: CGFloat) {
        let gravity: CGFloat = 1400
        let fade: CGFloat = Swift.max(0, 1 - time / 2.6)
        guard fade > 0 else { return }
        let x: CGFloat = canvas.width * originX + velocityX * time
        let y: CGFloat = canvas.height * 0.35 + velocityY * time + gravity * time * time / 2
        var copy = context
        copy.opacity = Double(fade)
        copy.translateBy(x: x, y: y)
        copy.rotate(by: .degrees(spin * Double(time)))
        let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
        copy.fill(Path(rect), with: .color(color))
    }
}
