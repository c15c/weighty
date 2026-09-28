import Foundation

/// Entries live in a JSON file in the shared container rather than in
/// UserDefaults. A defaults blob is rewritten in full on every save and is the
/// wrong place for hundreds of diary entries; a file also survives defaults
/// suite remapping between sideloaded builds.
enum EntryStorage {

    private static let filename = "entries.v2.json"

    static var fileURL: URL {
        let manager = FileManager.default
        let base = manager.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroup.identifier
        ) ?? manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? manager.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(filename)
    }

    static func load(defaults: UserDefaults) -> [WeightEntry] {
        let fromFile: [WeightEntry]? = {
            guard let data = try? Data(contentsOf: fileURL),
                  let decoded = try? JSONDecoder().decode([WeightEntry].self, from: data)
            else { return nil }
            return decoded
        }()
        let fromDefaults: [WeightEntry]? = {
            guard let data = defaults.data(forKey: StorageKeys.entries),
                  let decoded = try? JSONDecoder().decode([WeightEntry].self, from: data)
            else { return nil }
            return decoded
        }()

        if let file = fromFile {
            let merged = mergeNotes(primary: file, fallback: fromDefaults ?? [])
            if merged != file.sorted(by: { $0.date < $1.date }) {
                let sorted = merged.sorted { $0.date < $1.date }
                save(sorted, defaults: defaults)
                return sorted
            }
            return file.sorted { $0.date < $1.date }
        }

        if let defaultsEntries = fromDefaults {
            let sorted = defaultsEntries.sorted { $0.date < $1.date }
            save(sorted, defaults: defaults)
            return sorted
        }
        return []
    }

    /// If the live file lost diary text but an older defaults copy still has it,
    /// put the notes back. Match by id, then by day.
    static func mergeNotes(primary: [WeightEntry], fallback: [WeightEntry]) -> [WeightEntry] {
        guard !fallback.isEmpty else { return primary }
        let byID = Dictionary(uniqueKeysWithValues: fallback.map { ($0.id, $0) })
        var byDay: [Date: WeightEntry] = [:]
        let calendar = Calendar.current
        for entry in fallback {
            byDay[calendar.startOfDay(for: entry.date)] = entry
        }
        return primary.map { entry in
            let missing = entry.note == nil || entry.note?.isEmpty == true
            guard missing else { return entry }
            let other = byID[entry.id] ?? byDay[calendar.startOfDay(for: entry.date)]
            guard let recovered = other?.note, !recovered.isEmpty else { return entry }
            var copy = entry
            copy.note = recovered
            return copy
        }
    }

    static func save(_ entries: [WeightEntry], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        do {
            try data.write(to: fileURL, options: .atomic)
            // Keep a copy in defaults so an older build, or one that cannot
            // resolve the shared container, still finds the data.
            defaults.set(data, forKey: StorageKeys.entries)
        } catch {
            defaults.set(data, forKey: StorageKeys.entries)
        }
    }
}
