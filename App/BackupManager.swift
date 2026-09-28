import Foundation

@MainActor
enum BackupManager {

    /// v1 bookmarks were created with `.minimalBookmark`, which does not keep the
    /// security scope for a folder handed over by the file picker. They resolve
    /// after a relaunch but every write is then denied, so the folder has to be
    /// picked once more to mint a proper scoped bookmark.
    private static let bookmarkKey = "backupFolderBookmark.v2"
    private static let legacyBookmarkKey = "backupFolderBookmark.v1"
    private static let lastBackupKey = "backupLastCompletedAt"
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

    /// True when only the old, unusable bookmark is present.
    static var needsReselection: Bool {
        AppGroup.defaults.data(forKey: bookmarkKey) == nil
            && AppGroup.defaults.data(forKey: legacyBookmarkKey) != nil
    }

    static var destinationName: String? {
        guard let bookmark = AppGroup.defaults.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        let url = try? URL(resolvingBookmarkData: bookmark,
                           options: [],
                           relativeTo: nil,
                           bookmarkDataIsStale: &stale)
        return url?.lastPathComponent
    }

    static var lastBackupDate: Date? {
        AppGroup.defaults.object(forKey: lastBackupKey) as? Date
    }

    // MARK: - Destination

    static func select(folder: URL) throws {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }

        // No options: on iOS that is what produces a bookmark which can
        // re-acquire security scope on a later launch.
        let bookmark = try folder.bookmarkData(options: [],
                                               includingResourceValuesForKeys: nil,
                                               relativeTo: nil)
        AppGroup.defaults.set(bookmark, forKey: bookmarkKey)
        AppGroup.defaults.removeObject(forKey: legacyBookmarkKey)
    }

    // MARK: - Backup

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

        let payload = BackupPayload(version: 2,
                                    createdAt: Date(),
                                    entries: store.entries,
                                    goalKilograms: store.goalKilograms,
                                    unit: store.unit,
                                    photos: photos)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)

        try write(data, to: folder.appendingPathComponent(backupFilename))
        AppGroup.defaults.set(Date(), forKey: lastBackupKey)
    }

    static func restore(into store: WeightStore) throws -> Date {
        let folder = try resolveFolder()
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }

        let data = try read(from: folder.appendingPathComponent(backupFilename))
        let payload = try JSONDecoder().decode(BackupPayload.self, from: data)
        for (filename, photoData) in payload.photos {
            try EntryPhotoStore.restore(photoData, named: filename)
        }
        store.restore(entries: payload.entries,
                      goalKilograms: payload.goalKilograms,
                      unit: payload.unit)
        return payload.createdAt
    }

    // MARK: - Coordinated file access

    /// iCloud Drive is a file provider, not a plain directory. Writes have to go
    /// through NSFileCoordinator, and an atomic write (temp file plus rename) is
    /// frequently refused there, which is why the previous version failed.
    private static func write(_ data: Data, to url: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var writeError: Error?

        coordinator.coordinate(writingItemAt: url, options: .forReplacing,
                               error: &coordinationError) { target in
            do {
                try data.write(to: target)
            } catch {
                writeError = error
            }
        }
        if let coordinationError { throw BackupError.accessDenied(coordinationError) }
        if let writeError { throw BackupError.accessDenied(writeError) }
    }

    private static func read(from url: URL) throws -> Data {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var data: Data?
        var readError: Error?

        coordinator.coordinate(readingItemAt: url, options: [],
                               error: &coordinationError) { target in
            do {
                data = try Data(contentsOf: target)
            } catch {
                readError = error
            }
        }
        if let coordinationError { throw BackupError.accessDenied(coordinationError) }
        if let readError { throw BackupError.noBackupFile }
        guard let data else { throw BackupError.noBackupFile }
        return data
    }

    private static func resolveFolder() throws -> URL {
        if AppGroup.defaults.data(forKey: bookmarkKey) == nil,
           AppGroup.defaults.data(forKey: legacyBookmarkKey) != nil {
            throw BackupError.needsReselection
        }
        guard let bookmark = AppGroup.defaults.data(forKey: bookmarkKey) else {
            throw BackupError.noDestination
        }

        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark,
                          options: [],
                          relativeTo: nil,
                          bookmarkDataIsStale: &stale)

        // Confirm the scope can actually be taken; a bookmark that resolves but
        // cannot be accessed is the failure this replaces.
        guard url.startAccessingSecurityScopedResource() else {
            throw BackupError.needsReselection
        }
        url.stopAccessingSecurityScopedResource()

        if stale {
            try select(folder: url)
        }
        return url
    }

    enum BackupError: LocalizedError {
        case noDestination
        case needsReselection
        case noBackupFile
        case accessDenied(Error)

        var errorDescription: String? {
            switch self {
            case .noDestination:
                return "Choose an iCloud Drive backup folder first."
            case .needsReselection:
                return "iOS no longer grants access to that folder. Choose the iCloud Drive folder again."
            case .noBackupFile:
                return "No backup file was found in that folder yet."
            case .accessDenied(let error):
                return "Could not write the backup: \(error.localizedDescription)"
            }
        }
    }
}
