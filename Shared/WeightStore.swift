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

    @Published var heightCentimeters: Double? {
        didSet { setOptional(heightCentimeters, key: StorageKeys.height) }
    }

    /// Overrides the first weigh-in as the starting point for progress.
    @Published var baselineKilograms: Double? {
        didSet { setOptional(baselineKilograms, key: StorageKeys.baseline) }
    }

    @Published var ratePeriod: RatePeriod {
        didSet { setValue(ratePeriod.rawValue, key: StorageKeys.ratePeriod) }
    }

    @Published var weekStart: WeekStart {
        didSet { setValue(weekStart.rawValue, key: StorageKeys.weekStart) }
    }

    @Published var indicatorBasis: IndicatorBasis {
        didSet { setValue(indicatorBasis.rawValue, key: StorageKeys.indicatorBasis) }
    }

    init() {
        let store = AppGroup.defaults
        self.defaults = store
        self.unit = WeightUnit(rawValue: store.string(forKey: StorageKeys.unit) ?? "") ?? .kilograms
        self.goalKilograms = store.object(forKey: StorageKeys.goal) as? Double
        self.heightCentimeters = store.object(forKey: StorageKeys.height) as? Double
        self.baselineKilograms = store.object(forKey: StorageKeys.baseline) as? Double
        self.ratePeriod = RatePeriod(rawValue: store.integer(forKey: StorageKeys.ratePeriod)) ?? .week
        self.weekStart = WeekStart(rawValue: store.integer(forKey: StorageKeys.weekStart)) ?? .system
        self.indicatorBasis = IndicatorBasis(rawValue: store.string(forKey: StorageKeys.indicatorBasis) ?? "") ?? .previous
        self.entries = EntryStorage.load(defaults: store)
    }

    var latest: WeightEntry? { entries.last }
    var sharedStorageAvailable: Bool { AppGroup.isShared }
    var startingKilograms: Double? { baselineKilograms ?? entries.first?.kilograms }
    var calendar: Calendar { weekStart.calendar }
    var changes: [UUID: EntryChange] { Indicators.changes(entries: entries, basis: indicatorBasis) }
    var periodStats: PeriodStats { Periods.stats(entries: entries, days: ratePeriod.days) }
    var bmi: Double? { BMI.value(kilograms: trendKilograms, heightCentimeters: heightCentimeters) }

    var profile: ProfileSettings {
        ProfileSettings(heightCentimeters: heightCentimeters,
                        baselineKilograms: baselineKilograms,
                        ratePeriodDays: ratePeriod.rawValue,
                        weekStart: weekStart.rawValue,
                        indicatorBasis: indicatorBasis.rawValue)
    }

    func apply(_ profile: ProfileSettings) {
        heightCentimeters = profile.heightCentimeters
        baselineKilograms = profile.baselineKilograms
        if let days = profile.ratePeriodDays, let period = RatePeriod(rawValue: days) { ratePeriod = period }
        if let raw = profile.weekStart, let start = WeekStart(rawValue: raw) { weekStart = start }
        if let raw = profile.indicatorBasis, let basis = IndicatorBasis(rawValue: raw) { indicatorBasis = basis }
    }

    private func setOptional(_ value: Double?, key: String) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        WeightStore.reloadWidgets()
        WeightStore.didChange?(self)
    }

    private func setValue(_ value: Any, key: String) {
        defaults.set(value, forKey: key)
        WeightStore.reloadWidgets()
        WeightStore.didChange?(self)
    }
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
                 unit restoredUnit: WeightUnit,
                 profile restoredProfile: ProfileSettings? = nil) {
        entries = restoredEntries.sorted { $0.date < $1.date }
        goalKilograms = restoredGoal
        unit = restoredUnit
        if let restoredProfile { apply(restoredProfile) }
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
