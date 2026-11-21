import EhFeatures
import SwiftUI

/// Translate in the panel (`shelf.md` section 5), between the reading direction and Settings.
///
/// - A tap turns translation on or off in this reader (without models, it opens the download
///   sheet). The tile is lit in the tint while it is on.
/// - While it is on, the original shows from the moment a finger is down on the button, and
///   the translation comes back when the finger lifts after a hold. A tap that turns it off
///   therefore never shows the translation again in between.
/// - The mark: pages of this gallery were translated before.
///
/// VoiceOver cannot hold, so the button has a named action, Original, that shows the original
/// until it is chosen again or Translate is turned off.
struct ShelfTranslateButton: View {
    let model: ReaderModel

    @State private var press = ShelfTranslatePress()

    var body: some View {
        let translation = model.translation
        let isOn = translation.isOn
        Button {
            press.lifted(on: model)
        } label: {
            ShelfPanelButtonLabel(
                title: L10n.Localizable.Reader.translate, symbol: "translate",
                isOn: isOn, isMarked: translation.pagesTranslatedBefore > 0
            )
        }
        .buttonStyle(ShelfTranslateButtonStyle(model: model, press: press))
        // On and off are in the value (`readerTranslateAccessibility`).
        .accessibilityRemoveTraits(.isSelected)
        .readerTranslateAccessibility(ReaderTranslateAccessibility(
            isOn: isOn, pagesTranslatedBefore: translation.pagesTranslatedBefore,
            availability: model.translationAvailability
        ))
        .accessibilityActions {
            if isOn {
                Button(L10n.Localizable.Reader.Translate.original) {
                    translation.holdOriginal(!translation.isHoldingOriginal)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: isOn)
    }
}

/// Draws the press, and shows the original from the update that draws it.
private struct ShelfTranslateButtonStyle: ButtonStyle {
    let model: ReaderModel
    let press: ShelfTranslatePress

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    press.began(on: model)
                } else {
                    press.ended(on: model)
                }
            }
    }
}

/// One press of Translate: a tap or a hold. Not observable; nothing is drawn from it.
///
/// The finger going down and coming up reach it through the button style; a release on the
/// button reaches it through the button's action as well, in either order. A press shorter
/// than `holdDuration` that ends on the button is a tap and turns Translate on or off; a
/// longer one while Translate is on only lets the original go, and so does a press whose
/// finger slid off the button. An activation with no finger down (VoiceOver's double tap,
/// Switch Control, a keyboard) reaches only the action, and is a tap.
final class ShelfTranslatePress {
    /// From this long on, a press while Translate is on is a hold, not a tap.
    static let holdDuration: Duration = .milliseconds(350)

    private var start: ContinuousClock.Instant?
    /// Whether this press shows the original: Translate was on when it began.
    private var holdsOriginal = false
    /// Counts presses, so a late check of one press leaves the next alone.
    private var number = 0
    /// The press whose lift was handled. Equal to `number` when no finger went down since.
    private var liftedNumber = 0

    func began(on model: ReaderModel) {
        number += 1
        start = .now
        holdsOriginal = model.translation.isOn
        if holdsOriginal { model.translation.holdOriginal(true) }
    }

    /// The finger lifted on the button.
    func lifted(on model: ReaderModel) {
        guard liftedNumber != number else {
            // No finger went down since the last lift: an assistive activation, a tap.
            model.toggleTranslation()
            return
        }
        liftedNumber = number
        if isHold {
            model.translation.holdOriginal(false)
        } else {
            // Turning off keeps the original that the press shows; turning on shows the
            // translation.
            model.toggleTranslation()
        }
    }

    /// The press ended, on the button or off it.
    func ended(on model: ReaderModel) {
        guard holdsOriginal else { return }
        if isHold {
            model.translation.holdOriginal(false)
            return
        }
        // A short press is a tap only if the button's action comes; it may come after this,
        // in the same touch. Without it the finger slid off, and the original goes.
        let number = number
        Task { @MainActor [weak self] in
            guard let self, self.number == number, liftedNumber != number else { return }
            model.translation.holdOriginal(false)
        }
    }

    private var isHold: Bool {
        guard holdsOriginal, let start else { return false }
        return ContinuousClock.now - start >= Self.holdDuration
    }
}
