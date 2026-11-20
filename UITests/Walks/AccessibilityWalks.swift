/// The accessibility pass's audit: under each preset, XCUITest's `performAccessibilityAudit()`
/// (the `audit` step) on the screens of each part, the way the plan's walk reaches them: the
/// first screen, a second list, a gallery page, the reader with its controls, search, the
/// library, Settings and Experience. The audits report and never fail the walk; their
/// attachments (`<walk>__audit-<nn>-<screen>`) list the issues.
///
/// Also, per preset, the gallery page's child screens one by one (`a11y-children-<preset>`:
/// previews, details, a tag's details, archives, torrents), each audited and its tree dumped;
/// and the offer after install at the largest text size (`a11y-offer-large`).
enum AccessibilityWalks {
    static let ids = Style.allCases.map { "a11y-\($0.rawValue)" }
        + Style.allCases.map { "a11y-children-\($0.rawValue)" }
        + ["a11y-offer-large"]

    static func walk(id: String, in environment: WalkEnvironment) -> Walk? {
        if id == "a11y-offer-large" {
            return offerAtLargeText(id: id, environment: environment)
        }
        let isChildren = id.hasPrefix("a11y-children-")
        let prefix = isChildren ? "a11y-children-" : "a11y-"
        guard id.hasPrefix(prefix), let style = Style(rawValue: String(id.dropFirst(prefix.count))) else {
            return nil
        }
        let choices = Choices(preset: style)
        let screens = Screens(choices: choices, environment: environment)
        return Walk(
            id: id, title: isChildren ? "\(style.name) preset, the gallery's child screens audited" : "\(style.name) preset, audited",
            launch: environment.baseArguments() + choices.arguments(for: environment.fixture),
            steps: isChildren ? childSteps(screens, style: style) : steps(screens, choices: choices)
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
                .tapPoint(x: 0.5, y: 0.45), .pause(seconds: 1), .audit("reader-controls"), .dump("reader-controls"),
                .group("open sheet", readerSheetOpened(choices)),
                .tap(Screens.close), .wait(Screens.readPill)
            ),
            .group("search", openSearch + [.wait(Screens.searchField), .pause(seconds: 1), .audit("search")] + screens.closeSearch),
            .group("library", screens.library + [.audit("library")]),
            .group(
                "settings",
                openSettings + [
                    // On an iPad Customize is below the form sheet's fold, made only when near.
                    .wait(Screens.settingsBar), .pause(seconds: 1), .audit("settings"),
                    .scrollTo(Screens.customise, screens: 3), .tap(Screens.customise), .wait(Screens.experienceBar), .pause(seconds: 1), .audit("experience"),
                ] + Screens.closeSettings
            ),
        ]
    }

    /// Ledger's control sheet raised to its open height by its grabber, as VoiceOver does it
    /// (a swipe on the page turns the page), audited and dumped, and lowered again; nothing
    /// for the designs without a sheet.
    private static func readerSheetOpened(_ choices: Choices) -> [Step] {
        guard choices.reader == .ledger else { return [] }
        let grabber = Target(matches: [.label("Sheet Grabber")], type: .button)
        return [
            .tap(grabber), .pause(seconds: 1.5), .audit("reader-sheet-open"), .dump("reader-sheet-open"),
            .tap(grabber), .pause(seconds: 1),
        ]
    }

    // MARK: The gallery's child screens

    /// The gallery page's child screens one by one, each audited and dumped: the previews
    /// (pushed), the gallery's details (pushed), a tag's details, the archives and the torrents
    /// (sheets). The signed-in fixture's fuller page has 48 pages, translated tags of which
    /// 眼镜 (glasses) and 和服 (kimono) have a description, and three torrents.
    private static func childSteps(_ screens: Screens, style: Style) -> [Step] {
        let details = "Gallery details"
        // Wall puts the page's other actions in the dock's menu; Shelf and Ledger in the
        // navigation bar's More menu, which stays at hand wherever the page is scrolled.
        func fromMenu(_ title: String) -> [Step] {
            switch style {
            case .shelf, .ledger: [.tap(Target.button("More").in(.navigationBar)), .pause(seconds: 1), .tap(Target.button(title))]
            case .wall: [.tap(Target.id("dock.menu")), .pause(seconds: 1), .tap(Target.button(title))]
            }
        }
        let torrents = "Torrents · 3"
        let tagDetail: [Step] = switch style {
        case .shelf, .wall:
            [
                .scrollTo(Target.button("眼镜"), screens: 6), .longPress(Target.button("眼镜"), seconds: 1.2),
                .pause(seconds: 1), .tap(Target.button("Tag details")),
            ]
        case .ledger:
            // The menu of the Female line lists the line's tags that have a description.
            [
                .scrollTo(Target.containing("眼镜"), screens: 6), .longPress(Target.containing("眼镜"), seconds: 1.2),
                .pause(seconds: 1), .tap(Target(matches: [.label("眼镜")], type: .button).last),
            ]
        }
        func child(_ name: String, open: [Step], pushed: Bool) -> Step {
            // Shelf's and Wall's sheets at the medium detent have no Close: a tap on the
            // dimmed page above the sheet takes them away.
            let leave: [Step] = pushed
                ? [.back]
                : [.ifPresent(Screens.close, within: 2, then: [.tap(Screens.close)], else: [.tapPoint(x: 0.5, y: 0.2)])]
            return .group(name, open + [
                .pause(seconds: 2), .screenshot(name), .audit(name), .dump(name),
            ] + leave + [.wait(Screens.readPill), .pause(seconds: 1)])
        }
        let start: [Step] = style == .ledger ? screens.openSecondList : []
        return [
            .group("first screen", .launch(extra: []), screens.waitForFirstScreen, .pause(seconds: 2)),
            .group("gallery", start + screens.openGallery + [.pause(seconds: 1)]),
            child("previews", open: [.scrollTo(Target.button("All 48"), screens: 4), .tap(Target.button("All 48"))], pushed: true),
            child("details", open: fromMenu(details), pushed: true),
            child("tag-detail", open: tagDetail, pushed: false),
            child("archives", open: fromMenu("Archive"), pushed: false),
            child("torrents", open: fromMenu(torrents), pushed: false),
        ]
    }

    // MARK: The offer at the largest text size

    /// The offer after install at the largest accessibility text size, on the real app (`live`,
    /// as `device-offer`): the part harness does not run the activation that queues the offer.
    /// The flag is cleared at launch, so no fresh install is needed. Audited, photographed and
    /// left with Not now. Nothing scrolls (a drag at the sheet's top dismisses it) and no tree
    /// is dumped: behind the sheet is the real app's first screen. A failure screenshot can
    /// still show it: look at the screenshots and delete them after a run.
    private static func offerAtLargeText(id: String, environment: WalkEnvironment) -> Walk {
        var live = environment
        live.fixture = .live
        let offerTitle = Target.label("Choose your experience")
        let largest = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        let showsOffer = ["-settings.experienceOfferShown", "<false/>"]
        return Walk(
            id: id, title: "The offer at the largest text size",
            launch: live.baseArguments(showsOffer: true) + showsOffer + largest,
            steps: [
                .launch(extra: []),
                // The sheet's first layout logs UIKit's "Adding 'UIKitToolbar' as a subview"
                // (harmless: SwiftUI places the toolbar itself), which XCTest hands to whichever step is running.
                .optional([.wait(offerTitle, timeout: 60)]),
                .expect(offerTitle), .pause(seconds: 2),
                .screenshot("offer"), .audit("offer"),
                .tap(Target.button("Not now")), .waitGone(offerTitle, timeout: 10),
            ]
        )
    }
}
