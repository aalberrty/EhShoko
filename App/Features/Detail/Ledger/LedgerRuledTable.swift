import SwiftUI

// The pieces of Ledger's gallery page that read like a ruled ledger (`ledger.md` section 4):
// labels in small capitals and tables of cells separated by hairlines. They are content, so
// they take the look's colours and nothing here is glass.

extension View {
    /// Ledger's small capitals: uppercase, 11 pt bold, tracked 0.9, in the secondary colour
    /// unless a colour is given. Uppercase is a text case, so VoiceOver reads the original.
    func ledgerSmallCaps(_ color: Color? = nil) -> some View {
        modifier(LedgerSmallCaps(color: color))
    }
}

private struct LedgerSmallCaps: ViewModifier {
    let color: Color?
    @Environment(\.look) private var look

    func body(content: Content) -> some View {
        content
            .font(.caption2.bold())
            .tracking(0.9)
            .textCase(.uppercase)
            .foregroundStyle(color ?? look.secondaryLabel)
    }
}

/// A hairline in the look's separator colour, one pixel thick.
struct LedgerRule: View {
    enum Axis { case horizontal, vertical }

    var axis: Axis = .horizontal
    @Environment(\.look) private var look
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let thickness = 1 / max(displayScale, 1)
        switch axis {
        case .horizontal:
            Rectangle().fill(look.separator).frame(height: thickness)
        case .vertical:
            Rectangle().fill(look.separator).frame(width: thickness)
        }
    }
}

/// Cells in rows of `columns`, a hairline above every row and below the last, and a hairline
/// between the columns of a row. A row is as tall as its tallest cell; a row that is not full
/// leaves its last cells empty.
struct LedgerRuledTable<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    let columns: Int
    @ViewBuilder let cell: (Item) -> Cell

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows, id: \.self) { start in
                LedgerRule()
                HStack(alignment: .top, spacing: 0) {
                    ForEach(0..<columns, id: \.self) { column in
                        if column > 0 {
                            LedgerRule(axis: .vertical)
                        }
                        Group {
                            if start + column < items.count {
                                cell(items[start + column])
                            } else {
                                Color.clear
                            }
                        }
                        .padding(.leading, column > 0 ? 12 : 0)
                        .padding(.trailing, column < columns - 1 ? 12 : 0)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                // The vertical rules take the height of the tallest cell, not the proposal.
                .fixedSize(horizontal: false, vertical: true)
            }
            LedgerRule()
        }
    }

    private var rows: [Int] {
        Array(stride(from: 0, to: items.count, by: max(columns, 1)))
    }
}

/// One cell of a ruled table: a label in small capitals over its value.
struct LedgerLabelledCell<Value: View>: View {
    let label: String
    @ViewBuilder let value: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .ledgerSmallCaps()
                .lineLimit(1)
            value
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A section's heading line: the title as the look sets headings, and an optional control
/// trailing ("Vote", "All 48").
struct LedgerSectionHeading<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .lookSectionHeader()
            Spacer(minLength: 12)
            trailing
                .font(.subheadline)
        }
    }
}

extension LedgerSectionHeading where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}
