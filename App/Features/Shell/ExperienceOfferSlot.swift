import EhFeatures
import SwiftUI

/// Where the offer after install is presented from (`Design/designs/settings.md`, "The offer
/// after install"): a sheet attached above the bar's switch, up while the router's queue rule
/// allows (`ExperienceOfferModel.isPresented`). The sheet is built only then, so after the
/// first screen is up.
///
/// - Swiping the sheet away is "Not now". When something else takes its place (the lock, a
///   greeting), the sheet goes without that, and comes back once it may.
/// - Settings opens for "Set up step by step" only once the sheet has gone (`onDismiss`): the
///   shell presents one sheet at a time.
/// - A link's gallery takes precedence over the offer.
struct ExperienceOfferSlot: ViewModifier {
    let offer: ExperienceOfferModel
    let router: AppRouter

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: isPresented, onDismiss: { offer.didDismiss() }) {
                ExperienceOfferSheet(model: offer)
            }
            .onChange(of: router.presentedGallery != nil) { _, isPresented in
                if isPresented { offer.linkPresented() }
            }
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { offer.isPresented },
            // Only a swipe: a sheet taken away by the queue rule is not the user's "Not now".
            set: { if !$0, offer.isPresented { offer.notNow() } }
        )
    }
}
