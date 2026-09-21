import SwiftUI
import PhotosUI

struct LogWeightView: View {
    @EnvironmentObject private var store: WeightStore
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var pendingPhotos: [Data] = []
    @State private var existingPhotos: [String] = []
    @State private var saving = false
    @FocusState private var weightFocused: Bool

    private var parsed: Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
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

                Section("Date") {
                    DatePicker("Weigh-in date", selection: $date, in: ...Date(), displayedComponents: .date)
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
                    Button("Save") { Task { await save() } }
                        .disabled(parsed == nil || saving)
                }
            }
            .onAppear(perform: prefill)
            .onChange(of: date) { _, _ in prefillForSelectedDate() }
            .onChange(of: selectedPhotos) { _, items in
                Task { await loadPhotos(items) }
            }
        }
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
        } else {
            text = ""
            note = ""
            existingPhotos = []
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

    @MainActor
    private func save() async {
        guard let value = parsed else { return }
        saving = true
        let cleanedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let entryID = store.log(kilograms: store.unit.store(value),
                                on: date,
                                note: cleanedNote.isEmpty ? nil : cleanedNote)
        let filenames = pendingPhotos.compactMap {
            EntryPhotoStore.save($0, entryID: entryID)
        }
        store.appendPhotos(entryID: entryID, filenames: filenames)
        dismiss()
    }
}
