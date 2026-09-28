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
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([WeightEntry].self, from: data) {
            return decoded.sorted { $0.date < $1.date }
        }

        // One-time migration from the 1.0 defaults blob.
        if let data = defaults.data(forKey: StorageKeys.entries),
           let decoded = try? JSONDecoder().decode([WeightEntry].self, from: data) {
            let sorted = decoded.sorted { $0.date < $1.date }
            save(sorted, defaults: defaults)
            return sorted
        }
        return []
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
