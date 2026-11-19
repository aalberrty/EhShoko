/// Shelf's first screen and the gallery sheet in each look, for what the plan's walk does not
/// pass through: History from Home, the Front Page's filter pill, pull to refresh, re-selecting
/// a tab, Continue's card, and Sign in over a link's gallery sheet closed with one Close.
/// Run them with the `offline` fixture: signed out, Rate asks to sign in.
///
/// | Walk | What |
/// |---|---|
/// | `home-<look>` | Shelf's preset with that look: the items above on Home and Top. |
/// | `sheet-<look>` | The gallery in the sheet a link opens (`-HarnessPresentation sheet`), Rate, Sign in over it, Done, Close. |
///
/// The set `looks` holds all six.
enum LookWalks {
    static var ids: [String] {
        Style.allCases.map { "home-\($0.rawValue)" } + Style.allCases.map { "sheet-\($0.rawValue)" }
    }

    static func walk(id: String, in environment: WalkEnvironment) -> Walk? {
        let words = id.split(separator: "-").map(String.init)
        guard words.count == 2, let look = Style(rawValue: words[1]) else { return nil }
        var choices = Choices(preset: .shelf)
        choices.look = look
        switch words[0] {
        case "home":
            let launch = environment.baseArguments() + choices.arguments(for: environment.fixture)
            let screens = Screens(choices: choices, environment: environment)
            return Walk(id: id, title: "Shelf's Home in \(look.name)'s look", launch: launch, steps: home(screens))
        case "sheet":
            var launch = environment.baseArguments()
            if let index = launch.firstIndex(of: "-HarnessPart"), launch.indices.contains(index + 1) {
                launch[index + 1] = "gallery"
            }
            launch += ["-HarnessPresentation", "sheet"] + choices.arguments(for: environment.fixture)
            return Walk(id: id, title: "The gallery sheet in \(look.name)'s look", launch: launch, steps: sheet)
        default:
            return nil
        }
    }

    private static let history = Target(matches: [.label("History")], type: .button)
    private static let filters = Target(matches: [.label("Filters")], type: .button)
    /// Shelf's Continue card: the title alone, with the page as its value.
    private static let continueCard = Target(matches: [.label(Screens.galleryTitle)], type: .button)

    private static func home(_ screens: Screens) -> [Step] {
        let launch: [Step] = [.launch(extra: []), screens.waitForFirstScreen, .pause(seconds: 2), .screenshot("home")]
        let history: Step = .group("history", [.tap(Self.history), .pause(seconds: 2), .screenshot("history")])
        let filterPill: [Step] = Screens.openTab("Home") + [
            .pause(seconds: 1), .scrollTo(filters, screens: 3), .tap(filters), .pause(seconds: 1.5),
            .screenshot("filters"), .tap(Screens.close | Screens.done), .pause(seconds: 1),
        ]
        let refresh: [Step] = [
            .scroll(.up, screens: 3, on: nil), .scroll(.up, screens: 0.6, on: nil), .pause(seconds: 0.3),
            .screenshot("refreshing"), .pause(seconds: 2), .screenshot("refreshed"),
        ]
        var reselect: [Step] = Screens.openTab("Top")
        reselect += [.wait(Screens.galleryInList), .scroll(.down, screens: 2, on: nil), .screenshot("top-scrolled")]
        reselect += Screens.openTab("Top") + [.pause(seconds: 1), .screenshot("top-reselected")]
        reselect += Screens.openTab("Top") + [.pause(seconds: 2), .screenshot("top-reselected-again")]
        var continueCard: [Step] = Screens.openTab("Home")
        continueCard += [
            .pause(seconds: 1), .tap(Self.continueCard), .pause(seconds: 0.25), .screenshot("continue-zooming"),
            .pause(seconds: 2.5), .screenshot("continue-reader"),
        ]
        continueCard += Screens.showReaderControls + Screens.closeReader + [.pause(seconds: 1.5), .screenshot("continue-closed")]
        return launch + [
            history,
            .group("filter pill", filterPill),
            .group("pull to refresh", refresh),
            .group("re-select a tab", reselect),
            .group("continue card", continueCard),
        ]
    }

    private static var sheet: [Step] {
        [
            .launch(extra: []), .wait(Screens.readPill), .pause(seconds: 1), .screenshot("gallery-sheet"),
            .tap(Target(matches: [.label("Rate"), .labelPrefix("Rate,")], type: .button)),
            .wait(Target.label("Sign in")), .pause(seconds: 1), .screenshot("sign-in-over-sheet"),
        ] + Screens.closeSettings + [
            // Settings opens with Sign in pushed: back to its root, then Done.
            .pause(seconds: 1.5), .wait(Screens.readPill), .screenshot("back-on-sheet"),
            .tap(Screens.close), .pause(seconds: 1.5), .waitGone(Screens.readPill, timeout: 5), .screenshot("sheet-closed"),
        ]
    }
}
