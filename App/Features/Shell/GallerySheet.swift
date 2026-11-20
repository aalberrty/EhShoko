import EhFeatures
import EhModels
import SwiftUI

/// The gallery opened from a deep link, a clipboard link or the share extension: always a
/// sheet with its own stack and its own chrome host for the page's dock, never a side pane.
/// Close, at the top leading edge of its root, puts it away, as the side pane's does.
///
/// Settings opened from the page in the sheet (a sign-in prompt, the reader's closing page)
/// comes up over the sheet, from inside it, so it is not opened underneath.
struct GallerySheet: ViewModifier {
    let router: AppRouter
    /// Whether this is the presenter of the gallery sheet: the topmost one below it.
    let isActive: Bool
    /// Settings is up over the gallery sheet, presented from inside it.
    var holdsSettings = false

    @Environment(\.chrome) private var chrome

    func body(content: Content) -> some View {
        content.sheet(item: presentedGallery) { gallery in
            GallerySheetStack(router: router, gallery: gallery)
                .environment(\.chrome, chrome.presented(isSheet: true))
                .sheet(isPresented: settings) {
                    SettingsSheet(router: router)
                        .newDawnSheet(router: router, isTopmost: true)
                }
                // The page in this sheet may receive the greeting; only the topmost presenter
                // can show it.
                .newDawnSheet(router: router, isTopmost: !holdsSettings)
        }
    }

    private var presentedGallery: Binding<Gallery?> {
        Binding(
            get: { isActive ? router.presentedGallery : nil },
            set: { if $0 == nil, isActive { router.dismissPresentedGallery() } }
        )
    }

    private var settings: Binding<Bool> {
        Binding(
            get: { holdsSettings && router.isSettingsPresented },
            set: { if !$0, holdsSettings { router.dismissSettings() } }
        )
    }
}

/// The sheet's stack: the gallery's page as its root, with Close.
private struct GallerySheetStack: View {
    let router: AppRouter
    let gallery: Gallery

    var body: some View {
        BottomChrome(router: router.presented) {
            RoutedStack(router: router.presented) {
                // The link's target (an image page or a comment) is honoured once.
                GalleryPage(
                    gallery: gallery,
                    intent: router.takePresentedGalleryTarget(for: gallery.gid).map(DetailIntent.init)
                )
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        SheetCloseButton { router.dismissPresentedGallery() }
                    }
                }
            }
        }
        .pushesGalleries(on: router.presented)
    }
}

/// Which of Settings and the link's gallery sheet is above the other while both are up: the
/// one that came second. Worked out from what was up before, so the sheet that was there
/// first is never taken down to be put under the other.
nonisolated struct ShellSheetOrder: Equatable, Sendable {
    var isSettingsUp = false
    var isGalleryUp = false
    /// Both are up, Settings above the gallery sheet.
    var settingsOverGallery = false

    /// The order once Settings and the gallery sheet are as given, from this one.
    func next(isSettingsUp: Bool, isGalleryUp: Bool) -> ShellSheetOrder {
        let settingsOverGallery: Bool = if !isSettingsUp || !isGalleryUp {
            false
        } else if self.isSettingsUp, self.isGalleryUp {
            self.settingsOverGallery
        } else {
            // Settings was asked for while the gallery sheet was up alone. A link arriving
            // while Settings is up, or both at once, puts the gallery above, as before.
            self.isGalleryUp && !self.isSettingsUp
        }
        return ShellSheetOrder(
            isSettingsUp: isSettingsUp, isGalleryUp: isGalleryUp, settingsOverGallery: settingsOverGallery
        )
    }

    /// Settings is presented by the root.
    var settingsAtRoot: Bool { isSettingsUp && !settingsOverGallery }

    /// The gallery sheet is presented by the root: alone, or under Settings.
    var galleryAtRoot: Bool { isGalleryUp && (!isSettingsUp || settingsOverGallery) }
}
