import EhFeatures
import SwiftUI

/// Tells VoiceOver when a page on screen could not be translated ("Couldn't translate page
/// 23"), the same in every design: once per failure, when the page joins the failed pages on
/// screen. The status moving between the two pages of a spread says nothing again; a page
/// that fails again after Try again, or is turned back to, is said again. When two pages fail
/// at once, the nearer is said: one announcement would cut the other off.
///
/// It is the one status change worth speaking. VoiceOver reads nothing of a translated page
/// (the patches are pictures over the image), so "translating" and "done" would only talk over
/// the page turn; a failure asks for something, Try again, which the design's capsule, toast
/// or line holds wherever the controls are. Nothing is said while VoiceOver is off, and the
/// view reads only the failed pages, so a change re-renders this empty view alone.
struct ReaderTranslationAnnouncements: View {
    let translation: ReaderTranslationModel

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: translation.failedPagesOnScreen) { old, new in
                guard UIAccessibility.isVoiceOverRunning, let page = new.first(where: { !old.contains($0) }) else { return }
                AccessibilityNotification.Announcement(L10n.Localizable.Reader.Translate.Status.failed(page)).post()
            }
    }
}
