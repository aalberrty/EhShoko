import EhFeatures
import SwiftUI

/// Tells VoiceOver when the current page could not be translated ("Couldn't translate page
/// 23"), the same in every design.
///
/// It is the one status change worth speaking. VoiceOver reads nothing of a translated page
/// (the patches are pictures over the image), so "translating" and "done" would only talk over
/// the page turn; a failure asks for something, Try again, which the design's capsule, toast
/// or line holds wherever the controls are. Nothing is said while VoiceOver is off, and the
/// view reads only the status, so a change re-renders this empty view alone.
struct ReaderTranslationAnnouncements: View {
    let translation: ReaderTranslationModel

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: failedPage) { _, page in
                guard let page, UIAccessibility.isVoiceOverRunning else { return }
                AccessibilityNotification.Announcement(L10n.Localizable.Reader.Translate.Status.failed(page)).post()
            }
    }

    private var failedPage: Int? {
        if case .failed(let page) = translation.status { page } else { nil }
    }
}
