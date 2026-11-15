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

/// A SwiftUI row on top of the keyboard: the field's input accessory, so it moves with the
/// keyboard and the field bar sits on it (`spikes/S6.md` section 4). Ledger draws its keys in
/// it. It draws no backdrop: what the row holds carries its own surfaces.
///
/// A plain view, not a `UIInputView`: the keyboard keeps a `UIInputView` it has shown alive
/// after its field has gone, with nothing pointing at it (two retains too many), one more for
/// every field that showed one, while a plain view is freed with its field. And it lets go of
/// the row's host when the field goes away (`releaseHost()`), so nothing of the design that
/// drew the row outlives it.
final class TagSearchAccessoryView: UIView {
    /// The row's hosting controller, until `releaseHost()`.
    private(set) var host: UIViewController?

    /// 48 pt, growing with Dynamic Type up to 60 pt.
    static var height: CGFloat {
        min(UIFontMetrics(forTextStyle: .body).scaledValue(for: 48), 60)
    }

    init(host: UIViewController) {
        self.host = host
        let height = Self.height
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: height))
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
        #if DEBUG || HARNESS
        SearchAccessoryCensus.live += 1
        SearchAccessoryCensus.views.add(self)
        #endif
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    #if DEBUG || HARNESS
    deinit {
        // UIKit frees its views on the main thread.
        MainActor.assumeIsolated { SearchAccessoryCensus.live -= 1 }
    }
    #endif

    /// Takes the row out and lets go of its host, so the row and everything it holds are freed
    /// with the field, whoever still holds this view.
    func releaseHost() {
        host?.view.removeFromSuperview()
        host = nil
    }
}
