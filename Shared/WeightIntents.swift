import AppIntents
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The Shortcuts and Siri entry point. Also the practical bridge for anything
/// that can run a Shortcut, including a smart scale automation.
struct LogWeightIntent: AppIntent {
    static var title: LocalizedStringResource = "Log weight"
    static var description = IntentDescription("Records a weigh-in in Weight Streak.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Weight")
    var weight: Double

    @Parameter(title: "Date")
    var date: Date?

    @Parameter(title: "Diary note")
    var note: String?

    init() {}

    init(weight: Double, date: Date? = nil, note: String? = nil) {
        self.weight = weight
        self.date = date
        self.note = note
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$weight) on \(\.$date)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = WeightStore.shared
        let kilograms = store.unit.store(weight)
        let day = date ?? Date()
        store.log(kilograms: kilograms,
                  on: day,
                  note: note?.isEmpty == false ? note : nil,
                  loggedAt: Date())
        WeightStore.reloadWidgets()
        return .result(dialog: IntentDialog("Logged \(store.unit.formatted(kilograms))."))
    }
}

/// Reads back the smoothed trend rather than the raw reading, because that is
/// the number that answers "how am I doing".
struct WeightTrendIntent: AppIntent {
    static var title: LocalizedStringResource = "Get weight trend"
    static var description = IntentDescription("Returns your current trend weight and weekly rate.")
    static var openAppWhenRun: Bool = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Double> {
        let store = WeightStore.shared
        guard let trend = store.trendKilograms else {
            return .result(value: 0, dialog: IntentDialog("No weigh-ins yet."))
        }
        let rate = store.weeklyRate
        let rateText = rate.map { " Trending \(store.unit.formattedDelta($0)) per week." } ?? ""
        return .result(value: store.unit.display(trend),
                       dialog: IntentDialog("Trend weight \(store.unit.formatted(trend)).\(rateText)"))
    }
}
