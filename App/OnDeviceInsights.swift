import Foundation
import Combine

struct GeneratedRecap: Equatable, Codable {
    var headline: String
    var body: String
}

/// On-device Apple Intelligence when the SDK and the phone both have it.
/// Missing model, older OS, or a generation failure all resolve to nil —
/// the rest of the app does not depend on this.
enum OnDeviceInsights {

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return FoundationModelsBridge.isAvailable
        }
        #endif
        return false
    }

    static func recap(snapshot: InsightSnapshot) async -> GeneratedRecap? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await FoundationModelsBridge.recap(snapshot: snapshot)
        }
        #endif
        return nil
    }

    static func suggestTags(note: String, catalog: [TagDefinition]) async -> [String] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await FoundationModelsBridge.suggestTags(note: note, catalog: catalog)
        }
        #endif
        return []
    }

    static func search(query: String, entries: [WeightEntry]) async -> [UUID] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await FoundationModelsBridge.search(query: query, entries: entries)
        }
        #endif
        return []
    }
}

struct ChatTurn: Identifiable, Equatable {
    let id: UUID
    let fromUser: Bool
    let text: String

    init(id: UUID = UUID(), fromUser: Bool, text: String) {
        self.id = id
        self.fromUser = fromUser
        self.text = text
    }
}

@MainActor
final class InsightChatController: ObservableObject {
    @Published var turns: [ChatTurn] = []
    @Published var busy = false

    func send(_ text: String, snapshot: InsightSnapshot) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !busy else { return }
        turns.append(ChatTurn(fromUser: true, text: trimmed))
        busy = true
        defer { busy = false }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let reply = await FoundationModelsBridge.chat(message: trimmed, snapshot: snapshot)
            turns.append(ChatTurn(fromUser: false, text: reply))
            return
        }
        #endif
        turns.append(ChatTurn(fromUser: false, text: "Apple Intelligence isn’t available."))
    }
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
private enum FoundationModelsBridge {

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
    }

    static func recap(snapshot: InsightSnapshot) async -> GeneratedRecap? {
        let key = cacheKey(for: snapshot)
        if let cached = RecapStore.load(key: key) { return cached }

        let session = LanguageModelSession(instructions: recapInstructions)
        do {
            let response = try await session.respond(to: snapshot.promptText(),
                                                     generating: RecapPayload.self)
            let recap = GeneratedRecap(headline: response.content.headline.trimmingCharacters(in: .whitespacesAndNewlines),
                                       body: response.content.body.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !recap.headline.isEmpty else { return nil }
            RecapStore.save(recap, key: key)
            return recap
        } catch {
            return nil
        }
    }

    static func suggestTags(note: String, catalog: [TagDefinition]) async -> [String] {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8, !catalog.isEmpty else { return [] }
        let catalogLines = catalog.map { "\($0.id)=\($0.label)" }.joined(separator: "\n")
        let session = LanguageModelSession(instructions: tagInstructions)
        let prompt = "CATALOG\n\(catalogLines)\nNOTE\n\(trimmed)"
        do {
            let response = try await session.respond(to: prompt, generating: TagPayload.self)
            let allowed = Set(catalog.map(\.id))
            return response.content.tagIDs.filter { allowed.contains($0) }
        } catch {
            return []
        }
    }

    static func search(query: String, entries: [WeightEntry]) async -> [UUID] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4, !entries.isEmpty else { return [] }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        let lines = entries.suffix(120).map { entry in
            let note = (entry.note ?? "").replacingOccurrences(of: "\n", with: " ")
            return "\(entry.id.uuidString)|\(iso.string(from: entry.date))|\(String(format: "%.1f", entry.kilograms))|\(entry.tags.joined(separator: ","))|\(note.prefix(160))"
        }.joined(separator: "\n")
        let session = LanguageModelSession(instructions: searchInstructions)
        let prompt = "QUERY\n\(trimmed)\nENTRIES\nid|date|kg|tags|note\n\(lines)"
        do {
            let response = try await session.respond(to: prompt, generating: SearchPayload.self)
            return response.content.ids.compactMap(UUID.init(uuidString:))
        } catch {
            return []
        }
    }

    private static var chatSession: LanguageModelSession?

    static func chat(message: String, snapshot: InsightSnapshot) async -> String {
        if chatSession == nil {
            chatSession = LanguageModelSession(instructions: chatInstructions)
        }
        guard let session = chatSession else {
            return "Apple Intelligence isn’t available."
        }
        do {
            let response = try await session.respond(
                to: message + "\n\nFACTS\n" + snapshot.promptText()
            )
            return String(describing: response.content)
        } catch {
            return error.localizedDescription
        }
    }

    private static let chatInstructions = """
    You are a private on-device assistant for this weight log.
    Use only numbers and facts in FACTS. Never invent measurements.
    No diet plans, workout plans, or medical diagnoses.
    Be concise.
    """

    private static let recapInstructions = """
    Write a factual note about a personal weight log.
    Use only numbers present in the prompt. Never invent measurements, dates, or tag effects.
    No diet, exercise, medical advice, encouragement, questions, or instructions.
    No emoji. Headline max 8 words. Body max 40 words.
    """

    private static let tagInstructions = """
    Choose catalog ids that the note clearly supports. Return only ids from CATALOG.
    If none apply, return an empty list. No extra keys.
    """

    private static let searchInstructions = """
    Return ids of entries that match QUERY by note, tags, date, or weight context.
    Use only ids from ENTRIES. Empty list if none match.
    """

    private static func cacheKey(for snapshot: InsightSnapshot) -> String {
        let day = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date()))
        return "recap.\(day).\(snapshot.recent.first?.id ?? "none").\(snapshot.streak).\(String(format: "%.2f", snapshot.latest ?? 0))"
    }
}

@available(iOS 26.0, *)
@Generable
private struct RecapPayload {
    @Guide(description: "Max 8 words. Factual.")
    var headline: String
    @Guide(description: "Max 40 words. Numbers only from the prompt.")
    var body: String
}

@available(iOS 26.0, *)
@Generable
private struct TagPayload {
    @Guide(description: "Catalog ids that apply.")
    var tagIDs: [String]
}

@available(iOS 26.0, *)
@Generable
private struct SearchPayload {
    @Guide(description: "Matching entry UUIDs.")
    var ids: [String]
}

private enum RecapStore {
    private static let defaults = AppGroup.defaults
    private static let key = "onDeviceRecap.v1"

    static func load(key: String) -> GeneratedRecap? {
        guard let data = defaults.data(forKey: Self.key),
              let box = try? JSONDecoder().decode(Box.self, from: data),
              box.key == key
        else { return nil }
        return box.recap
    }

    static func save(_ recap: GeneratedRecap, key: String) {
        let box = Box(key: key, recap: recap)
        if let data = try? JSONEncoder().encode(box) {
            defaults.set(data, forKey: Self.key)
        }
    }

    private struct Box: Codable {
        var key: String
        var recap: GeneratedRecap
    }
}

#else

private enum RecapStore {}

#endif
