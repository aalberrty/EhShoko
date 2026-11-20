#if DEBUG || HARNESS
import EhCore
import EhFeatures
import SwiftUI

extension View {
    /// What every search design adds for the harness: sample quick and recent searches
    /// (`-HarnessSearchWords YES`), and the settings the keystroke probe's `design:` steps
    /// switch the search design through.
    func searchDesignHarness(model: SearchSurfaceModel) -> some View {
        modifier(SearchDesignHarness(model: model))
    }
}

private struct SearchDesignHarness: ViewModifier {
    let model: SearchSurfaceModel

    @Environment(SettingsStore.self) private var settings

    func body(content: Content) -> some View {
        content
            .task { await SearchSampleWords.addIfRequested(hasQuickSearches: !model.root.quickSearchWords.isEmpty) }
            .onAppear { SearchKeystrokeProbe.settings = settings }
    }
}
#endif
