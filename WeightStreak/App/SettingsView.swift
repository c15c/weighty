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

                Section("Apple Health") {
                    Text("Export a CSV, then use the Shortcuts app to log the numbers into Health. A sideloaded build signed with a free Apple ID cannot write to Health directly.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
