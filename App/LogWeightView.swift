import SwiftUI
import PhotosUI

struct LogWeightView: View {
    @EnvironmentObject private var store: WeightStore
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var date = Date()
    @State private var time = Date()
    @State private var note = ""
    @State private var tags: Set<EntryTag> = []
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var pendingPhotos: [Data] = []
    @State private var existingPhotos: [String] = []
    @State private var saving = false
    @State private var confirmOutlier = false
    @FocusState private var weightFocused: Bool

    private var parsed: Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private var kilograms: Double? {
        parsed.map { store.unit.store($0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Weight") {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        TextField("0.0", text: $text)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 44, weight: .semibold, design: .rounded))
                            .focused($weightFocused)
                        Text(store.unit.short)
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                } header: {
                    Text("When")
                } footer: {
                    Text(timingHint)
                }

                Section {
                    TagSelector(selected: $tags)
                } header: {
                    Text("Context")
                } footer: {
                    Text("Optional. Tagging a few mornings lets Weight Streak show what each one is worth on the scale.")
                }

                Section {
                    TextEditor(text: $note)
                        .frame(minHeight: 180)
                } header: {
                    Text("Diary")
                } footer: {
                    Text("Optional — add how the day went, meals, exercise, or anything you want to remember.")
                }

                Section("Photos") {
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
                    }
                }
            }
            .navigationTitle("Weigh-in")
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
            .alert("Does that look right?", isPresented: $confirmOutlier) {
                Button("Save anyway") { Task { await save() } }
                Button("Let me fix it", role: .cancel) { weightFocused = true }
            } message: {
                Text(outlierMessage)
            }
        }
    }

    /// Consistency in timing removes more noise than any feature in the app.
    private var timingHint: String {
        guard let usual = Insights.usualWeighInTime(entries: store.entries),
              let hour = usual.hour, let minute = usual.minute else {
            return "Weigh in at the same time each day — first thing, after the bathroom, before eating or drinking."
        }
        return String(format: "You usually weigh in around %02d:%02d. Keeping to it makes your trend far more reliable.",
                      hour, minute)
    }

    private var outlierMessage: String {
        guard let kilograms else { return "" }
        let reference = store.trendKilograms ?? store.latest?.kilograms
        guard let reference else {
            return "That is outside the usual range for a bodyweight reading."
        }
        let gap = kilograms - reference
        return "That is \(store.unit.formattedDelta(gap)) from your trend of \(store.unit.formatted(reference)). A mistyped reading distorts your trend and charts for weeks."
    }

    private func prefill() {
        prefillForSelectedDate()
        weightFocused = true
    }

    private func prefillForSelectedDate() {
        if let existing = store.entry(on: date) {
            text = String(format: "%.1f", store.unit.display(existing.kilograms))
            note = existing.note ?? ""
            existingPhotos = existing.photoFilenames
            tags = Set(existing.knownTags)
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
                                tags: tags.map(\.rawValue).sorted())
        let filenames = pendingPhotos.compactMap {
            EntryPhotoStore.save($0, entryID: entryID)
        }
        store.appendPhotos(entryID: entryID, filenames: filenames)
        store.clearDraft()
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
