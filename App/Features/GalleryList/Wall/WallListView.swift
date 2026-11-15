import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// Wall's list of galleries (`wall.md` section 3): a wall of covers in three densities, which
/// a pinch or the More menu changes. Every list is drawn by it when the lists choice is Wall:
/// Front Page, Popular, Watched, Toplists, History, a favourites folder, search results.
///
/// `GalleryListScreen` owns the models, the first load, the sheets and the reader; this view
/// draws `input.feed`'s entries under `header`, places `input.controls` and reports choices to
/// `input.perform`. It works out the grid's layout and the cells' style once per change of
/// what they depend on (the density, the width, the text size, the tag settings, the look),
/// so a cell reads nothing itself.
///
/// The density is `SettingsStore.wallDensity`, which every wall shares. Each wall lays itself
/// out from its own copy and follows the setting, so that it can change its layout and its
/// scroll offset together and keep the row at its top where it is.
struct WallListView<Header: View>: View {
    let input: ListDesignInput
    @ViewBuilder var header: Header

    @State private var texts = WallCellTexts()
    @State private var prefetcher = ListCoverPrefetcher()
    @State private var tracker = WallListTracker()
    @State private var position = ScrollPosition()
    /// The density this wall is laid out in; `nil` until it changes one, when it is the
    /// setting's.
    @State private var density: WallDensity?
    @State private var cue = WallDensityCue.rest
    @State private var hint: WallDensityHint?
    /// The container's width, for the columns; 0 until it is known.
    @State private var width: CGFloat = 0
    @State private var hasAppeared = false
    /// For the zoom sources when no stack set the app's namespace (a preview).
    @Namespace private var localZoom

    @Environment(SettingsStore.self) private var settings
    @Environment(TagTranslationService.self) private var tagTranslations: TagTranslationService?
    @Environment(StackRouter.self) private var stack
    @Environment(\.zoomNamespace) private var zoomNamespace
    @Environment(\.look) private var look
    @Environment(\.lookTint) private var tint
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.displayScale) private var displayScale
    @Environment(\.chrome) private var chrome
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverOn
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let density = density ?? settings.wallDensity
        content(density)
            // Inside the chrome, so that it lies under the find field and not on its glass.
            .overlay(alignment: .top) { WallDensityHintView(hint: hint) }
            .modifier(WallListChrome(input: input, density: density, ownFolder: input.ownFolder(hasHeader: hasHeader)) {
                setDensity($0, from: density)
            })
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            // Another wall changed the setting (a tab's, or the list under a pushed one).
            .onChange(of: settings.wallDensity) { old, new in
                setDensity(new, from: self.density ?? old, announces: false)
            }
            .task(id: hint) {
                guard hint != nil else { return }
                try? await Task.sleep(for: .milliseconds(1_500))
                if !Task.isCancelled { hint = nil }
            }
            .onAppear {
                // Back from a gallery page pushed over the list, or from a reader it presented:
                // entries read their reading progress when their page was mapped.
                if hasAppeared {
                    Task { await input.feed.refreshReadingProgress() }
                }
                hasAppeared = true
            }
            .onDisappear { prefetcher.stop() }
            .followsFavoriteChanges(of: input)
    }

    @ViewBuilder
    private func content(_ density: WallDensity) -> some View {
        if WallListState.replacesList(input.feed.phase), !hasHeader {
            // Nothing to scroll: the state takes the screen, where its buttons may be glass.
            WallListState(input: input)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(look.background)
        } else if width > 0 {
            let layout = layout(for: density)
            WallListGrid(
                input: input, header: header, style: style(layout), layout: layout, pages: pages,
                primary: headerPrimary, cue: cue, selectedID: stack.sideGallery?.gid,
                prefetcher: prefetcher, tracker: tracker, position: $position
            ) { direction in
                if let next = density.stepped(direction) { setDensity(next, from: density) }
            }
            // VoiceOver's zoom, on any cover: the pinch for someone who cannot pinch.
            .accessibilityZoomAction { action in
                if let next = density.stepped(action.direction == .zoomIn ? 1 : -1) {
                    setDensity(next, from: density)
                }
            }
        } else {
            // One layout pass, until the width is known: no cell is made for a guessed width.
            look.background
        }
    }

    /// A first screen or the library passes a header; a list of its own passes none.
    private var hasHeader: Bool { !(Header.self is EmptyView.Type) }

    private var isRanked: Bool { input.context.kind == .place(.toplists) }

    /// Toplists' entries by page; `nil` for every other list.
    private var pages: RankedPages? {
        let feed = input.feed
        guard isRanked, feed.phase == .content else { return nil }
        return RankedPages(entries: feed.entries, pageStarts: feed.pageStarts, findText: feed.findText)
    }

    /// The filter pill or the sort menu, where the bar does not hold them and no first screen
    /// draws the list's heading; not over a list that cannot be shown (signed out, failed).
    private var headerPrimary: ListPrimaryControl? {
        guard !input.context.embedsInStart, !chrome.barHoldsPrimaryControl else { return nil }
        switch input.feed.phase {
        case .signedOut, .failed: return nil
        case .loading, .empty, .content: return input.controls.primary
        }
    }

    // MARK: Layout and style

    private var showsTags: Bool { settings.showsTagsInList }

    private func layout(for density: WallDensity) -> WallGridLayout {
        texts.prepare(WallCellTexts.Inputs(
            look: look, tint: tint, typeSize: typeSize,
            translations: settings.translatesTags ? tagTranslations : nil,
            translationCount: settings.translatesTags ? tagTranslations?.translations.count ?? 0 : 0
        ))
        return WallGridLayout(
            width: width, density: density,
            captionHeight: texts.metrics.captionHeight(for: density, showsTags: showsTags),
            usesLargeText: typeSize.isAccessibilitySize, displayScale: displayScale
        )
    }

    private func style(_ layout: WallGridLayout) -> WallCellStyle {
        WallCellStyle(
            density: layout.density, coverHeight: layout.coverHeight, captionHeight: layout.captionHeight,
            rowSpacing: layout.rowSpacing, facts: Self.facts(for: input.context.kind),
            tagLimit: layout.density == .large && showsTags ? tagsThatFit(layout) : 0,
            isDimmed: input.feed.staleError?.isNetworkError == true, isSpoken: isVoiceOverOn,
            zoom: zoomNamespace ?? localZoom, texts: texts, textsRevision: texts.revision
        )
    }

    /// Up to three chips (`wall.md` section 3), at most the setting's maximum (0 is none) and
    /// no more than a cell's width shows.
    private func tagsThatFit(_ layout: WallGridLayout) -> Int {
        let setting = settings.listTagsNumberMaximum
        let cap = setting > 0 ? min(setting, 3) : 3
        return min(cap, max(Int((layout.cellWidth / texts.metrics.chipWidth).rounded(.up)), 1))
    }

    private static func facts(for kind: ListKind) -> WallCellStyle.Facts {
        switch kind {
        case .folder, .scopedSearch(.favorites, _): .favorites
        case .place(.history): .history
        default: .standard
        }
    }

    // MARK: Density

    /// Where the rows are at `density`, for keeping one in place.
    private func map(for density: WallDensity) -> WallGridMap {
        WallGridMap(
            layout: layout(for: density), sections: pages?.sections ?? [input.feed.entries.count],
            top: tracker.cellsTop, dividerHeight: texts.metrics.dividerHeight
        )
    }

    /// Changes the density at once, with the row nearest the top edge kept where it is: the
    /// layout and the scroll offset change in one transaction without animation, and what
    /// moves is the wall as a whole, for a moment (`WallDensityCue`). Animating the cells to
    /// their new places is not possible with a lazy grid (`spikes/S1.md`): it shows the old
    /// layout at the new offset for a frame or two, and can crash.
    private func setDensity(_ next: WallDensity, from current: WallDensity, announces: Bool = true) {
        guard next != current else { return }
        let old = map(for: current)
        let new = map(for: next)
        // The row an earlier change kept, until someone scrolls: taking the top row's first
        // entry again at every step lets the place slip back a little each time.
        let kept = tracker.kept.flatMap { $0.map == old ? $0 : nil }
        let change = old.offset(keeping: kept?.anchor, from: kept?.offset ?? tracker.offset, in: new)
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            density = next
            if change.anchor != nil {
                position.scrollTo(y: change.offset)
            }
            cue = WallDensityCue(from: old.layout, to: new.layout, moves: !reduceMotion)
        }
        tracker.keep(change.anchor, at: change.offset, in: new)
        // After the frame that shows the new layout: the scale and the fade settle.
        Task { cue = .rest }
        if settings.wallDensity != next {
            settings.wallDensity = next
        }
        guard announces else { return }
        let columns = Dictionary(uniqueKeysWithValues: WallDensity.allCases.map { density in
            (density, WallGridLayout.columns(width: width, density: density, usesLargeText: typeSize.isAccessibilitySize))
        })
        let hint = WallDensityHint(density: next, columns: columns, serial: (self.hint?.serial ?? 0) + 1)
        self.hint = hint
        AccessibilityNotification.Announcement(hint.announcement).post()
    }
}
