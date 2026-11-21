import Dependencies
import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// The sheet a press of Translate opens when the models are not installed (`README` 8, the
/// designer's `wall/10-translation-download-dark` without its Wi-Fi switch): what the
/// feature does, the download and its progress, Pause or Resume, Keep Reading, and the line
/// that translation starts in this gallery when the download finishes. Every design presents
/// it through `readerDestinationSheets`, at the medium height.
///
/// It has a navigation stack of its own. "Open Settings" pushes Settings › Translation onto
/// it: Settings is the shell's sheet and cannot show over the reader's full-screen cover, and
/// the reader never knows who presented it, so the reader stays open under the sheet. The
/// sheet grows to its full height for the pushed screens.
///
/// The download belongs to the store: closing the sheet or the reader does not stop it. The
/// sheet is the system's, so on iOS 26 it is glass, and nothing on it is (`Design/designs/
/// README.md` section 13).
struct ReaderTranslationDownloadSheet: View {
    let translation: ReaderTranslationModel
    let close: () -> Void

    @State private var router = StackRouter()
    @State private var store = PageTranslationModelStore.forDownloadSheet()
    @State private var detent = PresentationDetent.medium

    var body: some View {
        NavigationStack(path: $router.path) {
            ReaderTranslationDownloadPanel(store: store, translation: translation, close: close)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Route.self) { route in
                    // Only Settings › Translation and the screens it pushes are reached from here.
                    if case .settings(let settingsRoute) = route {
                        SettingsDestination(route: settingsRoute)
                    }
                }
        }
        .environment(router)
        .presentationDetents([.medium, .large], selection: $detent)
        .onChange(of: router.isAtRoot) { _, isAtRoot in
            if !isAtRoot { detent = .large }
        }
        .task {
            #if DEBUG
            await PageTranslationSample.prepare()
            #endif
            // The press read the folder already, unless the sample's store is shown.
            if !store.isLoaded { await store.refresh() }
        }
    }
}

extension PageTranslationModelStore {
    /// The store the download sheet shows: the app's, or in debug builds launched with
    /// `-PageTranslationSample`, the sample's.
    static func forDownloadSheet() -> PageTranslationModelStore {
        #if DEBUG
        if let store = PageTranslationSample.sampleStore { return store }
        #endif
        @Dependency(\.pageTranslationModelStore) var store
        return store
    }
}
