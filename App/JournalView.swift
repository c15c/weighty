import SwiftUI

// MARK: - Filtering

enum JournalDateFilter: String, CaseIterable, Identifiable {
    case all
    case month
    case quarter
    case year
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:     return "All time"
        case .month:   return "Last 30 days"
        case .quarter: return "Last 3 months"
        case .year:    return "Last year"
        case .custom:  return "Custom range"
        }
    }

    var days: Int? {
        switch self {
        case .month:   return 30
        case .quarter: return 90
        case .year:    return 365
        default:       return nil
        }
    }
}

// MARK: - Journal

struct JournalView: View {
    @EnvironmentObject private var store: WeightStore

    @State private var showPhotoCompare = false
    @State private var showFilters = false
    @State private var dateFilter = JournalDateFilter.all
    @State private var customStart = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customEnd = Date()
    @State private var selectedTags: Set<String> = []
    @State private var query = ""
    @AppStorage("journalNewestFirst") private var newestFirst = true

    private var changes: [UUID: EntryChange] { store.changes }

    /// Filtered entries bucketed by week, in the chosen order.
    private var groups: [WeekGroup] {
        let grouped = WeightCalendar.weekGroups(entries: entries, calendar: store.calendar)
        return newestFirst ? grouped.reversed() : grouped
    }

    private func ordered(_ items: [WeightEntry]) -> [WeightEntry] {
        newestFirst ? items.reversed() : items
    }

    private func weekHeader(_ group: WeekGroup) -> some View {
        let end = store.calendar.date(byAdding: .day, value: -1, to: group.interval.end) ?? group.interval.end
        return HStack {
            Text("\(group.interval.start.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated)))")
            Spacer()
            if let average = group.average {
                Text("avg \(store.unit.formatted(average))")
                    .monospacedDigit()
            }
        }
        .font(.subheadline.weight(.semibold))
        .textCase(nil)
    }

    private var hasPhotos: Bool { store.entries.contains { !$0.photoFilenames.isEmpty } }

    private var filtersActive: Bool {
        dateFilter != .all || !selectedTags.isEmpty
    }

    /// Chronological, narrowed by the active date range, tags and search.
    private var entries: [WeightEntry] {
        var items = store.entries

        if let days = dateFilter.days,
           let cutoff = Calendar.current.date(byAdding: .day,
                                              value: -(days - 1),
                                              to: Calendar.current.startOfDay(for: Date())) {
            items = items.filter { $0.date >= cutoff }
        } else if dateFilter == .custom {
            let lower = Calendar.current.startOfDay(for: min(customStart, customEnd))
            let upper = Calendar.current.startOfDay(for: max(customStart, customEnd))
            items = items.filter { $0.date >= lower && $0.date <= upper }
        }

        if !selectedTags.isEmpty {
            items = items.filter { !Set($0.tags).isDisjoint(with: selectedTags) }
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            items = items.filter { entry in
                (entry.note?.localizedCaseInsensitiveContains(trimmed) ?? false)
                || entry.resolvedTags.contains { $0.label.localizedCaseInsensitiveContains(trimmed) }
            }
        }

        return items
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    ContentUnavailableView("No journal entries yet",
                                           systemImage: "book.closed",
                                           description: Text("Your weigh-ins, notes, and photos will appear here."))
                } else {
                    List {
                        if filtersActive {
                            Section {
                                activeFilterSummary
                            }
                        }

                        if entries.isEmpty {
                            Section {
                                Text("No entries match these filters.")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(groups) { group in
                                Section {
                                    ForEach(ordered(group.entries)) { entry in
                                        NavigationLink {
                                            EntryDetailView(entryID: entry.id)
                                        } label: {
                                            JournalRow(entry: entry, change: changes[entry.id])
                                        }
                                    }
                                    .onDelete { offsets in
                                        delete(ordered(group.entries), at: offsets)
                                    }
                                } header: {
                                    weekHeader(group)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Journal")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { newestFirst.toggle() } label: {
                        Image(systemName: newestFirst ? "arrow.down" : "arrow.up")
                    }
                    .accessibilityLabel(newestFirst ? "Newest first" : "Oldest first")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFilters = true } label: {
                        Image(systemName: filtersActive
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Filter entries")
                }

                if hasPhotos {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showPhotoCompare = true } label: {
                            Image(systemName: "rectangle.on.rectangle.angled")
                        }
                        .accessibilityLabel("Compare photos")
                    }
                }
            }
            .sheet(isPresented: $showPhotoCompare) {
                PhotoCompareView()
            }
            .sheet(isPresented: $showFilters) {
                JournalFilterSheet(dateFilter: $dateFilter,
                                   customStart: $customStart,
                                   customEnd: $customEnd,
                                   selectedTags: $selectedTags)
            }
            .searchable(text: $query)
        }
    }

    private var activeFilterSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(dateFilter == .custom
                     ? "\(min(customStart, customEnd).formatted(date: .abbreviated, time: .omitted)) – \(max(customStart, customEnd).formatted(date: .abbreviated, time: .omitted))"
                     : dateFilter.label)
                    .font(.footnote.weight(.medium))
                Spacer()
                Button("Clear") {
                    dateFilter = .all
                    selectedTags = []
                }
                .font(.footnote.weight(.medium))
            }

            if !selectedTags.isEmpty {
                TagRow(tags: TagCatalog.definitions(for: selectedTags.sorted()))
            }
        }
    }

    private func delete(_ visible: [WeightEntry], at offsets: IndexSet) {
        for offset in offsets {
            let entry = visible[offset]
            EntryPhotoStore.delete(entry.photoFilenames)
            store.delete(entry)
        }
    }
}

// MARK: - Row

struct JournalRow: View {
    @EnvironmentObject private var store: WeightStore
    let entry: WeightEntry
    var change: EntryChange?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill((change?.direction ?? .flat).color)
                .frame(width: 11, height: 11)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(store.unit.number(entry.kilograms))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        Text(store.unit.short)
                            .font(.footnote.weight(.semibold))
                    }
                    Spacer()
                    if let delta = change?.delta {
                        let direction = Indicators.direction(for: delta)
                        HStack(spacing: 2) {
                            Image(systemName: direction.arrow)
                                .font(.caption2.weight(.bold))
                            Text(store.unit.number(abs(delta)))
                                .monospacedDigit()
                            Text(store.unit.short)
                                .font(.caption2)
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(direction.color)
                    }
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(entry.date, format: .dateTime.weekday(.abbreviated).day().month(.defaultDigits))
                            .textCase(.uppercase)
                        if let loggedAt = entry.loggedAt {
                            Text(loggedAt, format: .dateTime.hour().minute())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 72, alignment: .trailing)
                }

                if !entry.resolvedTags.isEmpty || !entry.photoFilenames.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(entry.resolvedTags) { tag in
                            Image(systemName: tag.symbol)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if !entry.photoFilenames.isEmpty {
                            Label("\(entry.photoFilenames.count)", systemImage: "photo")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                if let note = entry.note, !note.isEmpty {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Filter sheet

struct JournalFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var dateFilter: JournalDateFilter
    @Binding var customStart: Date
    @Binding var customEnd: Date
    @Binding var selectedTags: Set<String>

    var body: some View {
        NavigationStack {
            Form {
                Section("Date") {
                    Picker("Range", selection: $dateFilter) {
                        ForEach(JournalDateFilter.allCases) { filter in
                            Text(filter.label).tag(filter)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()

                    if dateFilter == .custom {
                        DatePicker("From", selection: $customStart,
                                   in: ...Date(), displayedComponents: .date)
                        DatePicker("To", selection: $customEnd,
                                   in: ...Date(), displayedComponents: .date)
                    }
                }

                Section {
                    ForEach(TagCatalog.all) { tag in
                        Button {
                            if selectedTags.contains(tag.id) {
                                selectedTags.remove(tag.id)
                            } else {
                                selectedTags.insert(tag.id)
                            }
                        } label: {
                            HStack {
                                Label(tag.label, systemImage: tag.symbol)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedTags.contains(tag.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Tags")
                } footer: {
                    Text("Entries matching any selected tag are shown.")
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        dateFilter = .all
                        selectedTags = []
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
