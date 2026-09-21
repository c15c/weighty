import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Single source of truth, backed by the shared App Group container so the
/// widget extension reads the same data without any IPC.
final class WeightStore: ObservableObject {

    static let shared = WeightStore()

    private let defaults: UserDefaults

    @Published private(set) var entries: [WeightEntry] = []

    @Published var goalKilograms: Double? {
        didSet {
            if let goal = goalKilograms {
                defaults.set(goal, forKey: StorageKeys.goal)
            } else {
                defaults.removeObject(forKey: StorageKeys.goal)
            }
            WeightStore.reloadWidgets()
        }
    }

    @Published var unit: WeightUnit {
        didSet {
            defaults.set(unit.rawValue, forKey: StorageKeys.unit)
            WeightStore.reloadWidgets()
        }
    }

    init() {
        let store = AppGroup.defaults
        self.defaults = store
        self.unit = WeightUnit(rawValue: store.string(forKey: StorageKeys.unit) ?? "") ?? .kilograms
        self.goalKilograms = store.object(forKey: StorageKeys.goal) as? Double
        self.entries = WeightStore.loadEntries(from: store)
    }

    var latest: WeightEntry? { entries.last }
    var sharedStorageAvailable: Bool { AppGroup.isShared }
    var startingKilograms: Double? { entries.first?.kilograms }
    var streak: StreakSummary { StreakCalculator.summary(entries: entries) }

    func entry(on date: Date, calendar: Calendar = .current) -> WeightEntry? {
        let day = calendar.startOfDay(for: date)
        return entries.first { calendar.isDate($0.date, inSameDayAs: day) }
    }

    /// One weigh-in per calendar day. Logging again on the same day replaces it.
    func log(kilograms: Double, on date: Date = Date(), note: String? = nil,
             calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)
        var next = entries.filter { !calendar.isDate($0.date, inSameDayAs: day) }
        next.append(WeightEntry(date: day, kilograms: kilograms, note: note))
        entries = next.sorted { $0.date < $1.date }
        persist()
    }

    /// Update an existing diary entry while preserving its identity. Moving it to a
    /// date that already has an entry replaces that day's older entry.
    func update(entryID: UUID, kilograms: Double, on date: Date, note: String?,
                calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)
        var next = entries.filter {
            $0.id != entryID && !calendar.isDate($0.date, inSameDayAs: day)
        }
        next.append(WeightEntry(id: entryID, date: day, kilograms: kilograms, note: note))
        entries = next.sorted { $0.date < $1.date }
        persist()
    }

    func delete(_ entry: WeightEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    func deleteAll() {
        entries = []
        persist()
    }

    func csv() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let rows = entries.map { entry -> String in
            let note = (entry.note ?? "").replacingOccurrences(of: ",", with: " ")
            return "\(formatter.string(from: entry.date)),\(String(format: "%.2f", entry.kilograms)),\(note)"
        }
        return (["date,kilograms,note"] + rows).joined(separator: "\n")
    }

    private static func loadEntries(from defaults: UserDefaults) -> [WeightEntry] {
        guard let data = defaults.data(forKey: StorageKeys.entries),
              let decoded = try? JSONDecoder().decode([WeightEntry].self, from: data)
        else { return [] }
        return decoded.sorted { $0.date < $1.date }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: StorageKeys.entries)
        }
        WeightStore.reloadWidgets()
    }

    static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
