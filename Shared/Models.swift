import Foundation

// MARK: - Entry

struct WeightEntry: Codable, Identifiable, Hashable {
    var id: UUID
    var date: Date          // normalized to start of day, local time
    var kilograms: Double
    var note: String?
    var photoFilenames: [String]

    init(id: UUID = UUID(),
         date: Date,
         kilograms: Double,
         note: String? = nil,
         photoFilenames: [String] = []) {
        self.id = id
        self.date = date
        self.kilograms = kilograms
        self.note = note
        self.photoFilenames = photoFilenames
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, kilograms, note, photoFilenames
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        kilograms = try container.decode(Double.self, forKey: .kilograms)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        photoFilenames = try container.decodeIfPresent([String].self,
                                                       forKey: .photoFilenames) ?? []
    }
}

// MARK: - Units

enum WeightUnit: String, Codable, CaseIterable, Identifiable {
    case kilograms
    case pounds

    var id: String { rawValue }

    var short: String { self == .kilograms ? "kg" : "lb" }
    var label: String { self == .kilograms ? "Kilograms" : "Pounds" }

    /// Convert a stored kilogram value into the display unit.
    func display(_ kilograms: Double) -> Double {
        self == .kilograms ? kilograms : kilograms * 2.2046226218
    }

    /// Convert a value typed by the user back into kilograms for storage.
    func store(_ value: Double) -> Double {
        self == .kilograms ? value : value / 2.2046226218
    }

    func formatted(_ kilograms: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f %@", display(kilograms), short)
    }

    /// Signed delta, e.g. "-0.4 kg" or "+1.2 lb".
    func formattedDelta(_ kilogramsDelta: Double, decimals: Int = 1) -> String {
        let v = display(kilogramsDelta)
        let sign = v > 0 ? "+" : ""
        return String(format: "\(sign)%.\(decimals)f %@", v, short)
    }
}

// MARK: - Shared container

enum AppGroup {

    /// The group as written in both .entitlements files and in project.yml.
    static let configuredIdentifier = "group.com.cisco.weightstreak"

    /// The group the signature on this build actually grants.
    ///
    /// AltStore and SideStore may suffix the configured identifier with the signing
    /// team's ID. Older versions publish that mapping in ALTAppGroups; newer versions
    /// may only include it in embedded.mobileprovision. Try both sources and accept a
    /// candidate only if iOS grants this process access to its container.
    static let identifier: String = {
        let installed = (Bundle.main.infoDictionary?["ALTAppGroups"] as? [String]) ?? []
        let provisioned = provisionedGroups(in: Bundle.main)
        let candidates = orderedCandidates(installedGroups: installed,
                                           provisionedGroups: provisioned)

        for candidate in candidates {
            if FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: candidate
            ) != nil {
                return candidate
            }
        }
        return configuredIdentifier
    }()

    static var defaults: UserDefaults {
        let store = UserDefaults(suiteName: identifier) ?? .standard

        // A previous sideloaded build may have written into a private suite while it
        // could not resolve the remapped App Group. Once the real shared container is
        // available, copy missing values across so an update keeps the user's data.
        if isShared && identifier != configuredIdentifier,
           let legacy = UserDefaults(suiteName: configuredIdentifier) {
            for key in StorageKeys.all where store.object(forKey: key) == nil {
                if let value = legacy.object(forKey: key) {
                    store.set(value, forKey: key)
                }
            }
        }
        return store
    }

    /// True only when the resolved container actually exists on disk. False means the
    /// entitlement did not survive signing and the widget cannot see the app's data.
    static var isShared: Bool {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: identifier) != nil
    }

    static func orderedCandidates(installedGroups: [String],
                                  provisionedGroups: [String]) -> [String] {
        func relevant(_ groups: [String]) -> [String] {
            groups
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter {
                    $0 == configuredIdentifier ||
                    $0.hasPrefix(configuredIdentifier + ".")
                }
        }

        // Prefer remapped groups from the actual profile over possibly stale plist
        // metadata, then fall back to the original identifier for normal Xcode builds.
        let raw = relevant(provisionedGroups).filter { $0 != configuredIdentifier }
            + relevant(installedGroups).filter { $0 != configuredIdentifier }
            + relevant(provisionedGroups).filter { $0 == configuredIdentifier }
            + relevant(installedGroups).filter { $0 == configuredIdentifier }
            + [configuredIdentifier]

        var seen = Set<String>()
        return raw.filter { seen.insert($0).inserted }
    }

    /// Extract the plist payload from the CMS provisioning profile for discovery.
    /// Container lookup above remains the authority on whether access was granted.
    static func appGroups(inProvisioningProfile data: Data) -> [String] {
        guard let start = data.range(of: Data("<plist".utf8)),
              let end = data.range(of: Data("</plist>".utf8),
                                   in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                from: data.subdata(in: start.lowerBound..<end.upperBound),
                options: [],
                format: nil
              ) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String]
        else { return [] }
        return groups
    }

    private static func provisionedGroups(in bundle: Bundle) -> [String] {
        let url = bundle.bundleURL.appendingPathComponent("embedded.mobileprovision")
        guard let data = try? Data(contentsOf: url) else { return [] }
        return appGroups(inProvisioningProfile: data)
    }
}

enum StorageKeys {
    static let entries = "entries.v1"
    static let goal = "goalKilograms"
    static let unit = "unit"
    static let reminderEnabled = "reminderEnabled"
    static let reminderHour = "reminderHour"
    static let reminderMinute = "reminderMinute"

    static let all = [entries, goal, unit, reminderEnabled, reminderHour, reminderMinute]
}
