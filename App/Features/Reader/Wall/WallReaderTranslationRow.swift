import EhFeatures
import SwiftUI

/// The row above the cluster while Translate is on (`wall.md` section 5): at the leading
/// side the pill that chooses what the pages show, at the trailing side the toast with the
/// current page's status. Both are glass shapes of Wall's one container.
///
/// The row is not in the hierarchy while Translate is off, so it takes no room. While it
/// shows, the filmstrip's place stands above it: the thumbnails rise over the row as they do
/// over the cluster.
struct WallReaderTranslationRow: View {
    let model: ReaderModel

    var body: some View {
        let isOn = model.translation.isOn
        Group {
            if isOn {
                row
            }
        }
        .animation(.smooth(duration: 0.25), value: isOn)
    }

    private var row: some View {
        ReaderTranslationSlot(availability: model.translationAvailability) {
            // Side by side where both fit; on a narrow screen, a long status or a large
            // text size, the toast stands over the pill, still at its side.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: WallReaderMetrics.clusterSpacing) {
                    WallReaderTranslationPill(model: model)
                    Spacer(minLength: 0)
                    WallReaderTranslationToast(model: model)
                }
                VStack(alignment: .trailing, spacing: Tokens.Spacing.medium) {
                    WallReaderTranslationToast(model: model)
                    WallReaderTranslationPill(model: model)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .transition(.opacity)
    }
}

/// The pill: Original, Compare and Translated, the one chosen filled with the tint. Its labels
/// are the wipe's 原文 and 译文, as drawn (they name the two sides of the page in every
/// language), with the split rectangle for Compare between them; VoiceOver reads the full
/// words. Compare puts the wipe over the page (`ReaderTranslationWipe`).
private struct WallReaderTranslationPill: View {
    let model: ReaderModel

    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let modes: [ReaderTranslationDisplayMode] = [.original, .compare, .translated]

    var body: some View {
        let chosen = model.translation.displayMode
        HStack(spacing: 0) {
            ForEach(Self.modes, id: \.self) { mode in
                WallReaderPillSegment(mode: mode, isChosen: mode == chosen, selection: selection) {
                    model.translation.setDisplayMode(mode)
                }
            }
        }
        .padding(WallReaderPillSegment.inset)
        .frame(height: WallReaderMetrics.rowHeight)
        .fixedSize(horizontal: true, vertical: false)
        .glassSurface(in: .capsule, isInteractive: true)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: chosen)
        .sensoryFeedback(.selection, trigger: chosen)
        .accessibilityElement(children: .contain)
    }
}

private struct WallReaderPillSegment: View {
    let mode: ReaderTranslationDisplayMode
    let isChosen: Bool
    let selection: Namespace.ID
    let action: () -> Void

    @Environment(\.look) private var look
    @Environment(\.lookTint) private var tint
    @Environment(\.onTint) private var onTint

    /// Between the pill's edge and its segments.
    static let inset: CGFloat = 4
    private static let minimumWidth: CGFloat = 52

    var body: some View {
        Button(action: action) {
            label
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(isChosen ? onTint : look.label)
                .padding(.horizontal, Tokens.Spacing.medium)
                .frame(minWidth: Self.minimumWidth, maxHeight: .infinity)
                .background {
                    // A fill on the pill's glass, not glass on glass.
                    if isChosen {
                        Capsule().fill(tint).matchedGeometryEffect(id: "chosen", in: selection)
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    @ViewBuilder private var label: some View {
        switch mode {
        case .original: Text(L10n.Localizable.Reader.Translate.Wipe.original)
        case .compare: Image(systemName: "rectangle.split.2x1")
        case .translated: Text(L10n.Localizable.Reader.Translate.Wipe.translated)
        }
    }

    private var accessibilityTitle: String {
        switch mode {
        case .original: L10n.Localizable.Reader.Translate.original
        case .translated: L10n.Localizable.Reader.Translate.translated
        case .compare: L10n.Localizable.Reader.Translate.compare
        }
    }
}

/// The toast: the current page's status ("Translating page 23…" with a spinner, "Getting
/// translation ready…", "Couldn't translate page 23" with Retry). A page that is done has
/// none: the pill is how to see the original. Not in the hierarchy while there is nothing to
/// say.
private struct WallReaderTranslationToast: View {
    let model: ReaderModel

    @Environment(\.look) private var look
    @Environment(\.lookTint) private var tint
    @Environment(\.onTint) private var onTint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let status = model.translation.status
        Group {
            if let status, let text = status.text(showsDone: false) {
                HStack(spacing: Tokens.Spacing.small) {
                    if status.isWorking {
                        ProgressView()
                            .controlSize(.small)
                            .tint(look.label)
                    } else if status.offersRetry {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(look.secondaryLabel)
                            .accessibilityHidden(true)
                    }
                    Text(text)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(look.label)
                        // A second line rather than a cut, where the toast stands over the
                        // pill and is still too narrow (a large text size).
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                    if status.offersRetry {
                        retry
                    }
                }
                .padding(.leading, Tokens.Spacing.medium)
                .padding(.trailing, status.offersRetry ? Tokens.Spacing.xSmall + 2 : Tokens.Spacing.large)
                .frame(minHeight: WallReaderMetrics.rowHeight)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .glassSurface(in: .capsule)
                // One element, except that Try again stays a button of its own: combined, the
                // toast itself became the button.
                .accessibilityElement(children: status.offersRetry ? .contain : .combine)
                .transition(reduceMotion ? AnyTransition.opacity : .opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
            }
        }
        .animation(.smooth(duration: 0.25), value: status)
    }

    /// Retry, a small capsule in the tint on the toast's glass.
    private var retry: some View {
        Button(action: model.retryTranslation) {
            Text(ReaderTranslationStatus.retryTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(onTint)
                .padding(.horizontal, Tokens.Spacing.medium)
                .frame(height: WallReaderMetrics.rowHeight - 2 * (Tokens.Spacing.xSmall + 2))
                .background(tint, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}
