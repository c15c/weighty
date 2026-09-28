import SwiftUI

/// The scale stalls for weeks at a time while the mirror keeps changing. A
/// side-by-side is often the only visible evidence during a plateau, which is
/// exactly when people quit.
struct PhotoCompareView: View {
    @EnvironmentObject private var store: WeightStore
    @Environment(\.dismiss) private var dismiss

    @State private var mode = Mode.compare

    enum Mode: String, CaseIterable, Identifiable {
        case compare
        case timeline

        var id: String { rawValue }
        var label: String { self == .compare ? "Compare" : "Timeline" }
    }

    private var withPhotos: [WeightEntry] {
        store.entries
            .filter { !$0.photoFilenames.isEmpty }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            Group {
                if withPhotos.isEmpty {
                    ContentUnavailableView("No photos yet",
                                           systemImage: "photo.on.rectangle.angled",
                                           description: Text("Add a photo to a weigh-in to start a visual record."))
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            Picker("Mode", selection: $mode) {
                                ForEach(Mode.allCases) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented)

                            if mode == .compare {
                                comparison
                            } else {
                                timeline
                            }
                        }
                        .padding()
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var comparison: some View {
        let first = withPhotos.first
        let last = withPhotos.last

        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                photoColumn(entry: first, caption: "First")
                photoColumn(entry: last, caption: "Latest")
            }

            if let first, let last, first.id != last.id {
                let delta = last.kilograms - first.kilograms
                let days = Calendar.current.dateComponents([.day], from: first.date, to: last.date).day ?? 0
                VStack(spacing: 4) {
                    Text(store.unit.formattedDelta(delta))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(delta < 0 ? .green : (delta > 0 ? .orange : .primary))
                    Text("over \(days) days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func photoColumn(entry: WeightEntry?, caption: String) -> some View {
        VStack(spacing: 6) {
            if let entry, let filename = entry.photoFilenames.first,
               let image = EntryPhotoStore.image(named: filename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 260)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.tertiarySystemFill))
                    .frame(height: 260)
            }

            Text(caption)
                .font(.caption.weight(.semibold))
            if let entry {
                Text("\(entry.date.formatted(date: .abbreviated, time: .omitted)) · \(store.unit.formatted(entry.kilograms))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var timeline: some View {
        VStack(spacing: 18) {
            ForEach(withPhotos.reversed()) { entry in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(store.unit.formatted(entry.kilograms))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    JournalPhotoGrid(filenames: entry.photoFilenames)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}
