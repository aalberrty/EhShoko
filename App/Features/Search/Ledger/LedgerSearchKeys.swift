import EhModels
import SwiftUI

/// Ledger's keys on top of the keyboard (`ledger.md` section 6): the namespaces people search
/// by most, then `-` (exclude) and `$` (exact match), each inserting its text at the caret.
///
/// The field hosts this row as its input accessory (`spikes/S6.md` section 4): it moves with
/// the keyboard, 48 pt high growing to 60 with Dynamic Type, and scrolls sideways. Each key is
/// its own glass capsule on iOS 26 (a material capsule on iOS 18, on the keyboard's backdrop);
/// the row itself is clear, so no glass sits on glass.
struct LedgerSearchKeys: View {
    @Environment(\.searchFieldController) private var field

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(LedgerSearchKey.allCases, id: \.self) { key in
                    LedgerSearchKeyButton(key: key) { field.insert(key.text) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity)
    }
}

/// The keys, in the order drawn.
nonisolated enum LedgerSearchKey: CaseIterable, Hashable {
    case artist, female, male, parody, group, character, exclude, exact

    /// What the key inserts.
    var text: String {
        if let namespace { namespace.rawValue + ":" } else if self == .exclude { "-" } else { "$" }
    }

    var namespace: TagNamespace? {
        switch self {
        case .artist: .artist
        case .female: .female
        case .male: .male
        case .parody: .parody
        case .group: .group
        case .character: .character
        case .exclude, .exact: nil
        }
    }
}

/// A key: its text in the face the look gives search syntax, in a capsule 36 pt high.
private struct LedgerSearchKeyButton: View {
    let key: LedgerSearchKey
    let action: () -> Void

    @Environment(\.look) private var look

    var body: some View {
        Button(action: action) {
            Text(verbatim: key.text)
                .font(.subheadline)
                .lookSyntaxDesign()
                .foregroundStyle(look.label)
                .padding(.horizontal, 14)
                .frame(minWidth: 44, minHeight: 36)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassSurface(in: .capsule, isInteractive: true)
        .modifier(LedgerSearchKeyLabel(key: key))
    }
}

/// What VoiceOver says for a key. The words "Insert %@", "Exclude" and "Exact match" are not
/// in the app's strings yet (F27): a namespace key says the namespace's name, and `-` and `$`
/// are read as the characters they are.
private struct LedgerSearchKeyLabel: ViewModifier {
    let key: LedgerSearchKey

    func body(content: Content) -> some View {
        if let namespace = key.namespace {
            content.accessibilityLabel(namespace.localizedName)
        } else {
            content
        }
    }
}
