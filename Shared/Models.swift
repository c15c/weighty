import Foundation

// MARK: - Entry

struct WeightEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var date: Date          // normalized to start of day, local time
    var kilograms: Double
    var note: String?
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
    /// Apple requires an App Group identifier to be unique to the signing team, so
    /// AltStore and SideStore cannot register the identifier as written. They create
    /// "<group>.<teamID>" instead, assign the App ID to it, and record the provisioned
    /// identifiers in an ALTAppGroups array in each bundle's Info.plist. Reading the
    /// build time constant in a sideloaded build therefore opens a container that was
    /// never provisioned, which is exactly the failure where the app saves fine and the
    /// widget shows nothing. A normal Xcode build carries no ALTAppGroups key and keeps
    /// the constant. Each process reads its own bundle, so the app and the widget
    /// extension resolve this independently and land on the same container.
    static let identifier: String = resolve(infoDictionary: Bundle.main.infoDictionary ?? [:])

    static func resolve(infoDictionary: [String: Any]) -> String {
        let provisioned = (infoDictionary["ALTAppGroups"] as? [String])?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("group.") } ?? []

        if let match = provisioned.first(where: {
            $0 == configuredIdentifier || $0.hasPrefix(configuredIdentifier + ".")
        }) {
            return match
        }
        if provisioned.count == 1, let only = provisioned.first {
            return only
        }
        return configuredIdentifier
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    /// True only when the resolved container actually exists on disk. False means the
    /// entitlement did not survive signing and the widget cannot see the app's data.
    static var isShared: Bool {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: identifier) != nil
    }
}

enum StorageKeys {
    static let entries = "entries.v1"
    static let goal = "goalKilograms"
    static let unit = "unit"
    static let reminderEnabled = "reminderEnabled"
    static let reminderHour = "reminderHour"
    static let reminderMinute = "reminderMinute"
}
