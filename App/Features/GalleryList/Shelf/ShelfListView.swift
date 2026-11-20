import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// Shelf's list of galleries (`shelf.md` section 3): a plain `List` of `ShelfGalleryRow`, or on
/// a container 700 pt wide or more, a lazy grid of the same rows in two or three columns. Every
/// list is drawn by it when the lists choice is Shelf: Front Page, Popular, Watched, Toplists,
/// History, a favourites folder, search results.
///
/// `GalleryListScreen` owns the models, the first load, the sheets and the reader; this view
/// draws `input.feed`'s rows under `header`, places `input.controls` and reports choices to
/// `input.perform`. It works out the rows' style once per change of what the rows depend on
/// (the tag settings, the text size, the width, the look), so a row reads nothing itself.
struct ShelfListView<Header: View>: View {
    let input: ListDesignInput
    @ViewBuilder var header: Header

    @State private var texts = ShelfRowTexts()
    @State private var prefetcher = ListCoverPrefetcher()
    /// The container's width, for the columns and the tags that fit; 0 until it is known.
    @State private var width: CGFloat = 0
    @State private var hasAppeared = false
    /// For the zoom sources when no stack set the app's namespace (a preview).
    @Namespace private var localZoom

    @Environment(SettingsStore.self) private var settings
    @Environment(TagTranslationService.self) private var tagTranslations: TagTranslationService?
    @Environment(UserStore.self) private var userStore: UserStore?
    @Environment(\.zoomNamespace) private var zoomNamespace
    @Environment(\.look) private var look
    @Environment(\.lookTint) private var tint
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.chrome) private var chrome
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverOn
    #if DEBUG || HARNESS
    /// Set by the list harness alone, to measure the grid at a phone's width.
    @Environment(\.shelfListAlwaysUsesGrid) private var alwaysUsesGrid
    #endif

    var body: some View {
        content
            .modifier(ShelfListChrome(input: input, width: width, ownFolder: input.ownFolder(hasHeader: hasHeader)))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .onAppear {
                // Back from a gallery page pushed over the list, or from a reader it presented:
                // the rows read their reading progress when their page was mapped.
                if hasAppeared {
                    Task { await input.feed.refreshReadingProgress() }
                }
                hasAppeared = true
            }
            .onDisappear { prefetcher.stop() }
    }

    @ViewBuilder
    private var content: some View {
        let phase = input.feed.phase
        if ShelfListLayout.isFullScreen(phase), !hasHeader {
            // Nothing to scroll: the state takes the screen, where its buttons may be glass.
            ShelfListState(input: input)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(look.background)
        } else if usesGrid {
            ShelfListGrid(
                input: input, header: header, style: style, columns: columns, headerLine: headerLine,
                prefetcher: prefetcher
            )
        } else {
            ShelfListRows(input: input, header: header, style: style, headerLine: headerLine, prefetcher: prefetcher)
        }
    }

    /// A first screen or the library passes a header; a list of its own passes none.
    private var hasHeader: Bool { !(Header.self is EmptyView.Type) }

    /// The lazy grid from two columns on; one column is the `List`.
    private var usesGrid: Bool {
        #if DEBUG || HARNESS
        if alwaysUsesGrid { return true }
        #endif
        return columns > 1
    }

    /// One column under 700 pt, two from 700, three from 1,100 (`shelf.md` section 3).
    private var columns: Int {
        switch width {
        case 1_100...: 3
        case 700...: 2
        default: 1
        }
    }

    /// The filter pill or the sort line, where the bar does not hold them and no first screen
    /// draws the list's heading; not over a list that cannot be shown (signed out, failed).
    private var headerLine: ListPrimaryControl? {
        guard input.context.drawsHeadingLine, !chrome.barHoldsPrimaryControl else { return nil }
        switch input.feed.phase {
        case .signedOut, .failed: return nil
        case .loading, .empty, .content: return input.controls.primary
        }
    }

    private var style: ShelfRowStyle {
        let context = input.context
        let footer = Self.footer(for: context.kind)
        let isRanked = context.kind == .place(.toplists)
        texts.prepare(ShelfRowTexts.Inputs(
            look: look, tint: tint, typeSize: typeSize,
            translations: settings.translatesTags ? tagTranslations : nil,
            translationCount: settings.translatesTags ? tagTranslations?.translations.count ?? 0 : 0,
            folderNames: footer == .favorites ? (0..<10).map { userStore?.favoriteFolderName($0) ?? "" } : []
        ))
        let metrics = texts.metrics
        let tagLimit = isRanked || !settings.showsTagsInList ? 0 : tagsThatFit(metrics)
        return ShelfRowStyle(
            isRanked: isRanked, footer: footer, tagLimit: tagLimit, isSpoken: ListSpokenRows.isOn(isVoiceOverOn),
            height: isRanked ? metrics.ranked : tagLimit > 0 ? metrics.standard.tags : metrics.standard.plain,
            zoom: zoomNamespace ?? localZoom, texts: texts, textsRevision: texts.revision
        )
    }

    /// The setting's maximum (0 is none), at most the entries' own cap, and no more chips than
    /// one line of the row can show: a chip is about 56 pt at the default text size.
    private func tagsThatFit(_ metrics: ShelfRowMetrics) -> Int {
        let setting = settings.listTagsNumberMaximum
        let cap = setting > 0 ? min(setting, GalleryEntry.rowTagLimit) : GalleryEntry.rowTagLimit
        // Until the width is known, a phone's: five chips.
        guard width > 0 else { return min(cap, 5) }
        let column = (width - ShelfListLayout.gridSpacing * CGFloat(columns - 1)) / CGFloat(columns)
        let text = column - ShelfListLayout.rowInsets.leading - ShelfListLayout.rowInsets.trailing
            - ShelfGalleryRow.textInset(isRanked: false)
        return min(cap, max(Int((text / metrics.chipWidth).rounded(.up)), 1))
    }

    private static func footer(for kind: ListKind) -> ShelfRowStyle.Footer {
        switch kind {
        case .folder, .scopedSearch(.favorites, _): .favorites
        case .place(.history): .history
        default: .posted
        }
    }
}

/// The insets and spacing the two containers share.
enum ShelfListLayout {
    /// 8 pt above and below, 20 leading, 16 trailing.
    static let rowInsets = EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 16)
    /// Ranked rows start nearer the edge, where the rank sits.
    static let rankedInsets = EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 16)
    /// The filter or sort line under the title.
    static let lineInsets = EdgeInsets(top: 4, leading: 20, bottom: 6, trailing: 16)
    static let bannerInsets = EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16)
    /// Toplists' "Page 2".
    static let dividerInsets = EdgeInsets(top: 10, leading: 20, bottom: 6, trailing: 16)
    /// A state under a header takes at least this much of the list.
    static let stateHeight: CGFloat = 360
    static let gridSpacing: CGFloat = 12

    static func insets(isRanked: Bool) -> EdgeInsets {
        isRanked ? rankedInsets : rowInsets
    }

    /// The states that take the list's place, under its header if it has one: everything but
    /// rows and their placeholders.
    static func isFullScreen(_ phase: ListFeed.Phase) -> Bool {
        switch phase {
        case .signedOut, .empty, .failed: true
        case .loading, .content: false
        }
    }
}
