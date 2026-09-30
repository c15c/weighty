import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: WeightStore

    @AppStorage(StorageKeys.reminderEnabled, store: AppGroup.defaults)
    private var reminderEnabled = false

    @State private var goalText = ""
    @State private var baselineText = ""
    @State private var heightText = ""
    @State private var showingExport = false
    @State private var choosingBackupFolder = false
    @State private var backupMessage: String?
    @State private var confirmRestore = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Personal data") {
                    numberRow("Baseline weight",
                              text: $baselineText,
                              suffix: store.unit.short,
                              placeholder: store.entries.first.map { store.unit.number($0.kilograms) } ?? "—")
                    numberRow("Weight goal", text: $goalText, suffix: store.unit.short, placeholder: "—")
                    numberRow("Height", text: $heightText, suffix: "cm", placeholder: "—")
                    if let bmi = store.bmi {
                        LabeledContent("BMI") {
                            Text("\(String(format: "%.1f", bmi)) · \(BMI.category(bmi).label)")
                                .monospacedDigit()
                        }
                    }
                }

                Section("Display") {
                    Picker("Weight unit", selection: $store.unit) {
                        ForEach(WeightUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    Picker("Weight change", selection: $store.ratePeriod) {
                        ForEach(RatePeriod.allCases) { period in
                            Text(period.label).tag(period)
                        }
                    }
                    Picker("Indicators", selection: $store.indicatorBasis) {
                        ForEach(IndicatorBasis.allCases) { basis in
                            Text(basis.label).tag(basis)
                        }
                    }
                    Picker("Start of the week", selection: $store.weekStart) {
                        ForEach(WeekStart.allCases) { start in
                            Text(start.label).tag(start)
                        }
                    }
                }

                Section("Notification") {
                    NavigationLink {
                        ReminderSettingsView()
                    } label: {
                        LabeledContent("Reminders", value: reminderEnabled ? "On" : "Off")
                    }
                }

                Section("Journal") {
                    NavigationLink {
                        TagSettingsView()
                    } label: {
                        Text("Tags")
                    }
                }

                Section("Data") {
                    Button("Export CSV") { showingExport = true }
                        .disabled(store.entries.isEmpty)
                }

                Section {
                    Button {
                        choosingBackupFolder = true
                    } label: {
                        Label(BackupManager.hasDestination
                              ? "Change backup folder"
                              : (BackupManager.needsReselection
                                 ? "Choose iCloud Drive folder again"
                                 : "Choose iCloud Drive folder"),
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
                        Text(BackupManager.lastBackupDate.map {
                            "\(name) · \($0.formatted(date: .abbreviated, time: .shortened))"
                        } ?? name)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("iCloud Backup")
                }

                Section {
                    LabeledContent("Version", value: versionString)
                }
            }
            .navigationTitle("Settings")
            .scrollDismissesKeyboard(.interactively)
            .onAppear(perform: load)
            .onChange(of: store.unit) { _, _ in load() }
            .onChange(of: goalText) { _, text in
                store.goalKilograms = parse(text).map { store.unit.store($0) }
            }
            .onChange(of: baselineText) { _, text in
                store.baselineKilograms = parse(text).map { store.unit.store($0) }
            }
            .onChange(of: heightText) { _, text in
                store.heightCentimeters = parse(text).flatMap { $0 > 50 ? $0 : nil }
            }
            .onChange(of: store.ratePeriod) { _, _ in WeightStore.reloadWidgets() }
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
                Text("This replaces the current journal and settings with the iCloud backup.")
            }
        }
    }

    private func numberRow(_ title: String, text: Binding<String>, suffix: String, placeholder: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: 110)
            Text(suffix)
                .foregroundStyle(.secondary)
        }
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }

    private func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(trimmed), value > 0 else { return nil }
        return value
    }

    private func format(_ kilograms: Double?) -> String {
        kilograms.map { String(format: "%.1f", store.unit.display($0)) } ?? ""
    }

    private func load() {
        goalText = format(store.goalKilograms)
        baselineText = format(store.baselineKilograms)
        heightText = store.heightCentimeters.map { String(format: "%.0f", $0) } ?? ""
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
            load()
        } catch {
            backupMessage = error.localizedDescription
        }
    }
}

// MARK: - Reminders

struct ReminderSettingsView: View {
    @EnvironmentObject private var store: WeightStore

    @AppStorage(StorageKeys.reminderEnabled, store: AppGroup.defaults)
    private var enabled = false
    @AppStorage(StorageKeys.reminderSplitWeekend, store: AppGroup.defaults)
    private var splitWeekend = false
    @AppStorage(StorageKeys.adaptiveReminder, store: AppGroup.defaults)
    private var adaptive = false
    @AppStorage(StorageKeys.eveningNudge, store: AppGroup.defaults)
    private var eveningNudge = false
    @AppStorage(StorageKeys.reminderStyle, store: AppGroup.defaults)
    private var styleRaw = ReminderStyle.simple.rawValue

    @State private var weekdayTime = Date()
    @State private var weekendTime = Date()
    @State private var loaded = false

    private var style: ReminderStyle { ReminderStyle(rawValue: styleRaw) ?? .simple }

    var body: some View {
        Form {
            Section {
                Toggle("Reminders", isOn: $enabled)
            }

            if enabled {
                Section("Time") {
                    Toggle("Different time on weekends", isOn: $splitWeekend)
                    Toggle("Use my usual weigh-in time", isOn: $adaptive)
                    if adaptive {
                        let times = Reminders.effectiveTimes(entries: store.entries)
                        LabeledContent(splitWeekend ? "Weekdays" : "Every day", value: label(times.weekday))
                        if splitWeekend {
                            LabeledContent("Weekends", value: label(times.weekend))
                        }
                    } else {
                        DatePicker(splitWeekend ? "Weekdays" : "Every day",
                                   selection: $weekdayTime, displayedComponents: .hourAndMinute)
                        if splitWeekend {
                            DatePicker("Weekends", selection: $weekendTime, displayedComponents: .hourAndMinute)
                        }
                    }
                }

                Section("Style") {
                    Picker("Style", selection: $styleRaw) {
                        ForEach(ReminderStyle.allCases) { style in
                            Text(style.label).tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(style.title(streak: store.streak.current))
                            .font(.subheadline.weight(.semibold))
                        let message = style.body(streak: store.streak.current)
                        if !message.isEmpty {
                            Text(message)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                }

                Section {
                    Toggle("Evening reminder while a streak is open", isOn: $eveningNudge)
                }
            }
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onChange(of: enabled) { _, _ in Task { await apply() } }
        .onChange(of: splitWeekend) { _, _ in Task { await apply() } }
        .onChange(of: adaptive) { _, _ in Task { await apply() } }
        .onChange(of: eveningNudge) { _, _ in Task { await apply() } }
        .onChange(of: styleRaw) { _, _ in Task { await apply() } }
        .onChange(of: weekdayTime) { _, _ in Task { await apply() } }
        .onChange(of: weekendTime) { _, _ in Task { await apply() } }
    }

    private func label(_ components: DateComponents) -> String {
        let date = Calendar.current.date(from: DateComponents(hour: components.hour ?? 7,
                                                              minute: components.minute ?? 0)) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func load() {
        let calendar = Calendar.current
        weekdayTime = calendar.date(from: Reminders.weekdayTime()) ?? weekdayTime
        weekendTime = calendar.date(from: Reminders.weekendTime()) ?? weekendTime
        loaded = true
    }

    private func apply() async {
        guard loaded else { return }
        let calendar = Calendar.current
        let weekday = calendar.dateComponents([.hour, .minute], from: weekdayTime)
        let weekend = calendar.dateComponents([.hour, .minute], from: weekendTime)
        let defaults = AppGroup.defaults
        defaults.set(weekday.hour ?? 7, forKey: StorageKeys.reminderHour)
        defaults.set(weekday.minute ?? 0, forKey: StorageKeys.reminderMinute)
        defaults.set(weekend.hour ?? 8, forKey: StorageKeys.reminderWeekendHour)
        defaults.set(weekend.minute ?? 0, forKey: StorageKeys.reminderWeekendMinute)

        guard enabled else {
            Reminders.cancel()
            return
        }
        if await Reminders.requestAuthorization() {
            Reminders.refresh(entries: store.entries, streak: store.streak)
        } else {
            enabled = false
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
