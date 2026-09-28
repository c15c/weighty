import SwiftUI
import PhotosUI

/// Laid out like the journal editor rather than as a settings form: the same
/// cards, headings and spacing, so logging and editing feel like one screen.
struct LogWeightView: View {
    @EnvironmentObject private var store: WeightStore
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var date = Date()
    @State private var time = Date()
    @State private var note = ""
    @State private var tags: Set<String> = []
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var pendingPhotos: [Data] = []
    @State private var existingPhotos: [String] = []
    @State private var saving = false
    @State private var confirmOutlier = false
    @State private var suggestedTags: [TagDefinition] = []
    @State private var editorID = UUID()
    @FocusState private var weightFocused: Bool

    private var parsed: Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private var kilograms: Double? {
        parsed.map { store.unit.store($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    weightCard
                    whenCard
                    contextCard
                    diaryCard
                    photosCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(store.entry(on: date) == nil ? "Weigh-in" : "Update weigh-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { attemptSave() }
                        .disabled(parsed == nil || saving)
                }
            }
            .onAppear(perform: prefill)
            .onChange(of: date) { _, _ in prefillForSelectedDate() }
            .onChange(of: selectedPhotos) { _, items in
                Task { await loadPhotos(items) }
            }
            .task(id: note) {
                await refreshSuggestedTags()
            }
            .alert("Does that look right?", isPresented: $confirmOutlier) {
                Button("Save anyway") { Task { await save() } }
                Button("Let me fix it", role: .cancel) { weightFocused = true }
            } message: {
                Text(outlierMessage)
            }
        }
    }

    // MARK: - Cards

    private var weightCard: some View {
        card {
            Text("Weight").font(.headline)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("0.0", text: $text)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .focused($weightFocused)
                Text(store.unit.short)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            if let trend = store.trendKilograms {
                Text("Trend is \(store.unit.formatted(trend))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var whenCard: some View {
        card {
            Text("When").font(.headline)
            DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
            Divider()
            DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
        }
    }

    private var contextCard: some View {
        card {
            HStack {
                Text("Context").font(.headline)
                Spacer()
                if !tags.isEmpty {
                    Button("Clear") { tags = [] }
                        .font(.caption.weight(.medium))
                }
            }
            TagSelector(selected: $tags)
            if !suggestedTags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(suggestedTags) { tag in
                        Button {
                            tags.insert(tag.id)
                            suggestedTags.removeAll { $0.id == tag.id }
                        } label: {
                            Label(tag.label, systemImage: "plus")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(.tertiarySystemFill), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var diaryCard: some View {
        card {
            Text("Diary").font(.headline)
            TextEditor(text: $note)
                .id(editorID)
                .frame(minHeight: 200)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var photosCard: some View {
        card {
            Text("Photos").font(.headline)
            if !existingPhotos.isEmpty {
                JournalPhotoGrid(filenames: existingPhotos)
            }
            if !pendingPhotos.isEmpty {
                PendingPhotoGrid(images: pendingPhotos) { index in
                    pendingPhotos.remove(at: index)
                }
            }
            PhotosPicker(selection: $selectedPhotos,
                         maxSelectionCount: 8,
                         matching: .images) {
                Label("Add photos", systemImage: "photo.on.rectangle.angled")
                    .font(.subheadline.weight(.medium))
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Copy

    private var outlierMessage: String {
        guard let kilograms else { return "" }
        guard let reference = store.trendKilograms ?? store.latest?.kilograms else {
            return "That is outside the usual range for a bodyweight reading."
        }
        let gap = kilograms - reference
        return "That is \(store.unit.formattedDelta(gap)) from your trend of \(store.unit.formatted(reference)). A mistyped reading distorts your trend and charts for weeks."
    }

    // MARK: - State

    private func prefill() {
        prefillForSelectedDate()
        weightFocused = true
    }

    private func prefillForSelectedDate() {
        if let existing = store.entry(on: date) {
            text = String(format: "%.1f", store.unit.display(existing.kilograms))
            note = existing.note ?? ""
            existingPhotos = existing.photoFilenames
            tags = Set(existing.tags)
            time = existing.loggedAt ?? Date()
        } else {
            text = ""
            note = ""
            existingPhotos = []
            tags = []
            time = Date()
        }
        selectedPhotos = []
        pendingPhotos = []
        editorID = UUID()
    }

    @MainActor
    private func refreshSuggestedTags() async {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard OnDeviceInsights.isAvailable, trimmed.count >= 8 else {
            suggestedTags = []
            return
        }
        try? await Task.sleep(nanoseconds: 700_000_000)
        guard !Task.isCancelled else { return }
        let ids = await OnDeviceInsights.suggestTags(note: trimmed, catalog: TagCatalog.all)
        suggestedTags = TagCatalog.definitions(for: ids).filter { !tags.contains($0.id) }
    }

    @MainActor
    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        var loaded: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                loaded.append(data)
            }
        }
        pendingPhotos = loaded
    }

    private func attemptSave() {
        guard let kilograms else { return }
        if Insights.isImplausible(kilograms: kilograms, entries: store.entries) {
            confirmOutlier = true
        } else {
            Task { await save() }
        }
    }

    @MainActor
    private func save() async {
        guard let kilograms else { return }
        saving = true
        let cleanedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let entryID = store.log(kilograms: kilograms,
                                on: date,
                                note: cleanedNote.isEmpty ? nil : cleanedNote,
                                loggedAt: combinedTimestamp,
                                tags: tags.sorted())
        let filenames = pendingPhotos.compactMap {
            EntryPhotoStore.save($0, entryID: entryID)
        }
        store.appendPhotos(entryID: entryID, filenames: filenames)
        Reminders.refresh(entries: store.entries, streak: store.streak)
        dismiss()
    }

    /// Keep the chosen day but carry the clock time, so timing analysis works
    /// even for a weigh-in entered later in the day.
    private var combinedTimestamp: Date {
        let calendar = Calendar.current
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        let clock = calendar.dateComponents([.hour, .minute], from: time)
        var merged = DateComponents()
        merged.year = day.year
        merged.month = day.month
        merged.day = day.day
        merged.hour = clock.hour
        merged.minute = clock.minute
        return calendar.date(from: merged) ?? Date()
    }
}
