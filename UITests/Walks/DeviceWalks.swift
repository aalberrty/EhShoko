/// The steps the plan does once per device, not per walk (`PLAN.md`, after I5): every
/// options screen, the wizard applied and the wizard left, each preset's storyboard and the
/// same four things in the real preset, the offer after a fresh install, and a short gallery
/// read to its closing page in each reading mode.
enum DeviceWalks {
    static let ids = [
        "device-options", "device-wizard-apply", "device-wizard-close", "device-storyboards",
        "device-offer", "device-closing",
    ]

    static func walk(id: String, in environment: WalkEnvironment) -> Walk? {
        let shelf = Choices(preset: .shelf)
        let launch = environment.baseArguments() + shelf.arguments(for: environment.fixture)
        let screens = Screens(choices: shelf, environment: environment)
        switch id {
        case "device-options":
            return Walk(id: id, title: "Every options screen", launch: launch, steps: options(screens))
        case "device-wizard-apply":
            return Walk(id: id, title: "The wizard, applied", launch: launch, steps: wizardApply(screens))
        case "device-wizard-close":
            return Walk(id: id, title: "The wizard, left with Close", launch: launch, steps: wizardClose(screens))
        case "device-storyboards":
            return Walk(id: id, title: "Each preset's storyboard, then the preset", launch: launch, steps: storyboards(environment))
        case "device-offer":
            return offer(id: id, environment: environment)
        case "device-closing":
            return Walk(id: id, title: "A gallery read to its closing page", launch: launch, steps: closing(screens))
        default:
            return nil
        }
    }

    // MARK: Settings

    private static func openExperience(_ screens: Screens) -> [Step] {
        [
            .launch(extra: []), screens.waitForFirstScreen,
            .tap(Screens.accountButton), .wait(Screens.customise), .tap(Screens.customise),
            .wait(Screens.experienceBar),
        ]
    }

    /// Opens all eight options screens; each screenshot is set beside the screen it stands for.
    private static func options(_ screens: Screens) -> [Step] {
        openExperience(screens) + [.screenshot("experience")] + Part.allCases.map { part in
            .group(
                part.rawValue,
                .scrollTo(Screens.partRow(part), screens: 6),
                .tap(Screens.partRow(part)), .pause(seconds: 1.5), .screenshot("options-\(part.rawValue)"),
                .scroll(.down, screens: 1, on: nil), .screenshot("options-\(part.rawValue)-end"),
                .back, .wait(Screens.experienceBar)
            )
        }
    }

    /// The wizard (`Settings › Set up step by step`): nine steps, then the summary.
    private static let setupRow = Target(matches: [.labelPrefix("Set up step by step")])
    private static let next = Target.button("Next")

    private static func openWizard(_ screens: Screens) -> [Step] {
        [
            .launch(extra: []), screens.waitForFirstScreen,
            .tap(Screens.accountButton), .wait(setupRow), .tap(setupRow),
            .wait(next), .screenshot("wizard-start"),
        ]
    }

    /// Runs the wizard to Apply for one mix (the plan's mix 4: tabs, Shelf's first screen,
    /// Ledger's lists, Wall's gallery and reader, Ledger's colours) and sees it applied.
    private static func wizardApply(_ screens: Screens) -> [Step] {
        let mix: [(Part, String)] = [
            (.bar, "Tabs"), (.start, "Shelf"), (.list, "Ledger"), (.gallery, "Wall"), (.reader, "Wall"),
            (.search, "Ledger"), (.library, "Ledger"), (.look, "Ledger"),
        ]
        var steps = openWizard(screens) + [.tap(next)]
        for (part, option) in mix {
            steps.append(.group(
                part.rawValue,
                .tap(Screens.optionCard(option)), .pause(seconds: 0.8), .screenshot("wizard-\(part.rawValue)"), .tap(next)
            ))
        }
        steps += [
            .wait(Target.button("Apply")), .screenshot("wizard-summary"), .tap(Target.button("Apply")),
            .pause(seconds: 2), .tapIfPresent(Screens.done), .pause(seconds: 1.5), .screenshot("wizard-applied"),
            ] + Screens.openTab("Top") + [.wait(Screens.galleryInList), .screenshot("wizard-applied-list"),
        ]
        return steps
    }

    /// Runs the wizard again, changes a step, leaves with Close (discarding), and sees nothing
    /// changed.
    private static func wizardClose(_ screens: Screens) -> [Step] {
        openWizard(screens) + [
            .tap(next), .tap(Screens.optionCard("Menu & search")), .tap(next), .screenshot("wizard-changed"),
            .tap(Target(matches: [.label("Close"), .label("Cancel")], type: .button)),
            .tapIfPresent(Target.button("Discard"), within: 3),
            .pause(seconds: 1.5), .tapIfPresent(Screens.done), .pause(seconds: 1.5),
            .expect(Screens.tab("Home")), .screenshot("wizard-closed"),
        ]
    }

    // MARK: Storyboards

    /// Watches each preset's storyboard on the wizard's first step (four beats about four
    /// seconds apart), then does the same four things in that preset.
    private static func storyboards(_ environment: WalkEnvironment) -> [Step] {
        var steps: [Step] = []
        for style in Style.allCases {
            let choices = Choices(preset: style)
            let screens = Screens(choices: choices, environment: environment)
            let watch: [Step] = [
                .launch(extra: choices.arguments(for: environment.fixture)), screens.waitForFirstScreen,
            ] + openSettings(screens) + [
                .wait(setupRow), .tap(setupRow), .wait(next),
                .tap(Target(matches: [.label(style.name)], type: .button)),
            ] + (1...4).flatMap { beat -> [Step] in
                [.pause(seconds: 4), .screenshot("stage-\(style.rawValue)-\(beat)")]
            }
            steps.append(.group("\(style.rawValue) storyboard", watch))
            steps.append(.group("\(style.rawValue) in the app", fourThings(style, screens: screens, environment: environment)))
        }
        return steps
    }

    private static func openSettings(_ screens: Screens) -> [Step] {
        switch screens.choices.bar {
        case .tabs: [.tap(Screens.accountButton)]
        case .command: screens.choosePlace("Settings")
        }
    }

    /// The four beats of each preset's storyboard (`settings.design.stage.<preset>.1…4`), done
    /// in the app.
    private static func fourThings(_ style: Style, screens: Screens, environment: WalkEnvironment) -> [Step] {
        let choices = Choices(preset: style)
        let relaunch: [Step] = [.launch(extra: choices.arguments(for: environment.fixture)), screens.waitForFirstScreen]
        switch style {
        case .shelf:
            return relaunch + [
                .scroll(.down, screens: 1.5, on: nil), .screenshot("shelf-1-scrolled"),
                ] + Screens.openTab("Top") + [.wait(Screens.galleryInList), .screenshot("shelf-2-tab"),
                .tap(Screens.galleryInList), .wait(Screens.readPill), .screenshot("shelf-3-gallery"),
                .tap(Screens.readPill), .pause(seconds: 3), .tapPoint(x: 0.5, y: 0.45), .pause(seconds: 1),
                .screenshot("shelf-4-reader"), .tap(Screens.close),
            ]
        case .wall:
            return relaunch + [
                .pinch(scale: 1.6, on: nil), .pause(seconds: 1.5), .screenshot("wall-1-pinched"),
                .swipe(.left, on: Screens.commandBar), .pause(seconds: 1.5), .screenshot("wall-2-next-list"),
                .tap(Screens.galleryInList), .wait(Screens.readPill), .screenshot("wall-3-dock"),
                .tap(Screens.readPill), .pause(seconds: 3), .tapPoint(x: 0.5, y: 0.45), .pause(seconds: 1),
                .screenshot("wall-4-reader"), .tap(Screens.close),
            ]
        case .ledger:
            return relaunch + [
                .tap(Target(matches: [.labelPrefix("Frontpage")], type: .button)), .wait(Screens.galleryInList),
                .screenshot("ledger-1-list"),
                .swipe(.left, on: Screens.galleryInList), .pause(seconds: 1), .screenshot("ledger-2-row-actions"),
                .swipe(.right, on: Screens.galleryInList), .pause(seconds: 1),
                .tap(Screens.galleryInList), .wait(Screens.readPill), .screenshot("ledger-3-gallery"),
                .tap(Screens.readPill), .pause(seconds: 3), .tapPoint(x: 0.5, y: 0.45), .pause(seconds: 1),
                .swipe(.up, on: nil), .pause(seconds: 1), .screenshot("ledger-4-sheet"), .tap(Screens.close),
            ]
        }
    }

    // MARK: The offer

    /// After a fresh install (`run_walks.sh --fresh` removes the app first), the offer shows
    /// once, and not on the next launch. Runs on the real app (`live`): the harness keeps no
    /// settings between launches.
    private static func offer(id: String, environment: WalkEnvironment) -> Walk {
        var live = environment
        live.fixture = .live
        let offerTitle = Target.label("Choose your experience")
        return Walk(id: id, title: "The offer after install", launch: live.baseArguments(showsOffer: true), steps: [
            .launch(extra: []), .wait(offerTitle, timeout: 30), .screenshot("offer"),
            .tap(Target.button("Not now")), .waitGone(offerTitle, timeout: 10), .screenshot("offer-dismissed"),
            .terminate, .launch(extra: []), .pause(seconds: 6),
            .group("not again", .waitGone(offerTitle, timeout: 1)), .screenshot("offer-not-again"),
        ])
    }

    // MARK: The closing page

    /// Reads the fixture gallery to its closing page in each reading mode, favourites there,
    /// and uses "Read again" from the gallery page.
    private static func closing(_ screens: Screens) -> [Step] {
        var steps: [Step] = []
        for (index, direction) in ["leftToRight", "rightToLeft", "vertical"].enumerated() {
            steps.append(.group(
                direction,
                .launch(extra: ["-settings.readingDirection", "<integer>\(index)</integer>"]), screens.waitForFirstScreen,
                .tap(Screens.tab("Top")), .wait(Screens.galleryInList),
                .tap(Screens.galleryInList), .wait(Screens.readPill),
                .tap(Screens.readPill), .pause(seconds: 3),
                .tapPoint(x: 0.5, y: 0.45), .wait(Screens.close),
                .tap(Target(matches: [.labelPrefix("Page")], type: .slider)),
                .dump("reader-slider-\(direction)"),
                .screenshot("closing-\(direction)")
            ))
        }
        return steps
    }
}
