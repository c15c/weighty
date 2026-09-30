import SwiftUI

/// Every home and lock screen widget, rendered with your own data.
struct WidgetGalleryView: View {
    @EnvironmentObject private var store: WeightStore

    private var snapshot: WidgetSnapshot {
        store.entries.isEmpty ? .placeholder : .make(store: store)
    }

    private let small: CGFloat = 158
    private let spacing: CGFloat = 14

    var body: some View {
        let s = snapshot
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                section("Lock Screen") {
                    HStack(spacing: 12) {
                        rectangular { WeekBarsAccessoryView(s: s) }
                        circular { WeightCircularGaugeView(s: s) }
                        circular { ChangeCircularView(s: s) }
                        circular { StreakCircularWidgetView(s: s) }
                    }
                }

                section("Home Screen") {
                    VStack(spacing: spacing) {
                        HStack(spacing: spacing) {
                            tile("Today") { TodayGaugeWidgetView(s: s) }
                            tile("This Week") { WeekBarsWidgetView(s: s) }
                        }
                        HStack(spacing: spacing) {
                            tile("Last 7 Days") { WeekListWidgetView(s: s) }
                            tile("Body Weight") { WeightChartWidgetView(s: s) }
                        }
                        HStack(spacing: spacing) {
                            tile("Weight Change") { ComparisonWidgetView(s: s) }
                            tile("BMI") { BMIWidgetView(s: s) }
                        }
                        HStack(spacing: spacing) {
                            tile("Weight Calendar") { CalendarSmallWidgetView(s: s) }
                            tile("Weight Goal") { GoalRingWidgetView(s: s) }
                        }
                        HStack(spacing: spacing) {
                            tile("Rate") { RateGaugeWidgetView(s: s) }
                            tile("Trend & Streak") { StreakSmallWidgetView(s: s) }
                        }
                        wide("Weight Calendar") { CalendarMediumWidgetView(s: s) }
                        wide("Body Weight") { WeightChartWidgetView(s: s) }
                        wide("Trend & Streak") { StreakMediumWidgetView(s: s) }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Widgets")
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func card<Content: View>(width: CGFloat, height: CGFloat,
                                     @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(15)
            .frame(width: width, height: height)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }

    private func tile<Content: View>(_ name: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 6) {
            card(width: small, height: small, content: content)
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func wide<Content: View>(_ name: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 6) {
            card(width: small * 2 + spacing, height: small, content: content)
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func circular<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: 62, height: 62)
            .background(Color.secondary.opacity(0.2), in: Circle())
    }

    private func rectangular<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(width: 150, height: 62)
            .background(Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
    }
}
