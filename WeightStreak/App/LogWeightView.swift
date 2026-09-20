import SwiftUI

struct LogWeightView: View {
    @EnvironmentObject private var store: WeightStore
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var date = Date()
    @State private var note = ""
    @FocusState private var focused: Bool

    private var parsed: Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        TextField("0.0", text: $text)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 44, weight: .semibold, design: .rounded))
                            .focused($focused)
                        Text(store.unit.short)
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                    TextField("Note (optional)", text: $note)
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
        }
    }

    private func prefill() {
        if let existing = store.entry(on: date) {
            text = String(format: "%.1f", store.unit.display(existing.kilograms))
            note = existing.note ?? ""
        }
        focused = true
    }

    private func save() {
        guard let value = parsed else { return }
        store.log(kilograms: store.unit.store(value),
                  on: date,
                  note: note.isEmpty ? nil : note)
        dismiss()
    }
}
