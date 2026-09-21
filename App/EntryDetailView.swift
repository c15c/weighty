import SwiftUI
import PhotosUI

struct EntryDetailView: View {
    @EnvironmentObject private var store: WeightStore
    @Environment(\.dismiss) private var dismiss

    let entryID: UUID

    @State private var isEditing = false
    @State private var weightText = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var confirmDelete = false
    @State private var originalPhotos: [String] = []
    @State private var workingPhotos: [String] = []
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var pendingPhotos: [Data] = []

    private var entry: WeightEntry? {
        store.entries.first { $0.id == entryID }
    }

    private var parsedWeight: Double? {
        Double(weightText.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        Group {
            if let entry {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if isEditing {
                            editor
                        } else {
                            reader(entry)
                        }

                        Button("Delete entry", role: .destructive) {
                            confirmDelete = true
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                    }
                    .padding()
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle(entry.date.formatted(date: .abbreviated, time: .omitted))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .onAppear { load(entry) }
                .onChange(of: selectedPhotos) { _, items in
                    Task { await loadPhotos(items) }
                }
                .alert("Delete this entry?", isPresented: $confirmDelete) {
                    Button("Delete", role: .destructive) { delete(entry) }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This cannot be undone.")
                }
            } else {
                ContentUnavailableView("Entry not found", systemImage: "exclamationmark.circle")
            }
        }
    }

    private func reader(_ entry: WeightEntry) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Weight")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(store.unit.formatted(entry.kilograms))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Diary")
                    .font(.headline)
                Text(entry.note?.isEmpty == false ? entry.note! : "No diary entry.")
                    .foregroundStyle(entry.note?.isEmpty == false ? .primary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

            if !entry.photoFilenames.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Photos")
                        .font(.headline)
                    JournalPhotoGrid(filenames: entry.photoFilenames)
                }
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Weight").font(.headline)
                HStack {
                    TextField("0.0", text: $weightText)
                        .keyboardType(.decimalPad)
                        .font(.title.weight(.semibold))
                    Text(store.unit.short)
                        .foregroundStyle(.secondary)
                }
            }

            DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)

            VStack(alignment: .leading, spacing: 8) {
                Text("Diary").font(.headline)
                TextEditor(text: $note)
                    .frame(minHeight: 220)
                    .padding(8)
                    .background(Color(.secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Photos").font(.headline)

                if !workingPhotos.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                              spacing: 8) {
                        ForEach(workingPhotos, id: \.self) { filename in
                            if let image = EntryPhotoStore.image(named: filename) {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 130)
                                        .frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    Button {
                                        workingPhotos.removeAll { $0 == filename }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title2)
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.65))
                                    }
                                    .padding(6)
                                }
                            }
                        }
                    }
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
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if isEditing {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if let entry { load(entry) }
                    isEditing = false
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(parsedWeight == nil)
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { isEditing = true }
            }
        }
    }

    private func load(_ entry: WeightEntry) {
        weightText = String(format: "%.1f", store.unit.display(entry.kilograms))
        date = entry.date
        note = entry.note ?? ""
        originalPhotos = entry.photoFilenames
        workingPhotos = entry.photoFilenames
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

    private func save() {
        guard let value = parsedWeight else { return }
        let cleanedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let deleted = originalPhotos.filter { !workingPhotos.contains($0) }
        EntryPhotoStore.delete(deleted)
        let added = pendingPhotos.compactMap {
            EntryPhotoStore.save($0, entryID: entryID)
        }
        let finalPhotos = workingPhotos + added
        store.update(entryID: entryID,
                     kilograms: store.unit.store(value),
                     on: date,
                     note: cleanedNote.isEmpty ? nil : cleanedNote,
                     photoFilenames: finalPhotos)
        originalPhotos = finalPhotos
        workingPhotos = finalPhotos
        pendingPhotos = []
        selectedPhotos = []
        isEditing = false
    }

    private func delete(_ entry: WeightEntry) {
        EntryPhotoStore.delete(entry.photoFilenames)
        store.delete(entry)
        dismiss()
    }
}
