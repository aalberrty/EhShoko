import EhCore
import EhFeatures
import SwiftUI

extension View {
    /// What a list shows after an action from its long-press menu or swipe actions: a HUD
    /// naming the folder a favourite went into ("Added to To Read"), and a haptic for success
    /// or failure. Apply it once, at the list's screen.
    ///
    /// It observes only the actions model's report and feedback, which change once per action,
    /// so the list's rows are not invalidated by it.
    func galleryActionsFeedback(_ actions: GalleryActionsModel) -> some View {
        modifier(GalleryActionsFeedback(actions: actions))
    }
}

private struct GalleryActionsFeedback: ViewModifier {
    let actions: GalleryActionsModel

    @Environment(UserStore.self) private var userStore
    @State private var hud: HUDConfiguration?

    func body(content: Content) -> some View {
        content
            .hud($hud)
            .onChange(of: actions.favoriteReport) { _, report in
                guard let report else { return }
                hud = .symbol(
                    "heart.fill", title: L10n.Localizable.List.Favorited.hud(userStore.favoriteFolderName(report.folder))
                )
            }
            .sensoryFeedback(trigger: actions.feedback) { _, feedback in
                feedback.map { $0.isSuccess ? SensoryFeedback.success : .error }
            }
    }
}
