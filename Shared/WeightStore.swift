import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

final class WeightStore: ObservableObject {

    static let shared = WeightStore()

    /// Called after every change. The app uses this to keep the iCloud Drive
    /// backup current; the widget extension leaves it unset.
    static var didChange: ((WeightStore) -> Void)?

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
            WeightStore.didChange?(self)
        }
    }

    @Published var unit: WeightUnit {
        didSet {
            defaults.set(unit.rawValue, forKey: StorageKeys.unit)
            WeightStore.reloadWidgets()
            WeightStore.didChange?(self)
        }
    }

    init() {
        let store = AppGroup.defaults
        self.defaults = store
        self.unit = WeightUnit(rawValue: store.string(forKey: StorageKeys.unit) ?? "") ?? .kilograms
        self.goalKilograms = store.object(forKey: StorageKeys.goal) as? Double
        self.entries = EntryStorage.load(defaults: store)
    }

    var latest: WeightEntry? { entries.last }
    var sharedStorageAvailable: Bool { AppGroup.isShared }
    var startingKilograms: Double? { entries.first?.kilograms }
    var streak: StreakSummary { StreakCalculator.summary(entries: entries) }

    /// The smoothed weight, which is the number the app leads with.
    var trendKilograms: Double? { Trend.current(entries: entries) }
    var weeklyRate: Double? { Trend.weeklyRate(entries: entries) }
    var thisWeekAverage: Double? { Trend.calendarWeekAverage(entries: entries, weeksAgo: 0) }
    var lastWeekAverage: Double? { Trend.calendarWeekAverage(entries: entries, weeksAgo: 1) }
    var trendEstablished: Bool { Trend.isEstablished(entries: entries) }

    func entry(on date: Date, calendar: Calendar = .current) -> WeightEntry? {
        let day = calendar.startOfDay(for: date)
        return entries.first { calendar.isDate($0.date, inSameDayAs: day) }
    }

    @discardableResult
    func log(kilograms: Double, on date: Date = Date(), note: String? = nil,
             loggedAt: Date? = nil, tags: [String]? = nil,
             calendar: Calendar = .current) -> UUID {
        let day = calendar.startOfDay(for: date)
        let existing = entries.first { calendar.isDate($0.date, inSameDayAs: day) }
        var next = entries.filter { !calendar.isDate($0.date, inSameDayAs: day) }
        let entry = WeightEntry(id: existing?.id ?? UUID(),
                                date: day,
                                kilograms: kilograms,
                                note: note ?? existing?.note,
                                photoFilenames: existing?.photoFilenames ?? [],
                                loggedAt: loggedAt ?? existing?.loggedAt ?? Date(),
                                tags: tags ?? existing?.tags ?? [])
        next.append(entry)
        entries = next.sorted { $0.date < $1.date }
        persist()
        return entry.id
    }

    func update(entryID: UUID, kilograms: Double, on date: Date, note: String?,
                photoFilenames: [String]? = nil,
                tags: [String]? = nil,
                calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)
        let existing = entries.first { $0.id == entryID }
        var next = entries.filter {
            $0.id != entryID && !calendar.isDate($0.date, inSameDayAs: day)
        }
        next.append(WeightEntry(id: entryID,
                                date: day,
                                kilograms: kilograms,
                                note: note,
                                photoFilenames: photoFilenames ?? existing?.photoFilenames ?? [],
                                loggedAt: existing?.loggedAt,
                                tags: tags ?? existing?.tags ?? []))
        entries = next.sorted { $0.date < $1.date }
        persist()
    }

    func appendPhotos(entryID: UUID, filenames: [String]) {
        guard !filenames.isEmpty,
              let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].photoFilenames.append(contentsOf: filenames)
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

    func restore(entries restoredEntries: [WeightEntry],
                 goalKilograms restoredGoal: Double?,
                 unit restoredUnit: WeightUnit) {
        entries = restoredEntries.sorted { $0.date < $1.date }
        goalKilograms = restoredGoal
        unit = restoredUnit
        persist()
    }

    func csv() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let time = DateFormatter()
        time.dateFormat = "HH:mm"
        let series = Trend.series(entries: entries)
        var trendByDay: [Date: Double] = [:]
        for point in series { trendByDay[point.date] = point.trend }

        let rows = entries.map { entry -> String in
            let note = (entry.note ?? "").replacingOccurrences(of: ",", with: " ")
            let tags = entry.tags.joined(separator: " ")
            let trend = trendByDay[Calendar.current.startOfDay(for: entry.date)]
                .map { String(format: "%.2f", $0) } ?? ""
            let clock = entry.loggedAt.map { time.string(from: $0) } ?? ""
            return "\(formatter.string(from: entry.date)),\(clock),\(String(format: "%.2f", entry.kilograms)),\(trend),\(tags),\(note)"
        }
        return (["date,time,kilograms,trend,tags,note"] + rows).joined(separator: "\n")
    }

    private func persist() {
        EntryStorage.save(entries, defaults: defaults)
        WeightStore.reloadWidgets()
        WeightStore.didChange?(self)
    }

    static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
