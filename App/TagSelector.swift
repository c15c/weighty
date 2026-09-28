import SwiftUI

/// Chips are laid out by width rather than in a fixed grid. The grid was
/// clipping longer labels, which is what made the tag row unreadable.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var widestRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                widestRow = max(widestRow, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += rowWidth > 0 ? spacing + size.width : size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        widestRow = max(widestRow, rowWidth)
        return CGSize(width: min(widestRow, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y),
                          anchor: .topLeading,
                          proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct TagChip: View {
    let tag: TagDefinition
    var selected: Bool = false

    var body: some View {
        Label(tag.label, systemImage: tag.symbol)
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? Color.accentColor : Color(.tertiarySystemFill),
                        in: Capsule())
    }
}

/// Tagging has to cost almost nothing or it will not happen: one tap, no typing.
struct TagSelector: View {
    @Binding var selected: Set<String>

    private var tags: [TagDefinition] { TagCatalog.all }

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(tags) { tag in
                Button {
                    if selected.contains(tag.id) {
                        selected.remove(tag.id)
                    } else {
                        selected.insert(tag.id)
                    }
                } label: {
                    TagChip(tag: tag, selected: selected.contains(tag.id))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct TagRow: View {
    let tags: [TagDefinition]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(tags) { tag in
                TagChip(tag: tag)
            }
        }
    }
}
