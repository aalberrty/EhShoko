import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// The full-screen reader for a gallery (legacy `ReadingView`). Present it with `readerCover`.
/// `initialPage` is 1-based; nil opens at the stored reading progress. `detail` is the
/// gallery's detail page when the presenter has it, for the title.
///
/// Three layers: the background, the UIKit reading engine, and the controls on top. The
/// controls are the reader part's switch point (`Design/designs/README.md` section 4): the
/// one place that reads `designReader`. Every controls design drives the same `ReaderModel`
/// and is given the same two things, the model and the `ReaderViewport`; none knows who
/// presented the reader.
///
/// The engine reads the reading settings and nothing of the controls, so showing them,
/// dragging the slider or turning a page never re-renders it. Only the viewport's inset
/// reaches its frame, and only a design that covers the page sets it.
struct ReaderScreen: View {
    @State private var session: ReaderSession

    init(gallery: Gallery, initialPage: Int? = nil, detail: GalleryDetail? = nil) {
        // Only the holder is made here. A view's `init` runs again every time the presenting
        // screen is re-evaluated (when the detail page finishes loading behind the open reader,
        // for one) and SwiftUI keeps the first value: a model made here would be built, with
        // its resolver, writer and loader, and thrown away each time.
        _session = State(initialValue: ReaderSession(gallery: gallery, initialPage: initialPage, detail: detail))
    }

    var body: some View {
        let model = session.model
        ZStack {
            // What the engine paints behind its pages, here while the stored pages are read.
            Color(uiColor: .readerBackground).ignoresSafeArea()
            ReaderEngineFrame(viewport: session.viewport) {
                ReaderEngineHost(model: model, bridge: session.bridge)
            }
            ReaderControls(model: model, viewport: session.viewport)
        }
        .modifier(ReaderChrome(model: model))
        .task { await model.start() }
        .onDisappear { model.close() }
    }
}

/// The reader's model, its bridge to the engine and its viewport, made the first time the
/// screen's body asks for them: once per presented reader.
private final class ReaderSession {
    private let gallery: Gallery
    private let initialPage: Int?
    private let detail: GalleryDetail?

    private(set) lazy var model = ReaderModel(gallery: gallery, initialPage: initialPage, detail: detail)
    private(set) lazy var bridge = ReaderEngineBridge(model: model, viewport: viewport)
    let viewport = ReaderViewport()

    init(gallery: Gallery, initialPage: Int?, detail: GalleryDetail?) {
        self.gallery = gallery
        self.initialPage = initialPage
        self.detail = detail
    }
}

/// The reader part's switch point. Each branch is that design's controls; until a design is
/// built its file adapts today's control panel.
private struct ReaderControls: View {
    let model: ReaderModel
    let viewport: ReaderViewport

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        switch settings.designReader {
        case .shelf: ShelfReaderControls(model: model, viewport: viewport)
        case .wall: WallReaderControls(model: model, viewport: viewport)
        case .ledger: LedgerReaderControls(model: model, viewport: viewport)
        }
    }
}

/// Where the engine draws: the whole screen, less the viewport's bottom inset. The padding is
/// inside `ignoresSafeArea`, so the inset is measured from the screen's edge (spike S4). It is
/// its own view so that a change of the inset reaches the engine's frame and nothing else, and
/// it hands the look to the engine's page status views, which are UIKit.
private struct ReaderEngineFrame<Content: View>: View {
    let viewport: ReaderViewport
    @ViewBuilder let content: Content

    @Environment(\.look) private var look
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        content
            .padding(.bottom, viewport.bottomInset)
            .ignoresSafeArea()
            .environment(\.readerPageStyle, ReaderPageStyle(look: look, accent: settings.accentColor))
    }
}

/// The engine, configured from the individual reading settings so a change applies live.
private struct ReaderEngineHost: View {
    let model: ReaderModel
    let bridge: ReaderEngineBridge

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        if model.isReady {
            ReaderEngineView(
                configuration: configuration, initialPage: model.initialPage,
                proxy: bridge.proxy, dataSource: bridge, delegate: bridge
            )
        }
    }

    private var configuration: ReaderConfiguration {
        ReaderConfiguration(
            direction: direction,
            allowsDualPage: settings.enablesDualPageMode,
            exceptCover: settings.exceptCover,
            pageGap: settings.contentDividerHeight,
            maximumZoomScale: settings.maximumScaleFactor,
            doubleTapZoomScale: settings.doubleTapScaleFactor,
            prefetchLimit: settings.prefetchLimit,
            isLiveTextEnabled: model.isLiveTextEnabled
        )
    }

    private var direction: ReaderDirection {
        switch settings.readingDirection {
        case .vertical: .vertical
        case .rightToLeft: .rightToLeft
        case .leftToRight: .leftToRight
        }
    }
}

/// Everything around the reader that follows the model and is the same in every design:
/// status bar, HUD and haptics. A modifier, so its updates do not run the screen's body. The
/// sheets of `model.destination` are not here: each design attaches them where it can show
/// them (`readerDestinationSheets(_:)`).
private struct ReaderChrome: ViewModifier {
    let model: ReaderModel

    @Environment(SettingsStore.self) private var settings

    func body(content: Content) -> some View {
        content
            // Legacy: the status bar shows with the controls.
            .statusBarHidden(!model.showsPanel)
            .hud(notice)
            .sensoryFeedback(.impact(flexibility: .soft), trigger: model.showsSliderPreview)
            .sensoryFeedback(.impact(weight: .light), trigger: model.destination) { _, destination in
                destination != nil
            }
            .onChange(of: settings.enablesLandscape) { _, isEnabled in
                model.enablesLandscapeDidChange(isEnabled)
            }
    }

    private var notice: Binding<HUDConfiguration?> {
        Binding(
            get: { model.notice?.hud },
            set: { if $0 == nil { model.notice = nil } }
        )
    }
}
