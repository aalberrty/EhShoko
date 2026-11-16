/// The accessibility pass's audit: under each preset, XCUITest's `performAccessibilityAudit()`
/// (the `audit` step) on the screens of each part, the way the plan's walk reaches them: the
/// first screen, a second list, a gallery page, the reader with its controls, search, the
/// library, Settings and Experience. The audits report and never fail the walk; their
/// attachments (`<walk>__audit-<nn>-<screen>`) list the issues.
enum AccessibilityWalks {
    static let ids = Style.allCases.map { "a11y-\($0.rawValue)" }

    static func walk(id: String, in environment: WalkEnvironment) -> Walk? {
        guard id.hasPrefix("a11y-"), let style = Style(rawValue: String(id.dropFirst("a11y-".count))) else {
            return nil
        }
        let choices = Choices(preset: style)
        return Walk(
            id: id, title: "\(style.name) preset, audited",
            launch: environment.baseArguments() + choices.arguments(for: environment.fixture),
            steps: steps(Screens(choices: choices, environment: environment), choices: choices)
        )
    }

    private static func steps(_ screens: Screens, choices: Choices) -> [Step] {
        let openSearch: [Step] = switch choices.bar {
        case .tabs: screens.leaveGallery + Screens.openTab("Search")
        case .command: screens.leaveGallery + [.tap(Target.button("Search").in(.container("Navigation")))]
        }
        let openSettings: [Step] = switch choices.bar {
        case .tabs: [.tap(Screens.accountButton)]
        case .command: screens.choosePlace("Settings")
        }
        return [
            .group("first screen", .launch(extra: []), screens.waitForFirstScreen, .pause(seconds: 2), .audit("first-screen")),
            .group("second list", screens.openSecondList + [.pause(seconds: 1), .audit("second-list")]),
            .group("gallery", screens.openGallery + [.pause(seconds: 1), .audit("gallery")]),
            .group(
                "reader",
                .tap(Screens.readPill), .pause(seconds: 3),
                .tapPoint(x: 0.5, y: 0.45), .pause(seconds: 1), .audit("reader-controls"),
                .tap(Screens.close), .wait(Screens.readPill)
            ),
            .group("search", openSearch + [.wait(Screens.searchField), .pause(seconds: 1), .audit("search")] + screens.closeSearch),
            .group("library", screens.library + [.audit("library")]),
            .group(
                "settings",
                openSettings + [
                    .wait(Screens.customise), .audit("settings"),
                    .tap(Screens.customise), .wait(Screens.experienceBar), .pause(seconds: 1), .audit("experience"),
                ] + Screens.closeSettings
            ),
        ]
    }
}
