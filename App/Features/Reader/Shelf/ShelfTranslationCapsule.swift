import EhFeatures
import SwiftUI

private typealias Strings = L10n.Localizable.Reader.Translate

/// Translation's state, in a glass capsule above the panel (`shelf.md` section 5, `README` 7.5):
/// "Translating page 23…", "简体中文 | Hold Translate to see the original", "Couldn't translate
/// page 23 | Try again". It is a shape of the panel's glass container, so it is shown and hidden
/// with the controls and is never glass on glass.
///
/// It shows the current page's status while Translate is on, and the download while a press
/// waits for the models. Otherwise there is nothing: Translate not pressed, an animated page,
/// the closing page.
struct ShelfTranslationCapsule: View {
    let model: ReaderModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let content = ShelfTranslationCapsuleContent(model: model)
        ZStack {
            if let content {
                ShelfTranslationCapsuleRow(content: content) { model.retryTranslation() }
                    // With Reduce Motion it only fades, as Wall's toast does.
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
            }
        }
        .animation(.smooth(duration: 0.25), value: content?.kind)
    }
}

/// What the capsule says, from the model's few observable values.
private struct ShelfTranslationCapsuleContent: Equatable {
    enum Kind: Equatable {
        /// Getting ready, a page in work, the models downloading: a spinner.
        case working
        /// The page shows its translation, or there was nothing to draw on it.
        case done
        /// The original is held.
        case original
        /// With Retry.
        case failed
    }

    let kind: Kind
    let text: String
    /// After a separator, in the secondary colour: how to see the original.
    var detail: String?

    init?(model: ReaderModel) {
        let translation = model.translation
        guard let status = translation.status else {
            guard translation.isWaitingForModels, let text = model.translationAvailability.installingText else { return nil }
            self.init(kind: .working, text: text)
            return
        }
        if translation.isHoldingOriginal, !status.offersRetry {
            self.init(kind: .original, text: Strings.original)
            return
        }
        switch status {
        case .gettingReady, .translating:
            guard let text = status.text(showsDone: true) else { return nil }
            self.init(kind: .working, text: text)
        case .translated, .nothingToDraw:
            // `ReaderTranslationStatus.doneText` in two parts, as the capsule draws them.
            self.init(kind: .done, text: Strings.target, detail: Strings.Status.hold)
        case .failed:
            guard let text = status.text(showsDone: true) else { return nil }
            self.init(kind: .failed, text: text, detail: ReaderTranslationStatus.retryTitle)
        }
    }

    private init(kind: Kind, text: String, detail: String? = nil) {
        self.kind = kind
        self.text = text
        self.detail = detail
    }
}

private struct ShelfTranslationCapsuleRow: View {
    let content: ShelfTranslationCapsuleContent
    let retry: () -> Void

    @Environment(\.look) private var look
    @Environment(\.lookTint) private var tint
    @Environment(\.onTint) private var onTint

    private static let height: CGFloat = 38
    /// Around Try again's title, inside the capsule's end.
    private static let retryInset: CGFloat = 8

    var body: some View {
        HStack(spacing: 8) {
            badge
            Text(content.text)
                .foregroundStyle(look.label)
            if let detail = content.detail {
                Rectangle()
                    .fill(look.separator)
                    .frame(width: 1, height: 16)
                    .accessibilityHidden(true)
                if content.kind == .failed {
                    Button(action: retry) {
                        Text(detail)
                            .fontWeight(.semibold)
                            .foregroundStyle(tint)
                            // The whole height of the capsule and its end take the touch, not
                            // only the word.
                            .padding(.horizontal, Self.retryInset)
                            .frame(minHeight: Self.height)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(detail)
                        .foregroundStyle(look.secondaryLabel)
                }
            }
        }
        .font(.footnote.weight(.medium))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.leading, 8)
        .padding(.trailing, content.kind == .failed ? 14 - Self.retryInset : 14)
        .frame(minHeight: Self.height)
        .glassSurface(in: Capsule(), isInteractive: content.kind == .failed)
        .accessibilityElement(children: content.kind == .failed ? .contain : .combine)
    }

    /// A 22 pt disc in the tint with the state's symbol, or a spinner while work goes on.
    @ViewBuilder private var badge: some View {
        switch content.kind {
        case .working:
            ProgressView()
                .controlSize(.small)
                .tint(tint)
                .frame(width: 22, height: 22)
        case .done, .original, .failed:
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(onTint)
                .frame(width: 22, height: 22)
                .background(tint, in: .circle)
                .accessibilityHidden(true)
        }
    }

    private var symbol: String {
        switch content.kind {
        case .done: "checkmark"
        case .original: "eye"
        case .failed, .working: "exclamationmark"
        }
    }
}
