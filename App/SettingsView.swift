import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: WeightStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage(StorageKeys.reminderEnabled, store: AppGroup.defaults)
    private var reminderEnabled = false

    @State private var goalText = ""
    @State private var reminderTime = Calendar.current.date(
        from: DateComponents(hour: 7, minute: 0)) ?? Date()
    @State private var showingExport = false
    @State private var importingHealth = false
    @State private var healthImportMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    HStack {
                        TextField("Target weight", text: $goalText)
                            .keyboardType(.decimalPad)
                        Text(store.unit.short).foregroundStyle(.secondary)
                    }
                    if store.goalKilograms != nil {
                        Button("Clear goal", role: .destructive) {
                            store.goalKilograms = nil
                            goalText = ""
                        }
                    }
                }

                Section("Units") {
                    Picker("Unit", selection: $store.unit) {
                        ForEach(WeightUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Daily reminder") {
                    Toggle("Remind me to weigh in", isOn: $reminderEnabled)
                    if reminderEnabled {
                        DatePicker("Time", selection: $reminderTime,
                                   displayedComponents: .hourAndMinute)
                    }
                }

                Section {
                    Button {
                        Task { await importFromHealth() }
                    } label: {
                        HStack {
                            Label("Import body weight", systemImage: "heart.text.square")
                            Spacer()
                            if importingHealth { ProgressView() }
                        }
                    }
                    .disabled(importingHealth || !HealthKitImporter.isAvailable)

                    if let healthImportMessage {
                        Text(healthImportMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Read-only: Weight Streak imports body weight records but never writes to Apple Health. Existing Weight Streak entries and diary notes are not replaced.")
                }

                Section("Data export") {
                    Button("Export CSV") { showingExport = true }
                        .disabled(store.entries.isEmpty)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { commit(); dismiss() }
                }
            }
            .onAppear(perform: load)
            .onChange(of: reminderEnabled) { _, enabled in
                Task { await updateReminder(enabled: enabled) }
            }
            .onChange(of: reminderTime) { _, _ in
                Task { await updateReminder(enabled: reminderEnabled) }
            }
            .sheet(isPresented: $showingExport) {
                ShareSheet(items: [store.csv()])
            }
        }
    }

    @MainActor
    private func importFromHealth() async {
        importingHealth = true
        healthImportMessage = nil
        defer { importingHealth = false }

        do {
            let samples = try await HealthKitImporter.bodyWeightSamples()
            let result = store.importWeights(samples)
            if samples.isEmpty {
                healthImportMessage = "No body weight records were available to import. Check Health access in Settings if you expected records."
            } else if result.imported == 0 {
                healthImportMessage = "Your history is already up to date."
            } else {
                let noun = result.imported == 1 ? "entry" : "entries"
                healthImportMessage = "Imported \(result.imported) new \(noun)."
            }
        } catch {
            healthImportMessage = error.localizedDescription
        }
    }

    private func load() {
        if let goal = store.goalKilograms {
            goalText = String(format: "%.1f", store.unit.display(goal))
        }
        let hour = AppGroup.defaults.object(forKey: StorageKeys.reminderHour) as? Int ?? 7
        let minute = AppGroup.defaults.object(forKey: StorageKeys.reminderMinute) as? Int ?? 0
        reminderTime = Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? reminderTime
    }

    private func commit() {
        if let value = Double(goalText.replacingOccurrences(of: ",", with: ".")) {
            store.goalKilograms = store.unit.store(value)
        }
    }

    private func updateReminder(enabled: Bool) async {
        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        AppGroup.defaults.set(components.hour ?? 7, forKey: StorageKeys.reminderHour)
        AppGroup.defaults.set(components.minute ?? 0, forKey: StorageKeys.reminderMinute)

        guard enabled else {
            Reminders.cancel()
            return
        }
        let granted = await Reminders.requestAuthorization()
        if granted {
            Reminders.schedule(hour: components.hour ?? 7, minute: components.minute ?? 0)
        } else {
            reminderEnabled = false
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
