import EhCore
import EhFeatures
import Observation
import SwiftUI

// What every reader controls design is given and builds with. A design is a view
// `init(model: ReaderModel, viewport: ReaderViewport)` in `Reader/<Design>/`, chosen by
// `ReaderScreen`; it draws over the engine and never knows who presented the reader.

/// The space the engine draws in, which a controls design may shorten.
@Observable
final class ReaderViewport {
    /// How much of the screen's bottom the engine gives up, measured from the screen's edge.
    ///
    /// Only a design whose controls would cover the page sets it: Ledger's open sheet, in a
    /// paged direction, in portrait, with the height the sheet covers taken from the sheet's
    /// own size (spike S4). Change it inside one animation, so the engine follows it frame by
    /// frame, and set it back to 0 when the controls hide and when the design goes away.
    var bottomInset: CGFloat = 0

    /// How much of the screen's bottom, measured from its edge, the controls cover while the
    /// engine keeps drawing under them: Ledger's open sheet in the vertical direction, where
    /// the strip scrolls behind it. Nothing indexed by page reads it; the closing page keeps
    /// that much room under its column (`ReaderClosingPage.bottomReserve`). Set it back to 0
    /// when the controls hide and when the design goes away.
    var coveredBottom: CGFloat = 0
}

/// The layer a design's floating controls sit in (`Design/designs/README.md` section 13):
/// one glass container, so its shapes blend and morph. Shelf uses two (the top group and the
/// bottom panel), Wall one; Ledger's controls are the system's sheet and need none.
///
/// While hidden it stays in the hierarchy, transparent and closed to touches. Taking it out
/// would pull a slider or an open menu away from under a finger when a second finger taps the
/// page. A fully transparent layer is not drawn, so hidden controls cost the reader no glass.
struct ReaderControlsLayer<Content: View>: View {
    let isShown: Bool
    var spacing: CGFloat?
    @ViewBuilder let content: Content

    var body: some View {
        GlassGroup(spacing: spacing) { content }
            .opacity(isShown ? 1 : 0)
            .allowsHitTesting(isShown)
            .accessibilityHidden(!isShown)
    }
}

/// Where the shared controls sit, the same in every design.
enum ReaderMetrics {
    /// Close is a glass circle of this size, top leading, so leaving is the same gesture in
    /// every design (`Design/designs/README.md` section 5.5).
    static let closeSize: CGFloat = 44
    /// From the leading edge of the safe area to Close.
    static let edgeInset: CGFloat = Tokens.Spacing.large
    /// From the top of the safe area to Close.
    static let topInset: CGFloat = Tokens.Spacing.xSmall
}

/// Close, on a glass circle. The symbol carries the system's localized "Close" label.
/// Closing is the presenter's dismissal, so it works the same whoever presented the reader;
/// under Ledger it needs nothing taken down first (spike S4).
///
/// The circle keeps its size, so the symbol grows with the text size only as far as the
/// largest standard size, where it still fits; beyond that the large content viewer shows it,
/// as for the system's bar buttons.
struct ReaderCloseControl: View {
    @Environment(\.dismiss) private var dismiss
    @State private var dismissals = 0

    var body: some View {
        Button {
            dismissals += 1
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.title3.weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .frame(width: ReaderMetrics.closeSize, height: ReaderMetrics.closeSize)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.Localizable.Common.close)
        .accessibilityShowsLargeContentViewer {
            Label(L10n.Localizable.Common.close, systemImage: "xmark")
        }
        .glassSurface(in: .circle, isInteractive: true)
        .sensoryFeedback(.impact(weight: .light), trigger: dismissals)
    }
}

extension View {
    /// The reading settings and the share sheet of `model.destination`. A design attaches them
    /// where it can present them: Shelf and Wall on their controls, Ledger inside its control
    /// sheet, because a second sheet attached to the reader's screen waits until the control
    /// sheet goes away (spike S4).
    func readerDestinationSheets(_ model: ReaderModel) -> some View {
        modifier(ReaderDestinationSheets(model: model))
    }
}

private struct ReaderDestinationSheets: ViewModifier {
    @Bindable var model: ReaderModel

    @Environment(SettingsStore.self) private var settings
    @Environment(\.look) private var look

    func body(content: Content) -> some View {
        content
            .sheet(item: $model.destination) { destination in
                switch destination {
                case .settings:
                    ReaderSettingsSheet(showsLandscapeSetting: model.showsLandscapeSetting)
                        .lookEnvironment(look, accent: settings.accentColor)
                case .share(let file):
                    ActivityView(items: [file])
                        .presentationDetents([.medium, .large])
                case .translationDownload:
                    // A placeholder until the download sheet is built.
                    EmptyView()
                }
            }
    }
}
