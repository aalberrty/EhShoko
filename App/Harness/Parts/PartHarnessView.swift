#if DEBUG || HARNESS
import Dependencies
import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// The part harness (`Design/designs/README.md` section 11.3): one part, in the design under
/// test, inside each variant of its surroundings that the contract distinguishes, so that a
/// part proves it meets the contract without running every combination of designs.
///
/// It is the real shell around the part: the same stack, bottom chrome host, side pane, bars
/// and presentations, on routers and settings of its own, so nothing the user chose changes.
/// Lists are fixtures in whichever state is asked for. Launched as the whole app
/// (`-Harness part`) it also has a database of its own, seeded, and an account of its own
/// (`PartHarnessAccount`: a cookie jar, a user store and a client that records every request
/// and answers on the device), so a gallery page shows a stored page and nothing leaves the
/// device; opened from Laboratory it uses the app's own database and client for everything
/// but lists.
struct PartHarnessView: View {
    @State private var model: PartHarnessModel
    @State private var showsPanel = false
    @Namespace private var zoom
    @Environment(\.dismiss) private var dismiss
    private let isClosable: Bool

    @Dependency(\.filterStore) private var filterStore
    @Dependency(\.userStore) private var userStore
    @Dependency(\.tagTranslationService) private var tagTranslationService
    @Dependency(\.accountSession) private var accountSession

    init(options: PartHarnessOptions = .atLaunch, isClosable: Bool = false) {
        _model = State(initialValue: PartHarnessModel(options: options))
        self.isClosable = isClosable
    }

    var body: some View {
        let options = model.options
        ZStack {
            Look(options.choices.look).surface.ignoresSafeArea()
            if model.isReady {
                PartHarnessStage(model: model)
                    .frame(maxWidth: options.width > 0 ? CGFloat(options.width) : .infinity)
                    .modifier(PartHarnessWidthClass(width: options.width))
                    // Another part, bar or presentation is another stage, built from scratch.
                    .id(model.stageID)
            } else {
                ProgressView()
            }
        }
        // At the top centre, clear of the top bar's buttons at both ends.
        .overlay(alignment: .top) {
            if options.showsPanelButton {
                Button { showsPanel = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.footnote)
                        .padding(8)
                        .glassSurface(in: .circle, isInteractive: true)
                }
                .accessibilityLabel(Text(verbatim: "Harness options"))
            }
        }
        .sheet(isPresented: $showsPanel) {
            PartHarnessPanel(model: model, close: isClosable ? { dismiss() } : nil)
                .presentationDetents([.medium, .large])
        }
        .lookEnvironment(Look(options.choices.look), accent: model.settings.accentColor)
        .preferredColorScheme(options.scheme == .system ? nil : (options.scheme == .dark ? .dark : .light))
        .dynamicTypeSize(options.usesLargestText ? DynamicTypeSize.accessibility5...DynamicTypeSize.accessibility5 : DynamicTypeSize.xSmall...DynamicTypeSize.accessibility5)
        .environment(\.zoomNamespace, zoom)
        // `-HarnessNetwork`: every list loads through the harness's client instead.
        .environment(\.listFixtures, PartHarnessDependencies.loadsLists ? nil : model.fixtures)
        .environment(model.settings)
        .environment(model.app.router)
        .environment(model.continueModel)
        .environment(filterStore)
        .environment(userStore)
        .environment(tagTranslationService)
        .environment(accountSession)
        .task { await model.prepare() }
        .task { await model.continueModel.observe() }
        .task { await model.runMemoryCheck() }
        // As the shell does once its first screen is up, so the Favourite tip can show here.
        .task { await TipsConfiguration.configure() }
        .task {
            guard PartHarnessDependencies.isInstalled else { return }
            await PartHarnessAccount.atLaunch.signInLater()
        }
        .task {
            guard PartHarnessDependencies.isInstalled else { return }
            await PartHarnessDecodeLog.run()
        }
    }
}

/// The contract's size class follows the container, which the harness narrows.
private struct PartHarnessWidthClass: ViewModifier {
    let width: Int

    func body(content: Content) -> some View {
        if width > 0 {
            content.environment(\.horizontalSizeClass, width >= 700 ? .regular : .compact)
        } else {
            content
        }
    }
}

/// The harness's row in Laboratory.
struct PartHarnessLauncher: View {
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: { Text(verbatim: "Part harness") }
            .fullScreenCover(isPresented: $isPresented) {
                PartHarnessView(options: .default, isClosable: true)
            }
    }
}
#endif
