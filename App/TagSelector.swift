import SwiftUI

/// Tagging has to cost almost nothing or it will not happen. One tap, no typing,
/// and only the handful of things that actually move an overnight reading.
struct TagSelector: View {
    @Binding var selected: Set<EntryTag>

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(EntryTag.allCases) { tag in
                let isOn = selected.contains(tag)
                Button {
                    if isOn { selected.remove(tag) } else { selected.insert(tag) }
                } label: {
                    Label(tag.label, systemImage: tag.symbol)
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(isOn ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill),
                                    in: Capsule())
                        .foregroundStyle(isOn ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TagRow: View {
    let tags: [EntryTag]

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(tags) { tag in
                Label(tag.label, systemImage: tag.symbol)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(Color(.tertiarySystemFill), in: Capsule())
            }
        }
    }
}
