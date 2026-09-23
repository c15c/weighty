import Foundation

@MainActor
enum BackupManager {
    private static let bookmarkKey = "backupFolderBookmark.v1"
    private static let backupFilename = "Weight Streak Backup.json"
    private static var pendingBackup: Task<Void, Never>?

    struct BackupPayload: Codable {
        let version: Int
        let createdAt: Date
        let entries: [WeightEntry]
        let goalKilograms: Double?
        let unit: WeightUnit
        let photos: [String: Data]
    }

    static var hasDestination: Bool {
        AppGroup.defaults.data(forKey: bookmarkKey) != nil
    }

    static var destinationName: String? {
        try? resolveFolder().lastPathComponent
    }

    static func select(folder: URL) throws {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        let bookmark = try folder.bookmarkData(options: .minimalBookmark,
                                               includingResourceValuesForKeys: nil,
                                               relativeTo: nil)
        AppGroup.defaults.set(bookmark, forKey: bookmarkKey)
    }

    static func scheduleBackup(of store: WeightStore) {
        guard hasDestination else { return }
        pendingBackup?.cancel()
        pendingBackup = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            try? backup(store)
        }
    }

    static func backup(_ store: WeightStore) throws {
        let folder = try resolveFolder()
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }

        var photos: [String: Data] = [:]
        for filename in Set(store.entries.flatMap(\.photoFilenames)) {
            if let data = EntryPhotoStore.data(named: filename) {
                photos[filename] = data
            }
        }

        let payload = BackupPayload(version: 1,
                                    createdAt: Date(),
                                    entries: store.entries,
                                    goalKilograms: store.goalKilograms,
                                    unit: store.unit,
                                    photos: photos)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: folder.appendingPathComponent(backupFilename), options: .atomic)
    }

    static func restore(into store: WeightStore) throws -> Date {
        let folder = try resolveFolder()
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: folder.appendingPathComponent(backupFilename))
        let payload = try JSONDecoder().decode(BackupPayload.self, from: data)
        for (filename, photoData) in payload.photos {
            try EntryPhotoStore.restore(photoData, named: filename)
        }
        store.restore(entries: payload.entries,
                      goalKilograms: payload.goalKilograms,
                      unit: payload.unit)
        return payload.createdAt
    }

    private static func resolveFolder() throws -> URL {
        guard let bookmark = AppGroup.defaults.data(forKey: bookmarkKey) else {
            throw BackupError.noDestination
        }
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark,
                          options: .withoutUI,
                          relativeTo: nil,
                          bookmarkDataIsStale: &stale)
        if stale {
            try select(folder: url)
        }
        return url
    }

    enum BackupError: LocalizedError {
        case noDestination

        var errorDescription: String? {
            "Choose an iCloud Drive backup folder first."
        }
    }
}