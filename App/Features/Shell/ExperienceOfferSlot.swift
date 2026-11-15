import EhFeatures
import SwiftUI

/// Where the offer after install is presented from (`Design/designs/settings.md`, "The offer
/// after install"): a sheet attached above the bar's switch, shown while
/// `AppRouter.showsOffer` allows.
///
/// Handed to the offer's task (F16), which replaces this body with its sheet. Nothing sets
/// `AppRouter.offer` until then, so this is never shown.
struct ExperienceOfferSlot: View {
    let router: AppRouter

    var body: some View {
        NavigationStack {
            Color.clear
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        SheetCloseButton { router.offer = false }
                    }
                }
        }
    }
}
