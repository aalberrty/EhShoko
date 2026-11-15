import EhFeatures
import SwiftUI
import UIKit

/// The search field every search design places in its field bar (`Design/designs/README.md`
/// section 5.6): a `UISearchTextField`, so accepted tags are tokens before the text
/// (`spikes/S6.md`).
///
/// It leads and the model follows: each edit the user makes is reported to `model`
/// (`fieldDidEdit`), and the field is never written back on a keystroke. It shows the model's
/// content again only when the model replaced it (`revision`). New content comes in through
/// the controller in the environment (`\.searchFieldController`), which is also how a design
/// focuses the field, inserts a key at the caret, takes a suggestion or submits.
///
/// Nothing that draws the field reads the model's text: a keystroke redraws only the views
/// that read it themselves. The field is one line; with three tokens or more the earlier
/// ones scroll out to the leading side, as the system does.
///
/// - Parameters:
///   - prompt: what the empty field says; the scope's `localizedPrompt`.
///   - tokenStyle: the colour behind every token. The system draws token text white.
///   - accessory: a row shown on top of the keyboard while the field has focus (Ledger's
///     keys), or none.
struct TagSearchField<Accessory: View>: UIViewRepresentable {
    let model: SearchSurfaceModel
    let prompt: String
    let tokenStyle: SearchTokenStyle
    let accessory: Accessory?

    @Environment(\.searchFieldController) private var controller
    @Environment(\.lookTint) private var tint
    @Environment(\.look) private var look

    init(model: SearchSurfaceModel, prompt: String, tokenStyle: SearchTokenStyle, @ViewBuilder accessory: () -> Accessory) {
        self.model = model
        self.prompt = prompt
        self.tokenStyle = tokenStyle
        self.accessory = accessory()
    }

    func makeCoordinator() -> TagSearchFieldCoordinator {
        TagSearchFieldCoordinator(model: model)
    }

    func makeUIView(context: Context) -> TagSearchTextField {
        let field = TagSearchTextField()
        let coordinator = context.coordinator
        field.delegate = coordinator
        field.addTarget(coordinator, action: #selector(TagSearchFieldCoordinator.editingChanged), for: .editingChanged)
        coordinator.field = field
        // What the model already holds: a design switched while the surface was open, or the
        // surface came back to the screen.
        coordinator.apply(model)
        if let accessory {
            field.inputAccessoryView = TagSearchAccessoryView(content: accessoryContent(accessory))
        }
        controller.register(coordinator)
        return field
    }

    func updateUIView(_ field: TagSearchTextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.model = model
        coordinator.controller = controller
        controller.register(coordinator)
        // Content the model replaced since the field last showed it: a keyword handed in from
        // somewhere other than the controller, which applies its own at once.
        if coordinator.appliedRevision != model.revision {
            coordinator.apply(model)
        }
        if field.placeholder != prompt {
            field.placeholder = prompt
            field.accessibilityLabel = prompt
        }
        let background = tokenStyle.background(tint: UIColor(tint))
        if field.tokenBackgroundColor != background { field.tokenBackgroundColor = background }
        if field.textColor != look.uiLabel { field.textColor = look.uiLabel }
        if let accessory, let view = field.inputAccessoryView as? TagSearchAccessoryView<AccessoryContent> {
            view.update(accessoryContent(accessory))
        }
    }

    static func dismantleUIView(_ field: TagSearchTextField, coordinator: TagSearchFieldCoordinator) {
        coordinator.fieldWillGo()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView field: TagSearchTextField, context: Context) -> CGSize? {
        // The height follows Dynamic Type (capped by the field); the width is what the capsule
        // offers.
        CGSize(width: proposal.width ?? 200, height: max(field.intrinsicContentSize.height, 36))
    }

    // MARK: The accessory

    /// A hosting controller does not inherit the SwiftUI environment, so the look and the
    /// tint go in with the row.
    typealias AccessoryContent = TagSearchAccessoryRoot<Accessory>

    private func accessoryContent(_ accessory: Accessory) -> AccessoryContent {
        TagSearchAccessoryRoot(content: accessory, look: look, tint: tint, controller: controller)
    }
}

extension TagSearchField where Accessory == EmptyView {
    init(model: SearchSurfaceModel, prompt: String, tokenStyle: SearchTokenStyle) {
        self.model = model
        self.prompt = prompt
        self.tokenStyle = tokenStyle
        accessory = nil
    }
}

/// The accessory row with what it would otherwise not inherit.
struct TagSearchAccessoryRoot<Content: View>: View {
    let content: Content
    let look: Look
    let tint: Color
    let controller: TagSearchFieldController

    var body: some View {
        content
            .environment(\.look, look)
            .environment(\.lookTint, tint)
            .environment(\.searchFieldController, controller)
            .tint(tint)
    }
}

/// The one colour `UISearchTextField` draws behind every token. It draws the token's text and
/// icon white whatever the colour (`spikes/S6.md` section 10), so each style keeps to colours
/// white reads on.
nonisolated enum SearchTokenStyle: Equatable, Sendable {
    /// The tint (Shelf, Ledger). Where white text cannot read on the tint at all (under 2:1:
    /// Wall's label-coloured tint in dark mode, a pale chosen accent), the grey instead.
    /// Mid-tones stay the tint, as the designs ask: Ledger's dark coral gives 2.7:1.
    case tint
    /// A solid grey (Wall, whose design drew tokens on a fill white text cannot read on).
    case grey

    @MainActor
    func background(tint: UIColor) -> UIColor {
        switch self {
        case .grey:
            return .systemGray
        case .tint:
            return UIColor { traits in
                let resolved = tint.resolvedColor(with: traits)
                return resolved.contrastWithWhite >= 2 ? resolved : .systemGray
            }
        }
    }
}

private extension UIColor {
    /// The contrast ratio of white text on this colour (WCAG), 1 to 21.
    nonisolated var contrastWithWhite: CGFloat {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return 21 }
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        return 1.05 / (luminance + 0.05)
    }
}
