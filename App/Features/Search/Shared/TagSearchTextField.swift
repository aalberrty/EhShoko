import SwiftUI
import UIKit

/// The UIKit field under `TagSearchField`: a `UISearchTextField`, the only system field that
/// draws tokens, set up once for the site's search syntax (`spikes/S6.md` section 1).
final class TagSearchTextField: UISearchTextField {
    /// Focus was asked for before the field could take it: it takes it once it is in a
    /// window. Focusing from `.onAppear` can come before the field is in one, and in one
    /// spike run under a long stall it never took focus at all without this.
    var wantsFocus = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        // The site's syntax: smart punctuation would turn `"` into a curly quote, which the
        // site does not read as a quote, and `--` into a dash; capitals would change tags.
        autocorrectionType = .no
        autocapitalizationType = .none
        spellCheckingType = .no
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        // Return submits, also with only tokens and no text.
        returnKeyType = .search
        enablesReturnKeyAutomatically = false
        font = .preferredFont(forTextStyle: .body)
        adjustsFontForContentSizeCategory = true
        // Beyond this a line of the field holds a handful of characters (section 8).
        maximumContentSizeCategory = .accessibilityMedium
        // The design's glass capsule is the background; the scope menu or a symbol beside
        // the field is its magnifier.
        borderStyle = .none
        backgroundColor = .clear
        leftView = nil
        leftViewMode = .never
        clearButtonMode = .whileEditing
        allowsDeletingTokens = true
        allowsCopyingTokens = true
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        takeFocusIfWanted()
    }

    func takeFocusIfWanted() {
        guard wantsFocus, window != nil else { return }
        if isFirstResponder || becomeFirstResponder() { wantsFocus = false }
    }

    /// The tokens, then the text: the system's value has U+FFFC where each token is, which
    /// VoiceOver reads as nothing (section 7).
    override var accessibilityValue: String? {
        get {
            let spoken = tokens.compactMap { $0.searchToken?.spokenText }
            let text = (super.accessibilityValue ?? "")
                .replacingOccurrences(of: "\u{FFFC}", with: "")
                .trimmingCharacters(in: .whitespaces)
            return (spoken + (text.isEmpty ? [] : [text])).joined(separator: ", ")
        }
        set { super.accessibilityValue = newValue }
    }
}

/// A SwiftUI row on top of the keyboard: the field's input accessory, hosted in an input view
/// with the keyboard's style, so it moves with the keyboard and the field bar sits on it
/// (`spikes/S6.md` section 4). Ledger draws its keys in it. On iOS 18 the input view draws the
/// keyboard's backdrop behind the row; on iOS 26 it draws none, so what the row holds must
/// carry its own surfaces.
final class TagSearchAccessoryView<Content: View>: UIInputView {
    private let host: UIHostingController<Content>

    /// 48 pt, growing with Dynamic Type up to 60 pt.
    static var height: CGFloat {
        min(UIFontMetrics(forTextStyle: .body).scaledValue(for: 48), 60)
    }

    init(content: Content) {
        host = UIHostingController(rootView: content)
        let height = Self.height
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: height), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        host.view.backgroundColor = .clear
        host.view.maximumContentSizeCategory = .accessibilityMedium
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.view.topAnchor.constraint(equalTo: topAnchor),
            host.view.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: height)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func update(_ content: Content) {
        host.rootView = content
    }
}
