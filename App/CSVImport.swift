import Foundation

struct CSVImportResult {
    var entries: [WeightEntry]
    var skippedRows: Int
    /// Set when the file gave no unit and weights were read in this one.
    var assumedUnit: WeightUnit?
}

enum CSVImportError: LocalizedError {
    case unreadable
    case noWeighIns

    var errorDescription: String? {
        switch self {
        case .unreadable: return "The file couldn't be read."
        case .noWeighIns: return "No weigh-ins found in this file."
        }
    }
}

/// Reads weigh-ins from this app's CSV export and from most other apps'
/// exports: any delimiter, with or without a header, kg or lb, many date styles.
enum CSVImporter {

    static func read(url: URL) throws -> String {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .utf16) { return text }
        if let text = String(data: data, encoding: .isoLatin1) { return text }
        throw CSVImportError.unreadable
    }

    static func parse(_ raw: String, defaultUnit: WeightUnit, calendar: Calendar = .current) throws -> CSVImportResult {
        var text = raw
        if text.hasPrefix("\u{FEFF}") { text = String(text.dropFirst()) }

        let table = rows(text, delimiter: delimiter(for: text))
        guard let first = table.first else { throw CSVImportError.noWeighIns }

        let hasHeader = !first.contains { isNumber($0) }
        let body = hasHeader ? Array(table.dropFirst()) : table
        var columns = hasHeader ? Columns(header: first) : Columns()
        if columns.date == nil { columns.date = 0 }
        if columns.weight == nil { columns.weight = guessWeightColumn(body, excluding: columns.date ?? 0) }
        guard let dateColumn = columns.date, let weightColumn = columns.weight else { throw CSVImportError.noWeighIns }

        let dayFirst = prefersDayFirst(body.compactMap { $0.indices.contains(dateColumn) ? $0[dateColumn] : nil })
        let parser = DateParser(dayFirst: dayFirst, timeZone: calendar.timeZone)

        var parsed: [WeightEntry] = []
        var skipped = 0
        var assumed = false

        for row in body {
            guard row.indices.contains(dateColumn), row.indices.contains(weightColumn),
                  let date = parser.date(from: row[dateColumn]),
                  let reading = weight(row[weightColumn]) else {
                skipped += 1
                continue
            }

            var unit: WeightUnit? = reading.unit
            if unit == nil, let unitColumn = columns.unit, row.indices.contains(unitColumn) {
                unit = unitFrom(row[unitColumn])
            }
            if unit == nil { unit = columns.headerUnit }
            if unit == nil {
                unit = defaultUnit
                assumed = true
            }
            let kilograms = (unit ?? .kilograms).store(reading.value)
            guard kilograms >= 20, kilograms <= 400 else {
                skipped += 1
                continue
            }

            var loggedAt: Date? = date.hasTime ? date.value : nil
            if loggedAt == nil, let timeColumn = columns.time, row.indices.contains(timeColumn),
               let clock = parser.time(from: row[timeColumn]) {
                loggedAt = calendar.date(bySettingHour: clock.hour, minute: clock.minute, second: 0, of: date.value)
            }

            var note: String?
            if let noteColumn = columns.note, row.indices.contains(noteColumn) {
                let trimmed = row[noteColumn].trimmingCharacters(in: .whitespacesAndNewlines)
                note = trimmed.isEmpty ? nil : trimmed
            }

            var tags: [String] = []
            if let tagsColumn = columns.tags, row.indices.contains(tagsColumn) {
                tags = row[tagsColumn]
                    .components(separatedBy: CharacterSet(charactersIn: " ;|"))
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }

            parsed.append(WeightEntry(date: calendar.startOfDay(for: date.value),
                                      kilograms: (kilograms * 100).rounded() / 100,
                                      note: note,
                                      loggedAt: loggedAt,
                                      tags: tags))
        }

        let entries = onePerDay(parsed)
        guard !entries.isEmpty else { throw CSVImportError.noWeighIns }
        return CSVImportResult(entries: entries,
                               skippedRows: skipped + (parsed.count - entries.count),
                               assumedUnit: assumed ? defaultUnit : nil)
    }

    // MARK: - Columns

    struct Columns {
        var date: Int?
        var time: Int?
        var weight: Int?
        var unit: Int?
        var note: Int?
        var tags: Int?
        var headerUnit: WeightUnit?

        init() {}

        init(header: [String]) {
            let names = header.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            let excluded = ["trend", "goal", "target", "change", "bmi", "fat", "muscle", "water", "lean", "bone", "average", "avg"]
            let weightNames: Set<String> = ["kilograms", "kg", "kgs", "lb", "lbs", "pounds", "mass", "body mass"]

            for (index, name) in names.enumerated() {
                if date == nil, name.contains("date") || name == "day" || name.contains("timestamp") {
                    date = index
                } else if time == nil, name == "time" || name == "clock" || name == "time of day" {
                    time = index
                } else if weight == nil,
                          name.contains("weight") || weightNames.contains(name),
                          !excluded.contains(where: { name.contains($0) }) {
                    weight = index
                    headerUnit = CSVImporter.unitFrom(name)
                } else if unit == nil, name == "unit" || name == "units" {
                    unit = index
                } else if note == nil, name.contains("note") || name.contains("comment") || name.contains("diary") || name.contains("memo") {
                    note = index
                } else if tags == nil, name == "tags" || name == "tag" {
                    tags = index
                }
            }
            // A lone "time" column that actually holds full timestamps.
            if date == nil, let time {
                date = time
                self.time = nil
            }
        }
    }

    private static func guessWeightColumn(_ body: [[String]], excluding dateColumn: Int) -> Int? {
        guard let width = body.map(\.count).max() else { return nil }
        let sample = Array(body.prefix(20))
        for column in 0..<width where column != dateColumn {
            let values = sample.compactMap { $0.indices.contains(column) ? $0[column] : nil }
            let numeric = values.filter { isNumber($0) }.count
            if numeric > 0, numeric * 2 >= values.count { return column }
        }
        return nil
    }

    // MARK: - Values

    static func unitFrom(_ text: String) -> WeightUnit? {
        let lower = text.lowercased()
        if lower.contains("lb") || lower.contains("pound") { return .pounds }
        if lower.contains("kg") || lower.contains("kilo") { return .kilograms }
        return nil
    }

    private static let numberPattern = #"^-?[0-9]+([.,][0-9]+)?\s*(kg|kgs|lb|lbs)?$"#

    static func isNumber(_ field: String) -> Bool {
        let trimmed = field.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(of: numberPattern, options: .regularExpression) != nil
    }

    static func weight(_ field: String) -> (value: Double, unit: WeightUnit?)? {
        let trimmed = field.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: numberPattern, options: .regularExpression) != nil else { return nil }
        let unit = unitFrom(trimmed)
        var number = ""
        for character in trimmed where character.isNumber || character == "." || character == "," || character == "-" {
            number.append(character == "," ? "." : character)
        }
        guard let value = Double(number), value > 0 else { return nil }
        return (value, unit)
    }

    // MARK: - Rows

    static func delimiter(for text: String) -> Character {
        let firstLine = text.split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? text
        let candidates: [Character] = [",", ";", "\t"]
        var best: Character = ","
        var bestCount = 0
        for candidate in candidates {
            let count = firstLine.filter { $0 == candidate }.count
            if count > bestCount {
                best = candidate
                bestCount = count
            }
        }
        return best
    }

    static func rows(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let characters = Array(text)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if inQuotes {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" {
                inQuotes = true
            } else if character == delimiter {
                row.append(field)
                field = ""
            } else if character.isNewline {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows.filter { cells in
            cells.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
    }

    /// Several readings on one day: keep the earliest, carrying over any note.
    private static func onePerDay(_ entries: [WeightEntry]) -> [WeightEntry] {
        var byDay: [Date: WeightEntry] = [:]
        for entry in entries {
            guard let existing = byDay[entry.date] else {
                byDay[entry.date] = entry
                continue
            }
            let entryTime = entry.loggedAt ?? .distantFuture
            let existingTime = existing.loggedAt ?? .distantFuture
            var keep = entryTime < existingTime ? entry : existing
            let other = entryTime < existingTime ? existing : entry
            if keep.note == nil { keep.note = other.note }
            byDay[entry.date] = keep
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    // MARK: - Dates

    /// Decides dd/mm against mm/dd from the values themselves, falling back to the region.
    private static func prefersDayFirst(_ values: [String]) -> Bool {
        let pattern = #"^\s*(\d{1,2})[/.\-](\d{1,2})[/.\-]\d{2,4}"#
        for value in values {
            guard let range = value.range(of: pattern, options: .regularExpression) else { continue }
            let parts = value[range]
                .split(whereSeparator: { $0 == "/" || $0 == "." || $0 == "-" })
                .map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
            guard parts.count >= 2 else { continue }
            if parts[0] > 12 { return true }
            if parts[1] > 12 { return false }
        }
        return Locale.current.region?.identifier != "US"
    }

    struct ParsedDate {
        let value: Date
        let hasTime: Bool
    }

    struct DateParser {
        private let withTime: [DateFormatter]
        private let dateOnly: [DateFormatter]
        private let clocks: [DateFormatter]

        init(dayFirst: Bool, timeZone: TimeZone) {
            func make(_ format: String) -> DateFormatter {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = timeZone
                formatter.dateFormat = format
                return formatter
            }
            let numericDay = dayFirst ? "dd/MM/yyyy" : "MM/dd/yyyy"
            let numericDayShort = dayFirst ? "dd/MM/yy" : "MM/dd/yy"
            let dashed = dayFirst ? "dd-MM-yyyy" : "MM-dd-yyyy"

            let timed = [
                "yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX", "yyyy-MM-dd'T'HH:mm:ss",
                "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd h:mm a",
                "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm",
                "\(numericDay) HH:mm:ss", "\(numericDay) HH:mm", "\(numericDay) h:mm a", "\(numericDay), HH:mm",
                "\(dashed) HH:mm", "dd.MM.yyyy HH:mm", "d MMM yyyy HH:mm", "d MMM yyyy, HH:mm",
                "MMM d, yyyy HH:mm", "MMM d, yyyy h:mm a", "MMM d, yyyy 'at' h:mm a", "d MMM yyyy 'at' HH:mm"
            ]
            let plain = [
                "yyyy-MM-dd", "yyyy/MM/dd", "yyyy.MM.dd", numericDay, numericDayShort, dashed, "dd.MM.yyyy",
                "d MMM yyyy", "d MMMM yyyy", "MMM d, yyyy", "MMMM d, yyyy", "EEE, d MMM yyyy",
                "EEEE, d MMMM yyyy", "EEE, MMM d, yyyy", "EEEE, MMMM d, yyyy", "yyyyMMdd"
            ]
            withTime = timed.map(make)
            dateOnly = plain.map(make)
            clocks = ["HH:mm", "HH:mm:ss", "h:mm a", "h:mma", "H:mm"].map(make)
        }

        func date(from field: String) -> ParsedDate? {
            let trimmed = field.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            if trimmed.allSatisfy(\.isNumber), trimmed.count == 10 || trimmed.count == 13,
               let seconds = Double(trimmed) {
                let value = trimmed.count == 13 ? seconds / 1000 : seconds
                return ParsedDate(value: Date(timeIntervalSince1970: value), hasTime: true)
            }
            for formatter in withTime {
                if let date = formatter.date(from: trimmed) { return ParsedDate(value: date, hasTime: true) }
            }
            for formatter in dateOnly {
                if let date = formatter.date(from: trimmed) { return ParsedDate(value: date, hasTime: false) }
            }
            return nil
        }

        func time(from field: String) -> (hour: Int, minute: Int)? {
            let trimmed = field.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            for formatter in clocks {
                if let date = formatter.date(from: trimmed.uppercased()) {
                    let parts = Calendar(identifier: .gregorian).dateComponents(in: formatter.timeZone, from: date)
                    return (parts.hour ?? 0, parts.minute ?? 0)
                }
            }
            return nil
        }
    }
}
