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
    /// Must match the group in both .entitlements files and in project.yml.
    static let identifier = "group.com.cisco.weightstreak"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
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
