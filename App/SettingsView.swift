import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: WeightStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage(StorageKeys.reminderEnabled, store: AppGroup.defaults)
    private var reminderEnabled = false

    @AppStorage(StorageKeys.adaptiveReminder, store: AppGroup.defaults)
    private var adaptiveReminder = true

    @AppStorage(StorageKeys.eveningNudge, store: AppGroup.defaults)
    private var eveningNudge = true

    @State private var goalText = ""
    @State private var reminderTime = Calendar.current.date(
        from: DateComponents(hour: 7, minute: 0)) ?? Date()
    @State private var showingExport = false
    @State private var choosingBackupFolder = false
    @State private var backupMessage: String?
    @State private var confirmRestore = false

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

                Section {
                    Toggle("Remind me to weigh in", isOn: $reminderEnabled)
                    if reminderEnabled {
                        Toggle("Use my usual weigh-in time", isOn: $adaptiveReminder)
                        if !adaptiveReminder {
                            DatePicker("Time", selection: $reminderTime,
                                       displayedComponents: .hourAndMinute)
                        }
                        Toggle("Evening nudge when a streak is open", isOn: $eveningNudge)
                    }
                } header: {
                    Text("Daily reminder")
                } footer: {
                    Text(reminderFooter)
                }

                Section("Data export") {
                    Button("Export CSV") { showingExport = true }
                        .disabled(store.entries.isEmpty)
                }

                Section {
                    Button {
                        choosingBackupFolder = true
                    } label: {
                        Label(BackupManager.hasDestination
                              ? "Change backup folder"
                              : "Choose iCloud Drive folder",
                              systemImage: "icloud.and.arrow.up")
                    }

                    if BackupManager.hasDestination {
                        Button("Back up now") { createBackup() }
                        Button("Restore from backup") { confirmRestore = true }
                    }

                    if let backupMessage {
                        Text(backupMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if let name = BackupManager.destinationName {
                        Text("Backing up automatically to \(name).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("iCloud Backup")
                } footer: {
                    Text("Choose a folder in iCloud Drive once. Weight Streak will automatically back up entries, settings, diary text, and photos after changes.")
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
            .onChange(of: adaptiveReminder) { _, _ in
                Task { await updateReminder(enabled: reminderEnabled) }
            }
            .onChange(of: eveningNudge) { _, _ in
                Task { await updateReminder(enabled: reminderEnabled) }
            }
            .sheet(isPresented: $showingExport) {
                ShareSheet(items: [store.csv()])
            }
            .fileImporter(isPresented: $choosingBackupFolder,
                          allowedContentTypes: [.folder],
                          allowsMultipleSelection: false) { result in
                handleBackupFolder(result)
            }
            .alert("Restore backup?", isPresented: $confirmRestore) {
                Button("Restore", role: .destructive) { restoreBackup() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This replaces the current journal and settings with the selected iCloud backup.")
            }
        }
    }

    private var reminderFooter: String {
        guard adaptiveReminder else {
            return "The nudge only appears while a streak is open, never as a daily reprimand."
        }
        if let usual = Insights.usualWeighInTime(entries: store.entries),
           let hour = usual.hour, let minute = usual.minute {
            return String(format: "Reminders follow your habit — currently around %02d:%02d.", hour, minute)
        }
        return "After a few weigh-ins, reminders will move to the time you usually step on the scale."
    }

    private func handleBackupFolder(_ result: Result<[URL], Error>) {
        do {
            guard let folder = try result.get().first else { return }
            try BackupManager.select(folder: folder)
            try BackupManager.backup(store)
            backupMessage = "Backup created in \(folder.lastPathComponent)."
        } catch {
            backupMessage = error.localizedDescription
        }
    }

    private func createBackup() {
        do {
            try BackupManager.backup(store)
            backupMessage = "Backup updated."
        } catch {
            backupMessage = error.localizedDescription
        }
    }

    private func restoreBackup() {
        do {
            let date = try BackupManager.restore(into: store)
            backupMessage = "Restored backup from \(date.formatted(date: .abbreviated, time: .shortened))."
        } catch {
            backupMessage = error.localizedDescription
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
            Reminders.refresh(entries: store.entries, streak: store.streak)
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
