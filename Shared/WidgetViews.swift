import SwiftUI
import Charts

// MARK: - Palette

extension Color {
    static let weightDown = Color(red: 0.23, green: 0.62, blue: 0.98)
    static let weightUp = Color(red: 0.93, green: 0.37, blue: 0.35)
    static let weightGoal = Color(red: 0.20, green: 0.74, blue: 0.40)
    static let weightEmpty = Color.secondary.opacity(0.2)
}

extension WeightDirection {
    var color: Color {
        switch self {
        case .down: return .weightDown
        case .up:   return .weightUp
        case .flat: return .weightDown
        }
    }

    var arrow: String {
        switch self {
        case .down: return "arrow.down"
        case .up:   return "arrow.up"
        case .flat: return "arrow.right"
        }
    }
}

extension BMICategory {
    var color: Color {
        switch self {
        case .underweight: return Color(red: 0.35, green: 0.78, blue: 0.95)
        case .healthy:     return Color(red: 0.55, green: 0.85, blue: 0.25)
        case .overweight:  return Color(red: 0.98, green: 0.80, blue: 0.30)
        case .obese1:      return Color(red: 0.98, green: 0.60, blue: 0.35)
        case .obese2:      return Color(red: 0.95, green: 0.45, blue: 0.40)
        case .obese3:      return Color(red: 0.85, green: 0.30, blue: 0.35)
        }
    }
}

extension WeightUnit {
    /// Number only, in the display unit.
    func number(_ kilograms: Double?, decimals: Int = 1) -> String {
        guard let kilograms else { return "--" }
        return String(format: "%.\(decimals)f", display(kilograms))
    }
}

// MARK: - Building blocks

struct WeightValueText: View {
    let kilograms: Double?
    let unit: WeightUnit
    var size: CGFloat = 30
    var weight: Font.Weight = .semibold

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(unit.number(kilograms))
                .font(.system(size: size, weight: weight, design: .rounded))
                .monospacedDigit()
            Text(unit.short)
                .font(.system(size: max(size * 0.45, 10), weight: .semibold, design: .rounded))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// Arrow chip plus signed-less amount, coloured by direction.
struct ChangeLabel: View {
    let kilograms: Double?
    let unit: WeightUnit
    var size: CGFloat = 15

    var body: some View {
        let direction = Indicators.direction(for: kilograms)
        HStack(spacing: 4) {
            Image(systemName: direction.arrow)
                .font(.system(size: size * 0.6, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size * 1.15, height: size * 1.15)
                .background(direction.color, in: Circle())
            WeightValueText(kilograms: kilograms.map { abs($0) }, unit: unit, size: size)
        }
    }
}

struct DayDot: View {
    let cell: DayCell
    var size: CGFloat = 10

    var body: some View {
        ZStack {
            if cell.isToday {
                Circle()
                    .strokeBorder(cell.direction?.color ?? .secondary, lineWidth: 1.5)
                    .frame(width: size + 5, height: size + 5)
            }
            Circle()
                .fill(cell.direction?.color ?? Color.weightEmpty)
                .frame(width: size, height: size)
        }
        .frame(width: size + 5, height: size + 5)
    }
}

/// An arc symmetric about the top, `sweep` degrees wide. Fractions run left to right.
struct GaugeArc: Shape {
    var from: Double = 0
    var to: Double = 1
    var sweep: Double = 240
    var inset: CGFloat = 0

    static func point(_ fraction: Double, in rect: CGRect, sweep: Double, inset: CGFloat) -> CGPoint {
        let area = rect.insetBy(dx: inset, dy: inset)
        let startAngle = (90 + sweep / 2) * .pi / 180
        let below = max(0, -sin(startAngle))
        let radius = min(area.width / 2, area.height / (1 + below))
        let center = CGPoint(x: area.midX, y: area.minY + radius)
        let theta = startAngle - fraction * sweep * .pi / 180
        return CGPoint(x: center.x + radius * cos(theta), y: center.y - radius * sin(theta))
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 60
        for index in 0...steps {
            let fraction = from + (to - from) * Double(index) / Double(steps)
            let point = GaugeArc.point(fraction, in: rect, sweep: sweep, inset: inset)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

struct GaugeMarker: View {
    let fraction: Double
    var sweep: Double = 240
    var lineWidth: CGFloat = 10
    var size: CGFloat = 10
    var color: Color = .primary

    var body: some View {
        GeometryReader { geometry in
            let point = GaugeArc.point(min(max(fraction, 0), 1),
                                       in: CGRect(origin: .zero, size: geometry.size),
                                       sweep: sweep,
                                       inset: lineWidth / 2)
            Circle()
                .fill(color)
                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                .frame(width: size, height: size)
                .position(point)
        }
    }
}

struct BMIBar: View {
    let bmi: Double?

    private let bounds: [Double] = [15, 18.5, 25, 30, 35, 40, 43]

    var body: some View {
        GeometryReader { geometry in
            let span = bounds[bounds.count - 1] - bounds[0]
            let categories = BMICategory.allCases
            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    ForEach(categories) { category in
                        let index = category.rawValue
                        let width = (bounds[index + 1] - bounds[index]) / span
                        Capsule()
                            .fill(category.color)
                            .frame(width: max(geometry.size.width * width - 2, 2))
                    }
                }
                if let bmi {
                    let fraction = min(max((bmi - bounds[0]) / span, 0), 1)
                    Capsule()
                        .fill(Color.primary)
                        .frame(width: 3, height: geometry.size.height + 6)
                        .offset(x: geometry.size.width * fraction - 1.5)
                }
            }
            .frame(height: geometry.size.height)
        }
    }
}

struct WidgetSparkline: View {
    let values: [Double]
    let goal: Double?

    private var bounds: (low: Double, high: Double) {
        var low = values.min() ?? 0
        var high = values.max() ?? 1
        if let goal {
            low = Swift.min(low, goal)
            high = Swift.max(high, goal)
        }
        if high - low < 0.2 {
            low -= 0.1
            high += 0.1
        }
        return (low, high)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let range = bounds
        let low = range.low, high = range.high
        return values.enumerated().map { index, value in
            CGPoint(x: size.width * CGFloat(index) / CGFloat(values.count - 1),
                    y: size.height - size.height * CGFloat((value - low) / (high - low)))
        }
    }

    private func goalY(_ goal: Double, height: CGFloat) -> CGFloat {
        let range = bounds
        return height - height * CGFloat((goal - range.low) / (range.high - range.low))
    }

    var body: some View {
        GeometryReader { geometry in
            let line = points(in: geometry.size)
            ZStack {
                Path { path in
                    guard let first = line.first, let last = line.last else { return }
                    path.move(to: CGPoint(x: first.x, y: geometry.size.height))
                    line.forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: last.x, y: geometry.size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.02)],
                                     startPoint: .top, endPoint: .bottom))
                Path { path in
                    guard let first = line.first else { return }
                    path.move(to: first)
                    line.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                if let goal {
                    let y = goalY(goal, height: geometry.size.height)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                    .stroke(Color.weightGoal.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
        }
    }
}

// MARK: - Streak

struct StreakSmallWidgetView: View {
    let s: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("TREND")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            WeightValueText(kilograms: s.trend, unit: s.unit, size: 28, weight: .bold)
            if let rate = s.weeklyRate {
                Text("\(s.unit.formattedDelta(rate, decimals: 2))/wk")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Indicators.direction(for: rate).color)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.caption2)
                    .foregroundStyle(s.streak.current > 0 ? .orange : .secondary)
                Text("\(s.streak.current)d")
                    .font(.caption2.weight(.semibold))
                Spacer()
                if s.streak.loggedToday {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.weightGoal)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct StreakMediumWidgetView: View {
    let s: WidgetSnapshot

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("TREND")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                WeightValueText(kilograms: s.trend, unit: s.unit, size: 34, weight: .bold)
                if let rate = s.weeklyRate {
                    Text("\(s.unit.formattedDelta(rate, decimals: 2)) per week")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Indicators.direction(for: rate).color)
                        .lineLimit(1)
                }
                Spacer(minLength: 2)
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(s.streak.current > 0 ? .orange : .secondary)
                    Text("\(s.streak.current) day\(s.streak.current == 1 ? "" : "s")")
                        .font(.caption2.weight(.semibold))
                    if s.streak.loggedToday {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.weightGoal)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                WidgetSparkline(values: s.chart.map(\.trend), goal: s.goal)
                    .frame(height: 78)
                if let remaining = s.remaining, remaining > 0.05 {
                    Text("\(s.unit.formatted(remaining)) to goal")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 150)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StreakCircularWidgetView: View {
    let s: WidgetSnapshot

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "flame.fill")
                .font(.caption2)
            Text("\(s.streak.current)")
                .font(.headline.weight(.bold))
                .monospacedDigit()
        }
    }
}

// MARK: - Today gauge

struct TodayGaugeWidgetView: View {
    let s: WidgetSnapshot

    private let sweep = 160.0

    private func fraction(_ value: Double) -> Double {
        guard let low = s.period.low, let high = s.period.high, high - low > 0.05 else { return 0.5 }
        return (value - low) / (high - low)
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(s.streak.loggedToday ? "Today" : "Latest")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            WeightValueText(kilograms: s.latest, unit: s.unit, size: 30)
            ZStack {
                GaugeArc(sweep: sweep, inset: 4)
                    .stroke(Color.weightEmpty, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                ForEach(Array(s.period.readings.enumerated()), id: \.offset) { item in
                    GaugeMarker(fraction: fraction(item.element), sweep: sweep, lineWidth: 8,
                                size: 5, color: Color.secondary.opacity(0.5))
                }
                if let latest = s.latest {
                    GaugeMarker(fraction: fraction(latest), sweep: sweep, lineWidth: 8,
                                size: 11, color: .primary)
                }
                VStack(spacing: 0) {
                    ChangeLabel(kilograms: s.period.change, unit: s.unit, size: 14)
                    Text("\(s.period.days) DAYS")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .offset(y: 12)
            }
            .frame(height: 52)
            HStack {
                Text(s.unit.number(s.period.low))
                Spacer()
                Text(s.unit.number(s.period.high))
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WeightCircularGaugeView: View {
    let s: WidgetSnapshot

    private var span: ClosedRange<Double> {
        let latest: Double = s.latest ?? 0
        let low: Double = Swift.min(s.period.low ?? latest - 0.5, latest)
        let high: Double = Swift.max(s.period.high ?? latest + 0.5, latest)
        if high - low < 0.1 { return (low - 0.5)...(high + 0.5) }
        return low...high
    }

    var body: some View {
        let span = self.span
        Gauge(value: s.latest ?? span.lowerBound, in: span) {
            Text(s.unit.short)
        } currentValueLabel: {
            Text(s.unit.number(s.latest))
                .monospacedDigit()
        }
        .gaugeStyle(.accessoryCircular)
    }
}

struct ChangeCircularView: View {
    let s: WidgetSnapshot

    var body: some View {
        let direction = Indicators.direction(for: s.period.change)
        VStack(spacing: 0) {
            Image(systemName: direction.arrow)
                .font(.system(size: 10, weight: .bold))
            Text(s.unit.number(s.period.change.map { abs($0) }))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
            Text("\(s.period.days)D")
                .font(.system(size: 9, weight: .semibold))
        }
    }
}

// MARK: - Week bars

struct WeekBarsWidgetView: View {
    let s: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Weight")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(s.now, format: .dateTime.day().month(.abbreviated))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.weightEmpty, in: Capsule())
            }
            WeightValueText(kilograms: s.latest, unit: s.unit, size: 26)
            Spacer(minLength: 0)
            WeekBars(cells: s.week, symbols: s.weekdaySymbols, barHeight: 46, accessory: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct WeekBars: View {
    let cells: [DayCell]
    let symbols: [String]
    var barHeight: CGFloat = 46
    var accessory = false

    private var bounds: (low: Double, high: Double)? {
        let values = cells.compactMap(\.kilograms)
        guard let low = values.min(), let high = values.max() else { return nil }
        return (low, high)
    }

    private func dotOffset(for value: Double, dot: CGFloat) -> CGFloat {
        guard let bounds, bounds.high - bounds.low > 0.05 else { return (barHeight - dot) / 2 }
        let fraction = (value - bounds.low) / (bounds.high - bounds.low)
        return (barHeight - dot) * CGFloat(1 - fraction)
    }

    var body: some View {
        let dot: CGFloat = accessory ? 8 : 12
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                VStack(spacing: 3) {
                    ZStack(alignment: .top) {
                        Capsule()
                            .fill(accessory ? Color.primary.opacity(0.25) : Color.weightEmpty)
                            .frame(width: dot + 2, height: barHeight)
                        if let value = cell.kilograms {
                            Circle()
                                .fill(accessory ? Color.primary : (cell.direction?.color ?? .weightDown))
                                .frame(width: dot, height: dot)
                                .offset(y: dotOffset(for: value, dot: dot))
                        }
                    }
                    .frame(height: barHeight)
                    Text(index < symbols.count ? symbols[index] : "")
                        .font(.system(size: accessory ? 8 : 10, weight: .semibold))
                        .foregroundStyle(cell.isToday ? Color.primary : Color.secondary)
                        .frame(width: 16, height: 14)
                        .background(cell.isToday && !accessory ? Color.weightEmpty : Color.clear, in: Circle())
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct WeekBarsAccessoryView: View {
    let s: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("BODY WEIGHT")
                    .font(.system(size: 9, weight: .semibold))
                Spacer()
                Text("\(s.unit.number(s.latest)) \(s.unit.short)")
                    .font(.system(size: 10, weight: .semibold))
            }
            WeekBars(cells: s.week, symbols: s.weekdaySymbols, barHeight: 26, accessory: true)
        }
    }
}

// MARK: - Week list

struct WeekListWidgetView: View {
    let s: WidgetSnapshot

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                Text(s.now, format: .dateTime.month(.abbreviated))
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                Text(s.now, format: .dateTime.day())
                    .font(.system(size: 34, weight: .regular, design: .rounded))
            }
            .frame(width: 44, alignment: .leading)

            VStack(spacing: 1) {
                ForEach(s.recentDays) { cell in
                    HStack(spacing: 6) {
                        Text(cell.date, format: .dateTime.weekday(.short))
                            .frame(width: 22, alignment: .trailing)
                            .foregroundStyle(.secondary)
                        Circle()
                            .fill(cell.direction?.color ?? Color.weightEmpty)
                            .frame(width: 7, height: 7)
                        Text(cell.kilograms.map { s.unit.number($0) } ?? "—")
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.vertical, 1)
                    .padding(.horizontal, 3)
                    .background(cell.isToday ? Color.weightEmpty : Color.clear, in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Chart

struct WeightChartWidgetView: View {
    let s: WidgetSnapshot

    private var readings: [TrendPoint] { s.chart.filter { $0.actual != nil } }

    private var domain: ClosedRange<Double> {
        let values = readings.compactMap(\.actual).map { s.unit.display($0) }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let pad = max((high - low) * 0.1, 0.3)
        return (low - pad)...(high + pad)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Body Weight")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                WeightValueText(kilograms: s.latest, unit: s.unit, size: 14)
            }
            if readings.count > 1 {
                Chart {
                    ForEach(readings) { point in
                        AreaMark(x: .value("Date", point.date),
                                 yStart: .value("Base", domain.lowerBound),
                                 yEnd: .value("Weight", s.unit.display(point.actual ?? 0)))
                            .foregroundStyle(LinearGradient(colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0.02)],
                                                            startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Date", point.date),
                                 y: .value("Weight", s.unit.display(point.actual ?? 0)))
                            .foregroundStyle(Color.accentColor)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
                .chartYScale(domain: domain)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Comparison

struct ComparisonWidgetView: View {
    let s: WidgetSnapshot

    var body: some View {
        let comparison = s.comparison
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text(comparison?.emoji ?? "⚖️")
                    .font(.system(size: 42))
                Spacer()
                if let lost = s.lost, lost > 0 {
                    ChangeLabel(kilograms: -lost, unit: s.unit, size: 14)
                }
            }
            Spacer(minLength: 0)
            Group {
                if let comparison {
                    Text("You've shed ").foregroundColor(.secondary)
                    + Text(comparison.name).foregroundColor(.primary)
                    + Text(" in weight").foregroundColor(.secondary)
                } else {
                    Text("Nothing shed yet").foregroundColor(.secondary)
                }
            }
            .font(.system(size: 18, weight: .bold))
            .lineLimit(3)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - BMI

struct BMIWidgetView: View {
    let s: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BMI")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(s.bmi.map { String(format: "%.1f", $0) } ?? "--")
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Spacer(minLength: 0)
            BMIBar(bmi: s.bmi)
                .frame(height: 8)
            if let bmi = s.bmi {
                let category = BMI.category(bmi)
                Text(category.label)
                    .font(.subheadline.weight(.medium))
                    .padding(.top, 2)
                Text("\(category.rangeLabel) | WHO")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.weightEmpty, in: RoundedRectangle(cornerRadius: 4))
            } else {
                Text("Height not set")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Calendar

struct MonthDotGrid: View {
    let leading: Int
    let cells: [DayCell]
    var dot: CGFloat = 9
    var spacing: CGFloat = 4

    private var rows: [[DayCell?]] {
        let padded: [DayCell?] = Array(repeating: nil, count: leading) + cells.map { Optional($0) }
        return stride(from: 0, to: padded.count, by: 7).map { start in
            let row = Array(padded[start..<min(start + 7, padded.count)])
            return row + Array(repeating: nil, count: 7 - row.count)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: spacing) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        if let cell {
                            DayDot(cell: cell, size: dot)
                        } else {
                            Color.clear.frame(width: dot + 5, height: dot + 5)
                        }
                    }
                }
            }
        }
    }
}

struct CalendarStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

struct CalendarMediumWidgetView: View {
    let s: WidgetSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(s.now, format: .dateTime.month(.wide).year())
                    .font(.caption)
                MonthDotGrid(leading: s.monthLeading, cells: s.month, dot: 10, spacing: 4)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(s.now, format: .dateTime.weekday(.abbreviated).day())
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                HStack(spacing: 14) {
                    CalendarStat(title: "AVG", value: "\(s.unit.number(s.monthAverage)) \(s.unit.short)")
                    CalendarStat(title: "CHG", value: changeText)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.streak.loggedToday ? "TODAY" : "LATEST")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    WeightValueText(kilograms: s.latest, unit: s.unit, size: 26)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var changeText: String {
        guard let change = s.monthChange else { return "--" }
        let arrow = change < -0.05 ? "↓" : (change > 0.05 ? "↑" : "→")
        return "\(arrow)\(s.unit.number(abs(change))) \(s.unit.short)"
    }
}

struct CalendarSmallWidgetView: View {
    let s: WidgetSnapshot

    private var changeText: String {
        guard let change = s.monthChange else { return "--" }
        let arrow: String = change < 0 ? "↓" : "↑"
        return arrow + s.unit.number(abs(change))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(s.now, format: .dateTime.month(.abbreviated).year())
                    .font(.caption2)
                Spacer()
                Text(s.now, format: .dateTime.weekday(.abbreviated).day())
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
            }
            MonthDotGrid(leading: s.monthLeading, cells: s.month, dot: 7, spacing: 3)
                .frame(maxWidth: .infinity, alignment: .center)
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("AVG \(s.unit.number(s.monthAverage))")
                    Text("CHG \(changeText)")
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                Spacer()
                WeightValueText(kilograms: s.latest, unit: s.unit, size: 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Goal

struct GoalRingWidgetView: View {
    let s: WidgetSnapshot

    var body: some View {
        let progress = s.progress ?? 0
        VStack(alignment: .leading, spacing: 4) {
            Text("Weight Goal")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.weightGoal)
            ZStack {
                Circle()
                    .stroke(Color.weightGoal.opacity(0.15), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.weightGoal, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(s.goal == nil ? "--" : "\(Int((progress * 100).rounded()))%")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.weightGoal)
            }
            .frame(width: 62, height: 62)
            .padding(.leading, 4)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                WeightValueText(kilograms: s.trend, unit: s.unit, size: 14)
                if let lost = s.lost, abs(lost) > 0.05 {
                    ChangeLabel(kilograms: -lost, unit: s.unit, size: 13)
                }
            }
            Text(s.goal == nil ? "No goal set" : "Remaining \(s.unit.formatted(s.remaining ?? 0))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Monthly rate

struct RateGaugeWidgetView: View {
    let s: WidgetSnapshot

    private let sweep = 250.0
    private let maximum = 5.0

    var body: some View {
        let percent = s.percentPerMonth
        let losing = (percent ?? 0) <= 0
        let tint = losing ? Color.weightDown : Color.weightUp
        let fraction = min(abs(percent ?? 0) / maximum, 1)
        ZStack {
            GaugeArc(sweep: sweep, inset: 6)
                .stroke(tint.opacity(0.15), style: StrokeStyle(lineWidth: 12, lineCap: .round))
            GaugeMarker(fraction: fraction, sweep: sweep, lineWidth: 12, size: 12, color: tint)
            VStack(spacing: 0) {
                Text(percent == nil ? "Rate" : (losing ? "Losing" : "Gaining"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Text(percent.map { String(format: "%.1f%%", abs($0)) } ?? "--")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                Text("per month")
                    .font(.caption)
            }
            .padding(.top, 8)
            VStack {
                Spacer()
                HStack {
                    Text("0%")
                    Spacer()
                    Text("\(Int(maximum))%")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint.opacity(0.7))
                .padding(.horizontal, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
