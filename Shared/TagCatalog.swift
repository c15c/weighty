import Foundation

/// A tag as it exists in the catalog. Entries store only the identifier, so
/// renaming a tag relabels history instead of orphaning it.
struct TagDefinition: Codable, Identifiable, Hashable {
    var id: String
    var label: String
    var symbol: String

    init(id: String, label: String, symbol: String) {
        self.id = id
        self.label = label
        self.symbol = symbol
    }
}

/// The user's editable tag list, seeded from the built-in set on first use.
enum TagCatalog {

    private static let storageKey = "tagCatalog.v1"

    /// Symbols offered when creating a tag. A fixed, legible set beats a free
    /// text field that produces missing glyphs.
    static let symbolChoices = [
        "tag", "wineglass", "fork.knife", "takeoutbag.and.cup.and.straw",
        "airplane", "moon.zzz", "bolt.heart", "cross.case", "calendar",
        "clock.badge.checkmark", "arrow.uturn.down", "figure.walk",
        "drop", "cup.and.saucer", "pills", "bed.double", "sun.max",
        "briefcase", "house", "heart", "flame", "star", "exclamationmark.triangle",
        "checkmark.seal"
    ]

    static var defaults: [TagDefinition] {
        EntryTag.allCases.map {
            TagDefinition(id: $0.rawValue, label: $0.label, symbol: $0.symbol)
        }
    }

    static var all: [TagDefinition] {
        guard let data = AppGroup.defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([TagDefinition].self, from: data),
              !decoded.isEmpty
        else { return defaults }
        return decoded
    }

    static func save(_ tags: [TagDefinition]) {
        guard let data = try? JSONEncoder().encode(tags) else { return }
        AppGroup.defaults.set(data, forKey: storageKey)
    }

    static func resetToDefaults() {
        AppGroup.defaults.removeObject(forKey: storageKey)
    }

    /// Resolve a stored identifier. Tags deleted from the catalog still render
    /// on the entries that used them, so journal history stays readable.
    static func definition(for id: String) -> TagDefinition {
        if let match = all.first(where: { $0.id == id }) { return match }
        if let builtIn = EntryTag(rawValue: id) {
            return TagDefinition(id: id, label: builtIn.label, symbol: builtIn.symbol)
        }
        let label = id
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        return TagDefinition(id: id, label: label.capitalized, symbol: "tag")
    }

    static func definitions(for ids: [String]) -> [TagDefinition] {
        ids.map(definition(for:))
    }

    /// Stable identifier for a user-created tag.
    static func makeIdentifier(for label: String, existing: [TagDefinition]) -> String {
        let base = label
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let stem = base.isEmpty ? "tag" : base
        var candidate = stem
        var suffix = 2
        while existing.contains(where: { $0.id == candidate }) {
            candidate = "\(stem)-\(suffix)"
            suffix += 1
        }
        return candidate
    }
}
