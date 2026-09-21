import SwiftUI

struct EntryDetailView: View {
    @EnvironmentObject private var store: WeightStore
    @Environment(\.dismiss) private var dismiss

    let entryID: UUID

    @State private var isEditing = false
    @State private var weightText = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var confirmDelete = false

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
    }

    private func save() {
        guard let value = parsedWeight else { return }
        let cleanedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        store.update(entryID: entryID,
                     kilograms: store.unit.store(value),
                     on: date,
                     note: cleanedNote.isEmpty ? nil : cleanedNote)
        isEditing = false
    }

    private func delete(_ entry: WeightEntry) {
        store.delete(entry)
        dismiss()
    }
}
