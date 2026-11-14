import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// A gallery's page (`Design/designs/README.md` sections 4 and 5.4): pushed for
/// `Route.detail`, the root of the side pane, the root of the gallery sheet opened from a
/// link. The gallery part's switch point: with `GalleryChildScreen`, the place that reads
/// `designGallery` to decide what a gallery page is.
///
/// Above the switch it owns the page's model and what every gallery design shares, so that a
/// change of design keeps what is loaded: the load, the child screens the page pushes, its
/// sheets, the reader it opens, the daily greeting it may receive, and its haptics. A design
/// draws the page and declares its bottom actions with `.dock(_:perform:)`; it presents
/// nothing itself, it sets `model.destination` through the model's own methods.
struct GalleryPage: View {
    @State private var model: GalleryDetailModel

    @Environment(SettingsStore.self) private var settings

    init(gallery: Gallery, intent: DetailIntent? = nil) {
        _model = State(initialValue: GalleryDetailModel(gallery: gallery, intent: intent))
    }

    var body: some View {
        page.modifier(GalleryPageHost(model: model))
    }

    @ViewBuilder
    private var page: some View {
        switch settings.designGallery {
        case .shelf: ShelfGalleryView(model: model)
        case .wall: WallGalleryView(model: model)
        case .ledger: LedgerGalleryView(model: model)
        }
    }
}

/// What a gallery page does whatever draws it.
private struct GalleryPageHost: ViewModifier {
    @Bindable var model: GalleryDetailModel

    @Environment(AppRouter.self) private var appRouter: AppRouter?
    @Environment(StackRouter.self) private var stack: StackRouter?

    func body(content: Content) -> some View {
        content
            .task { await model.load() }
            // Pushed children are entries of the stack's path, never pushed from the page.
            .onChange(of: model.pushedDestination, initial: true) { _, destination in
                guard let destination, let stack else { return }
                stack.push(.detailChild(DetailChildRoute(parent: model, destination: destination)))
                model.pushedDestination = nil
            }
            .sheet(item: $model.sheetDestination) { destination in
                GalleryChildScreen(sheet: destination, model: model)
            }
            // `readerCover(destination:of:)` replaces this line when the reader's shared
            // layer is merged.
            .fullScreenCover(item: $model.fullScreenDestination) { destination in
                if case .reader(let page) = destination {
                    ReaderScreen(gallery: model.gallery, initialPage: page)
                }
            }
            .sensoryFeedback(trigger: model.feedback) { _, feedback in
                feedback.map { $0.isSuccess ? .success : .error }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: model.destination) { _, destination in
                destination.map { $0.presentation != .push } ?? false
            }
            .onChange(of: model.greetingToAnnounce, initial: true) { _, greeting in
                guard let greeting, let appRouter else { return }
                appRouter.presentedGreeting = greeting
                model.greetingAnnounced()
            }
    }
}
