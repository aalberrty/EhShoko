#if DEBUG
import EhCore
import EhModels
import SwiftUI

/// Every design preview in one look, in a sheet, as Settings shows them: the 23 options at
/// 110 × 176 pt, the three preset tiles, and the pictures of a mix; a second page shows one
/// option at each size `settings.md` lists.
///
/// Launched as the whole app with `-Harness previews`, and these arguments:
///
/// | Argument | Default | Meaning |
/// |---|---|---|
/// | `-HarnessLook shelf\|wall\|ledger` | `shelf` | The app's look. |
/// | `-HarnessScheme light\|dark` | the system's | The appearance. |
/// | `-HarnessAccent <hex>` | none | A chosen accent colour in place of the look's own. |
/// | `-HarnessPage options\|sizes` | `options` | The page the sheet opens on. |
/// | `-HarnessOpen YES` | `NO` | Opens the sheet at launch. |
/// | `-HarnessCycle <n>` | `0` | Opens and closes the sheet once, then n times, for an allocations check (`runScripted`). |
/// | `-HarnessExport YES` | `NO` | Writes a contact sheet of every preview in each look, light and dark, to `Library/Caches/PreviewHarness/`. |
///
/// The sheet holds the only previews; closing it releases them, so opening and closing it is
/// what the Settings sheet does to them. The harness has its own settings store, so its
/// accent never touches the app's.
struct PreviewHarnessView: View {
    @State private var store: SettingsStore
    @State private var look: Look
    @State private var scheme: ColorScheme?
    @State private var page: PreviewHarnessPage
    @State private var isPresented: Bool
    @State private var status = ""

    private let cycles: Int
    private let exports: Bool

    init() {
        let defaults = UserDefaults.standard
        let suite = "app.ehgaro.preview-harness"
        UserDefaults().removePersistentDomain(forName: suite)
        let store = SettingsStore(defaults: UserDefaults(suiteName: suite) ?? .standard)
        store.accentColor = defaults.string(forKey: "HarnessAccent").flatMap(RGBColor.init(hex:)) ?? .systemBlue
        _store = State(initialValue: store)
        look = switch defaults.string(forKey: "HarnessLook") {
        case "wall": .wall
        case "ledger": .ledger
        default: .shelf
        }
        scheme = switch defaults.string(forKey: "HarnessScheme") {
        case "dark": .dark
        case "light": .light
        default: nil
        }
        page = defaults.string(forKey: "HarnessPage").flatMap(PreviewHarnessPage.init(rawValue:)) ?? .options
        isPresented = defaults.bool(forKey: "HarnessOpen")
        cycles = defaults.integer(forKey: "HarnessCycle")
        exports = defaults.bool(forKey: "HarnessExport")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        isPresented = true
                    } label: {
                        Text(verbatim: "Open the previews")
                    }
                    Picker(selection: $page) {
                        ForEach(PreviewHarnessPage.allCases) { page in
                            Text(verbatim: page.rawValue.capitalized).tag(page)
                        }
                    } label: {
                        Text(verbatim: "Page")
                    }
                }
                Section {
                    PreviewHarnessOptions(look: $look, scheme: $scheme, accent: accentBinding)
                }
                if !status.isEmpty {
                    Section {
                        Text(verbatim: status).font(.footnote.monospaced())
                    }
                }
            }
            .navigationTitle(Text(verbatim: "Preview harness"))
        }
        .sheet(isPresented: $isPresented) {
            PreviewHarnessSheet(page: $page)
                .lookEnvironment(look, accent: store.accentColor)
                .environment(store)
                .preferredColorScheme(scheme)
        }
        .lookEnvironment(look, accent: store.accentColor)
        .environment(store)
        .preferredColorScheme(scheme)
        .task { await runScripted() }
    }

    private var accentBinding: Binding<RGBColor> {
        Binding { store.accentColor } set: { store.accentColor = $0 }
    }

    /// The scripted runs: the open-and-close cycles, then the export.
    ///
    /// The cycles run in two rounds, one cycle and then n, each followed by a marker file
    /// (`Library/Caches/PreviewHarness/round-<k>`) and a minute's pause, so that the heap can
    /// be read after the first opening (caches warm) and again after n more: what grows
    /// between the two is what an opening leaves behind.
    private func runScripted() async {
        if cycles > 0 {
            try? await Task.sleep(for: .seconds(3))
            for (round, count) in [1, cycles].enumerated() {
                for cycle in 0..<count {
                    status = "Round \(round + 1), cycle \(cycle + 1) of \(count)"
                    isPresented = true
                    try? await Task.sleep(for: .seconds(2))
                    isPresented = false
                    try? await Task.sleep(for: .seconds(2))
                }
                status = "Round \(round + 1) done"
                PreviewHarnessExport.mark("round-\(round + 1)")
                try? await Task.sleep(for: .seconds(60))
            }
        }
        if exports {
            status = PreviewHarnessExport.writeContactSheets(store: store)
        }
    }
}

enum PreviewHarnessPage: String, CaseIterable, Identifiable {
    case options, sizes
    var id: String { rawValue }
}

/// The look, appearance and accent pickers of the harness's first screen.
private struct PreviewHarnessOptions: View {
    @Binding var look: Look
    @Binding var scheme: ColorScheme?
    @Binding var accent: RGBColor

    var body: some View {
        Picker(selection: $look) {
            ForEach(Look.allCases, id: \.self) { look in
                Text(verbatim: String(describing: look).capitalized).tag(look)
            }
        } label: {
            Text(verbatim: "Look")
        }
        Picker(selection: $scheme) {
            Text(verbatim: "System").tag(ColorScheme?.none)
            Text(verbatim: "Light").tag(ColorScheme?.some(.light))
            Text(verbatim: "Dark").tag(ColorScheme?.some(.dark))
        } label: {
            Text(verbatim: "Appearance")
        }
        Picker(selection: $accent) {
            Text(verbatim: "Look's own").tag(RGBColor.systemBlue)
            Text(verbatim: "Orange").tag(RGBColor(hex: "FF9500") ?? .systemBlue)
            Text(verbatim: "Mint").tag(RGBColor(hex: "A8F0D8") ?? .systemBlue)
        } label: {
            Text(verbatim: "Accent")
        }
    }
}
#endif
