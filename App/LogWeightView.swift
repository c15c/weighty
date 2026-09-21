import SwiftUI

struct LogWeightView: View {
    @EnvironmentObject private var store: WeightStore
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var date = Date()
    @State private var note = ""
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

                Section("Diary") {
                    TextEditor(text: $note)
                        .frame(minHeight: 180)
                } footer: {
                    Text("Optional — add how the day went, meals, exercise, or anything you want to remember.")
                }
            }
            .navigationTitle("Weigh-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(parsed == nil)
                }
            }
            .onAppear(perform: prefill)
            .onChange(of: date) { _, _ in prefillForSelectedDate() }
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
        } else {
            text = ""
            note = ""
        }
    }

    private func save() {
        guard let value = parsed else { return }
        let cleanedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        store.log(kilograms: store.unit.store(value),
                  on: date,
                  note: cleanedNote.isEmpty ? nil : cleanedNote)
        dismiss()
    }
}
