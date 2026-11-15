#if DEBUG || HARNESS
import EhModels
import SwiftUI

/// The shared pieces of `App/DesignSystem` in one look: tokens, type, category marks, ratings,
/// tag text, covers, the state views and the glass helpers.
///
/// Launched as the whole app with `-Harness look`, and these arguments:
///
/// | Argument | Default | Meaning |
/// |---|---|---|
/// | `-HarnessLook shelf\|wall\|ledger` | `shelf` | The look. |
/// | `-HarnessScheme light\|dark` | the system's | The appearance. |
/// | `-HarnessPage pieces\|states` | `pieces` | The page shown first. |
/// | `-HarnessAccent <hex>` | none | A chosen accent colour in place of the look's own. |
///
/// The glass is where the glass map puts it: the page switch in a top bar, a dock-like group
/// in the bottom bar, nothing glass inside the scrolling page.
struct LookHarnessView: View {
    enum Page: String, CaseIterable, Identifiable {
        case pieces, states
        var id: String { rawValue }
    }

    @State private var look: Look
    @State private var scheme: ColorScheme?
    @State private var page: Page
    @State private var accent: RGBColor

    init() {
        let defaults = UserDefaults.standard
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
        page = defaults.string(forKey: "HarnessPage").flatMap(Page.init(rawValue:)) ?? .pieces
        accent = defaults.string(forKey: "HarnessAccent").flatMap(RGBColor.init(hex:)) ?? .systemBlue
    }

    var body: some View {
        NavigationStack {
            LookHarnessPage(page: page)
                .navigationBarTitleDisplayMode(.inline)
                .screenSubtitle(subtitle, title: "Look harness")
                .toolbar { toolbar }
                .topBar {
                    Picker(selection: $page) {
                        ForEach(Page.allCases) { page in
                            Text(verbatim: page.rawValue.capitalized).tag(page)
                        }
                    } label: {
                        Text(verbatim: "Page")
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Tokens.Spacing.large)
                    .padding(.vertical, Tokens.Spacing.small)
                }
                .bottomBar { LookHarnessDock() }
        }
        .lookEnvironment(look, accent: accent)
        .preferredColorScheme(scheme)
    }

    private var subtitle: String {
        let appearance = switch scheme {
        case .dark: "dark"
        case .light: "light"
        default: "system"
        }
        let tint = accent.isDefaultAccent ? "look's accent" : "chosen accent"
        return "\(String(describing: look)) · \(appearance) · \(tint)"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
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
            } label: {
                Label { Text(verbatim: "Options") } icon: { Image(systemName: "slider.horizontal.3") }
            }
        }
    }
}

/// A dock-like group in the bottom bar: two glass circles and the prominent, tinted pill.
private struct LookHarnessDock: View {
    var body: some View {
        GlassGroup(spacing: Tokens.Spacing.medium) {
            HStack(spacing: Tokens.Spacing.medium) {
                Image(systemName: "heart")
                    .font(.title3)
                    .frame(width: 50, height: 50)
                    .glassSurface(in: .circle, isInteractive: true)
                Button {} label: {
                    Text(verbatim: "Read · page 23")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .glassProminentButtonStyle()
                .buttonBorderShape(.capsule)
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .frame(width: 50, height: 50)
                    .glassSurface(in: .circle, isInteractive: true)
            }
        }
        .padding(.horizontal, Tokens.Spacing.large)
        .padding(.bottom, Tokens.Spacing.small)
    }
}

private struct LookHarnessPage: View {
    let page: LookHarnessView.Page
    @Environment(\.look) private var look

    var body: some View {
        Group {
            switch page {
            case .pieces:
                ScrollView {
                    LookHarnessPieces()
                        .padding(.horizontal, Tokens.Spacing.large)
                        .padding(.vertical, Tokens.Spacing.medium)
                }
            case .states:
                LookHarnessStates()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(look.background)
    }
}

/// The state views, each in a fixed box; not scrolling, since their buttons are glass.
private struct LookHarnessStates: View {
    var body: some View {
        VStack(spacing: 0) {
            ErrorStateView(
                message: L10n.Localizable.ErrorView.Title.network, systemImage: "wifi.exclamationmark", retry: {}
            )
            EmptyStateView()
            NotLoggedInView {}
            LoadingStateView()
                .frame(height: 70)
        }
    }
}
#endif
