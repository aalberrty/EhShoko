import EhCore
import EhFeatures
import SwiftUI

private typealias Download = L10n.Localizable.Translation.Download

/// The download sheet's first screen: the symbol, the title and what the feature does, the
/// progress, the two buttons and the lines under them. Fills and text from the look; nothing
/// is glass on the sheet's glass.
struct ReaderTranslationDownloadPanel: View {
    let store: PageTranslationModelStore
    let translation: ReaderTranslationModel
    let close: () -> Void

    @Environment(StackRouter.self) private var router
    @Environment(\.look) private var look
    /// The title colour on the tint: black on Wall's white tint in dark mode.
    @Environment(\.onTint) private var onTint
    @State private var pace = ReaderTranslationDownloadPace()

    var body: some View {
        let state = store.requiredModelsState
        let content = ReaderTranslationDownloadContent(state: state, isConnected: store.isConnected)
        ScrollView {
            VStack(spacing: 0) {
                header
                if content.fraction != nil || content.statusLine != nil {
                    progress(content, state: state)
                        .padding(.top, Tokens.Spacing.xLarge)
                }
                if let detail = content.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(look.secondaryLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Tokens.Spacing.small)
                }
                buttons(content)
                    .padding(.top, Tokens.Spacing.xLarge)
                footnotes
                    .padding(.top, Tokens.Spacing.medium)
            }
            .padding(.horizontal, Tokens.Spacing.xLarge + Tokens.Spacing.xSmall)
            .padding(.top, Tokens.Spacing.xLarge)
            .padding(.bottom, Tokens.Spacing.large)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onChange(of: state.progress, initial: true) { _, progress in
            pace.note(content.isTransferring ? progress : nil, at: .now)
        }
        .onChange(of: state == .ready) { _, isReady in
            // Translate turns itself on in the reader (`isWaitingForModels`); on a pushed
            // Settings screen the sheet stays where the user is.
            if isReady, router.isAtRoot { close() }
        }
    }

    private var header: some View {
        VStack(spacing: Tokens.Spacing.small) {
            Image(systemName: "translate")
                .font(.largeTitle)
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
                .foregroundStyle(look.label)
                .frame(width: 64, height: 64)
                .background(look.fill, in: .rect(cornerRadius: 20, style: .continuous))
                .padding(.bottom, Tokens.Spacing.xSmall)
                .accessibilityHidden(true)
            Text(Download.title(PageTranslationDevice.name))
                .font(.title2.bold())
                .foregroundStyle(look.label)
                .accessibilityAddTraits(.isHeader)
            Text(Download.body)
                .font(.subheadline)
                .foregroundStyle(look.secondaryLabel)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func progress(_ content: ReaderTranslationDownloadContent, state: ModelSetState) -> some View {
        VStack(spacing: Tokens.Spacing.small) {
            if let fraction = content.fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
            }
            HStack(alignment: .firstTextBaseline) {
                if let line = content.statusLine {
                    Text(line)
                        .monospacedDigit()
                        .foregroundStyle(look.label)
                }
                Spacer(minLength: Tokens.Spacing.small)
                if content.isTransferring, let progress = state.progress,
                   let remaining = pace.remainingText(of: progress) {
                    Text(remaining)
                        .monospacedDigit()
                        .foregroundStyle(look.secondaryLabel)
                }
            }
            .font(.footnote)
        }
        .accessibilityElement(children: .combine)
    }

    /// Side by side as drawn; one above the other when a title would not fit on one line
    /// ("Download 1.18 GB" beside "Keep Reading" in a large text size or a long language).
    private func buttons(_ content: ReaderTranslationDownloadContent) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Tokens.Spacing.small + Tokens.Spacing.xxSmall) {
                buttonRow(content, prominentFirst: false)
            }
            VStack(spacing: Tokens.Spacing.small + Tokens.Spacing.xxSmall) {
                buttonRow(content, prominentFirst: true)
            }
        }
        .controlSize(.large)
        .buttonBorderShape(.capsule)
    }

    /// The two buttons in reading order: the secondary one leading in a row, the prominent
    /// one first when they stack.
    @ViewBuilder
    private func buttonRow(_ content: ReaderTranslationDownloadContent, prominentFirst: Bool) -> some View {
        if prominentFirst { prominentButton(content.primary) }
        if let secondary = content.secondary {
            Button { perform(secondary) } label: { buttonLabel(secondary) }
                .buttonStyle(.bordered)
        }
        if !prominentFirst { prominentButton(content.primary) }
    }

    private func prominentButton(_ action: ReaderTranslationDownloadContent.Action) -> some View {
        Button { perform(action) } label: { buttonLabel(action) }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(onTint)
    }

    private func buttonLabel(_ action: ReaderTranslationDownloadContent.Action) -> some View {
        Text(action.title)
            .fontWeight(.semibold)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var footnotes: some View {
        VStack(spacing: Tokens.Spacing.small) {
            // True only while this reader waits: it turns Translate on when the models are in.
            if translation.isWaitingForModels {
                Text(Download.footer)
            }
            if store.requiredModelsIncludeNonCommercial {
                Text(Download.nc)
            }
        }
        .font(.footnote)
        .foregroundStyle(look.secondaryLabel)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func perform(_ action: ReaderTranslationDownloadContent.Action) {
        switch action {
        case .download, .retry: store.downloadRequiredModels()
        case .pause: store.pause()
        case .resume: store.resume()
        case .openSettings: router.push(.settings(.pageTranslation))
        case .keepReading: close()
        }
    }
}
