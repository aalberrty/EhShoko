/// Page translation's screens and controls, audited (`performAccessibilityAudit()`), dumped and
/// photographed in each state, on the part harness's scripted translation
/// (`PartHarnessPageTranslation`: `-HarnessTranslation`, with the sample model store).
///
/// | Walk | What |
/// |---|---|
/// | `translation-shelf`, `-wall`, `-ledger` | That reader's Translate control off with the mark, on, Compare (Wall, Ledger), the open sheet (Ledger), then a failed page, a page in work, models getting ready, models downloading (the download sheet, then the ring) |
/// | `translation-shelf-large`, `-wall-large`, `-ledger-large` | The same reader's states at the largest accessibility text size, photographed |
/// | `translation-settings`, `translation-settings-large` | Settings › Translation, its four selection screens and Models and licences; at the default and the largest text size |
/// | `translation-sheet` | The download sheet with no model source, and Open Settings pushed inside it |
/// | `translation-shelf-two-pages`, `-wall-`, `-ledger-` | On an iPad in landscape with two pages: Translate on, Compare (Wall, Ledger), a failed page |
/// | `translation-wipe-landscape` | Wall's Compare in landscape, the handle swiped to either end: it stops inside the safe area, clear of the sensor housing |
///
/// The walks report and never fail on an audit issue; the attachments list the issues.
enum TranslationWalks {
    static let ids = Style.allCases.map { "translation-\($0.rawValue)" }
        + Style.allCases.map { "translation-\($0.rawValue)-large" }
        + Style.allCases.map { "translation-\($0.rawValue)-two-pages" }
        + ["translation-settings", "translation-settings-large", "translation-sheet", "translation-wipe-landscape"]

    private static let largest = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    static func walk(id: String, in environment: WalkEnvironment) -> Walk? {
        switch id {
        case "translation-settings": return settings(id: id, environment: environment, large: false)
        case "translation-settings-large": return settings(id: id, environment: environment, large: true)
        case "translation-sheet": return sheet(id: id, environment: environment)
        case "translation-wipe-landscape": return wipeInLandscape(id: id, environment: environment)
        default: break
        }
        guard id.hasPrefix("translation-") else { return nil }
        var name = String(id.dropFirst("translation-".count))
        if name.hasSuffix("-two-pages"), let style = Style(rawValue: String(name.dropLast("-two-pages".count))) {
            return twoPages(id: id, style: style, environment: environment)
        }
        let large = name.hasSuffix("-large")
        if large { name = String(name.dropLast("-large".count)) }
        guard let style = Style(rawValue: name) else { return nil }
        return reader(id: id, style: style, environment: environment, large: large)
    }

    // MARK: The reader

    /// The Shelf preset with this reader and look: its tab bar shows Continue, which opens the
    /// harness's Japanese gallery at page 103.
    private static func choices(_ style: Style) -> Choices {
        var choices = Choices(preset: .shelf)
        choices.reader = style
        choices.look = style
        return choices
    }

    private static func launch(_ environment: WalkEnvironment, _ style: Style, large: Bool) -> [String] {
        environment.baseArguments() + choices(style).arguments(for: environment.fixture)
            + ["-settings.pageTranslationSourceAddress", "https://models.example"]
            + (large ? largest : [])
    }

    private static let translate = Target.button("Translate")
    private static let compare = Target.button("Compare")
    private static let continueReading = Target.containing("Continue reading")

    /// Launches with a script and a sample store, opens the reader from Continue and shows its
    /// controls: Shelf's and Wall's open hidden (in the tree, not on screen) and come with a tap
    /// on the page; Ledger's sheet is there at rest at the default text size, and comes with a
    /// tap at the largest.
    private static func open(_ style: Style, script: String, sample: String = "ready") -> [Step] {
        var steps: [Step] = [
            .launch(extra: ["-HarnessTranslation", script, "-PageTranslationSample", sample]),
            .wait(continueReading), .pause(seconds: 1), .tap(continueReading), .pause(seconds: 4),
        ]
        let tapPage: [Step] = [.tapPoint(x: 0.5, y: 0.45), .pause(seconds: 1.5)]
        if style == .ledger {
            steps.append(.ifPresent(grabber, within: 2, then: [], else: tapPage))
        } else {
            steps += tapPage
        }
        return steps
    }

    private static let grabber = Target(matches: [.label("Sheet Grabber")], type: .button)

    private static func look(_ name: String) -> [Step] {
        [.screenshot(name), .audit(name), .dump(name)]
    }

    /// Translate while it is off: a press that did not take (the machine was slow to show the
    /// controls) is made again.
    private static let translateOff = Target(matches: [.valuePrefix("Translation off")], type: .button)

    /// Presses Translate until it is on, or until `done` shows (the download sheet).
    private static func press(until done: Target? = nil) -> [Step] {
        let check = done.map { Step.ifPresent($0, within: 1, then: [], else: [.tap(translate)]) }
            ?? .ifPresent(translateOff, within: 1, then: [.tap(translate)], else: [])
        return [.tap(translate), .pause(seconds: 2), check]
    }

    /// A state reached by one launch: the script, a press of Translate, a pause, a look.
    private static func state(_ name: String, _ style: Style, script: String, wait: Double, see: ([String]) -> [Step]) -> Step {
        var steps: [Step] = open(style, script: script)
        steps += press()
        steps.append(.pause(seconds: wait))
        steps += see([name])
        return .group(name, steps)
    }

    private static func reader(id: String, style: Style, environment: WalkEnvironment, large: Bool) -> Walk {
        let see: ([String]) -> [Step] = { names in
            names.flatMap { name -> [Step] in large ? [.screenshot(name)] : look(name) }
        }
        var first: [Step] = open(style, script: "translates")
        first.append(.wait(translate))
        first += see(["off-mark"])
        var on: [Step] = press()
        on.append(.pause(seconds: 1))
        on += see(["on"])
        var steps: [Step] = [.group("off, with the mark", first), .group("on", on)]
        if style != .shelf {
            var compareSteps: [Step] = [.tap(compare), .pause(seconds: 2)]
            compareSteps += see(["compare"])
            steps.append(.optional(compareSteps))
        }
        if style == .ledger {
            var sheetSteps: [Step] = [.tap(grabber), .pause(seconds: 2)]
            sheetSteps += see(["open-sheet"])
            sheetSteps += [.tap(grabber), .pause(seconds: 1)]
            steps.append(.optional(sheetSteps))
        }
        steps.append(state("failed", style, script: "fails", wait: 3, see: see))
        steps.append(state("working", style, script: "working", wait: 1, see: see))
        steps.append(state("getting-ready", style, script: "preparing", wait: 1, see: see))
        var download: [Step] = open(style, script: "translates", sample: "downloading")
        download += press(until: Target.button("Keep Reading"))
        download.append(.pause(seconds: 1))
        download += see(["download-sheet"])
        if large {
            // The sheet's buttons are below its fold at this size.
            download += [.scroll(.down, screens: 1, on: nil), .pause(seconds: 1.5), .screenshot("download-sheet-scrolled")]
        }
        download += [.tap(Target.button("Keep Reading")), .pause(seconds: 2)]
        download += see(["downloading"])
        steps.append(.group("downloading", download))
        return Walk(
            id: id, title: "Translation in the \(style.name) reader" + (large ? ", largest text" : ""),
            launch: launch(environment, style, large: large), steps: steps
        )
    }

    // MARK: The download sheet with Open Settings

    private static func sheet(id: String, environment: WalkEnvironment) -> Walk {
        let openSettings = Target.button("Open Settings")
        var noSource: [Step] = open(.wall, script: "translates", sample: "noSource")
        noSource += press(until: Target.button("Open Settings"))
        noSource.append(.pause(seconds: 1))
        noSource += look("sheet-no-source")
        var settings: [Step] = [.tap(openSettings), .pause(seconds: 2)]
        settings += look("sheet-settings")
        var findText: [Step] = [.tap(Target.prefix("Find text", .button)), .pause(seconds: 2)]
        findText += look("sheet-find-text")
        return Walk(
            id: id, title: "The download sheet, and Settings pushed inside it",
            launch: launch(environment, .wall, large: false),
            steps: [.group("no source", noSource), .group("open settings", settings), .optional(findText)]
        )
    }

    // MARK: Two pages on an iPad

    private static func twoPages(id: String, style: Style, environment: WalkEnvironment) -> Walk {
        // Each launch turns the device upright, so it turns after the reader opens.
        var on: [Step] = open(style, script: "translates")
        on += [.rotate(.landscapeLeft), .pause(seconds: 1)]
        on += press()
        on.append(.pause(seconds: 1))
        on += look("two-pages-on")
        var steps: [Step] = [.group("on", on)]
        if style != .shelf {
            var compare: [Step] = [.tap(Self.compare), .pause(seconds: 2)]
            compare += look("two-pages-compare")
            steps.append(.optional(compare))
        }
        var failed: [Step] = open(style, script: "fails")
        failed += [.rotate(.landscapeLeft), .pause(seconds: 1)]
        failed += press()
        failed.append(.pause(seconds: 3))
        failed += look("two-pages-failed")
        steps.append(.group("failed", failed))
        steps.append(.rotate(.portrait))
        return Walk(
            id: id, title: "Translation in the \(style.name) reader, two pages on an iPad",
            launch: launch(environment, style, large: false) + [
                "-settings.enablesLandscape", "<true/>", "-settings.enablesDualPageMode", "<true/>",
                "-settings.readingDirection", "<integer>2</integer>",
            ],
            steps: steps
        )
    }

    // MARK: The wipe in landscape

    private static func wipeInLandscape(id: String, environment: WalkEnvironment) -> Walk {
        let handle = Target.label("Compare original and translation")
        var compare: [Step] = open(.wall, script: "translates")
        compare += press()
        compare += [.tap(Self.compare), .pause(seconds: 2)]
        var turn: [Step] = [.turn(.landscapeLeft), .pause(seconds: 2)]
        turn += look("landscape")
        var toLeading: [Step] = [.drag(handle, dx: -600, dy: 0)]
        toLeading += [.pause(seconds: 1), .screenshot("landscape-leading-end"), .dump("landscape-leading-end")]
        var toTrailing: [Step] = [.drag(handle, dx: 1000, dy: 0)]
        toTrailing += [.pause(seconds: 1), .screenshot("landscape-trailing-end"), .dump("landscape-trailing-end")]
        return Walk(
            id: id, title: "Compare in landscape, the handle at either end",
            launch: launch(environment, .wall, large: false) + [
                "-settings.enablesLandscape", "<true/>", "-settings.readingDirection", "<integer>2</integer>",
            ],
            steps: [
                .group("compare", compare), .group("turn", turn),
                .group("leading end", toLeading), .group("trailing end", toTrailing),
                .turn(.portrait),
            ]
        )
    }

    // MARK: Settings

    private static func settings(id: String, environment: WalkEnvironment, large: Bool) -> Walk {
        func see(_ name: String) -> [Step] {
            large ? [.screenshot(name), .audit(name)] : look(name)
        }
        let row = Target(matches: [.labelPrefix("Translation")], type: .button)
        func child(_ title: String, _ name: String) -> Step {
            let target = Target.prefix(title, .button)
            var steps: [Step] = [.scrollTo(target, screens: 4), .tap(target), .pause(seconds: 2)]
            steps += see(name)
            steps += [.scroll(.down, screens: 1, on: nil), .pause(seconds: 1), .screenshot(name + "-scrolled"), .back, .pause(seconds: 1)]
            return .optional(steps)
        }
        var open: [Step] = [
            .launch(extra: ["-PageTranslationSample", "partial"]),
            .wait(Screens.accountButton), .tap(Screens.accountButton), .wait(Screens.settingsBar), .pause(seconds: 1),
            .scrollTo(row, screens: 4), .scroll(.down, screens: 0.5, on: nil), .pause(seconds: 1), .tap(row), .pause(seconds: 2),
        ]
        open += see("translation")
        let bottom: [Step] = [.scroll(.down, screens: 3, on: nil), .pause(seconds: 1), .screenshot("translation-bottom")]
        return Walk(
            id: id, title: "Settings › Translation" + (large ? ", largest text" : ""),
            launch: launch(environment, .shelf, large: large),
            steps: [
                .group("open", open),
                child("Find text", "find-text"),
                child("Read text", "read-text"),
                child("Translate", "translate"),
                child("Repaint artwork", "repaint"),
                .optional(bottom),
                child("Models and licen", "licences"),
            ]
        )
    }
}
