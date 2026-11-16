/// How the plan's walk reaches each screen under one set of design choices: the knowledge of
/// the app's screens that walks share. Labels are the English strings of
/// `App/Resources/en.lproj/Localizable.strings`; the fixture's galleries are the part
/// harness's (`ListHarnessGalleries`, the same list on every run).
struct Screens {
    var choices: Choices
    var environment: WalkEnvironment

    /// The first fixture gallery: first in every fixture list, the one with a stored page
    /// (`PartHarnessDependencies.seed`), read to page 103 of 310.
    static let galleryTitle = "Re: Extra Love Collection Summer Sweet Story Summer Chapter 7 Lesson Holiday"

    /// Tag suggestions in the harness: a dozen sample tags (`SearchSampleSuggestions`).
    static let searchFixtureArguments = [
        "-HarnessSearchSuggestions", "YES",
        "-settings.enablesTagsExtension", "<true/>", "-settings.showsTagsSearchSuggestion", "<true/>",
    ]

    // MARK: Targets

    static let tabBar = Target(matches: [.label("Tab Bar")], type: .tabBar)
    /// The command bar's container (`shell.bar.accessibility`).
    static let commandBar = Target(matches: [.label("Navigation")])
    /// A tab: in the tab bar on a phone; on an iPad the tabs are buttons at the top, with no
    /// tab bar element.
    static func tab(_ name: String) -> Target { Target.button(name).in(.tabBar) }
    static let accountButton = Target.button("Account and settings")

    /// A row or cell of the first gallery in a list. Shelf's row is labelled with the title,
    /// then the circle, category and pages; Ledger's starts with the circle when there is
    /// one; Wall's cell is the title alone. (Shelf's Continue card is the title alone too, but
    /// no walk opens a gallery from Shelf's Home.)
    static let galleryInList = Target(
        matches: [.labelPrefix(galleryTitle + ","), .labelContains(", " + galleryTitle + ","), .label(galleryTitle)],
        type: .button
    )
    /// The first gallery's row as one list design draws it, which tells the designs apart:
    /// Shelf's row reads title then circle, Ledger's circle then title, Wall's cell the title.
    static func galleryRow(in style: Style) -> Target {
        switch style {
        case .shelf: Target(matches: [.labelContains(galleryTitle + ", Hapoi-Dokoro")], type: .button)
        case .wall: Target(matches: [.label(galleryTitle)], type: .button)
        case .ledger: Target(matches: [.labelPrefix("Hapoi-Dokoro · Kimimaru, " + galleryTitle)], type: .button)
        }
    }

    /// The dock's pill: "Read", or "Continue" with the page.
    static let readPill = Target(
        matches: [.identifier("dock.pill"), .label("Read"), .labelPrefix("Continue,"), .labelPrefix("Continue ·"), .label("Continue"), .labelPrefix("Read,")],
        type: .button
    )
    static let favourite = Target.id("dock.favorite") | .id("dock.favorite.tip-anchor")
    /// iOS 26's system close and confirm buttons; on iOS 18 the fallbacks are an "xmark"
    /// and a "checkmark" (`SheetButtons.swift`), found by their symbols.
    static let close = Target(matches: [.label("Close"), .identifier("xmark")], type: .button)
    static let searchField = Target(matches: [.field("Search")])
    static let backButton = Target(matches: [.identifier("BackButton")], type: .button)
    static let done = Target(matches: [.label("Done"), .identifier("checkmark")], type: .button)

    /// Closes the Settings sheet from any of its screens: back to its root (the back buttons
    /// are labelled with the screen they return to), then Done.
    static let closeSettings: [Step] = [
        .tapIfPresent(Target(matches: [.label("Experience")], type: .button), within: 1),
        .pause(seconds: 0.8),
        .tapIfPresent(Target(matches: [.label("Settings")], type: .button), within: 2),
        .pause(seconds: 0.8),
        .tap(done),
    ]
    static let experienceBar = Target(matches: [.identifier("Experience")], type: .navigationBar)

    /// Settings' "Customize" row, which opens Experience.
    static let customise = Target(matches: [.labelPrefix("Customize")])
    /// Experience's row for a part ("Lists", with its choice after it).
    static func partRow(_ part: Part) -> Target { Target(matches: [.labelPrefix(part.settingsTitle + ",")], type: .button) }
    /// An options screen's card: its label is the option's name.
    static func optionCard(_ name: String) -> Target { Target(matches: [.label(name)], type: .button).last }

    // MARK: Waiting for the first screen

    var waitForFirstScreen: Step {
        switch choices.bar {
        case .tabs: .wait(Self.tab("Home"))
        case .command: .wait(Self.commandBar)
        }
    }

    // MARK: Lists

    /// Toplists, the second list, from whichever bar.
    var openSecondList: [Step] {
        switch choices.bar {
        case .tabs:
            Self.openTab("Top") + [.wait(Self.galleryInList)]
        case .command:
            choosePlace("Toplists") + [.wait(Self.galleryInList)]
        }
    }

    /// Opens the command bar's place menu and chooses an entry. On Ledger's Index (a phone's
    /// first screen) there is no menu: the Index's own row is the way.
    func choosePlace(_ title: String) -> [Step] {
        let menu = Target(
            matches: ["Home", "Frontpage", "Index", "Popular", "Watched", "Toplists", "History", "Favorites"].map { .label($0) },
            type: .button
        ).in(.container("Navigation"))
        // Ledger's Index on a phone has no menu: its own rows (and the account button) instead.
        let fromIndex: [Step] = title == "Settings"
            ? [.tap(Self.accountButton)]
            : [.tap(Target(matches: [.label(title), .labelPrefix(title + ",")], type: .button))]
        return [
            .ifPresent(menu, within: 3, then: [
                .tap(menu), .pause(seconds: 1),
                .tap(Target(matches: [.label(title)], type: .button).last),
            ], else: fromIndex),
        ]
    }

    /// A tab, after expanding the tab bar if scrolling collapsed it (iOS 26 on a phone).
    static func openTab(_ name: String) -> [Step] {
        [
            .tapIfPresent(Target(matches: [.value("Collapsed")], type: .button).in(.tabBar), within: 1),
            .pause(seconds: 0.8),
            .tap(tab(name)),
        ]
    }

    /// Back out of a pushed gallery page, which hides the bars; a gallery in the side pane
    /// leaves them, and stays. Wall's page has no system back button: `back` swipes.
    var leaveGallery: [Step] {
        let search = Target(matches: [.label("Search")], type: .button)
            .in(choices.bar == .tabs ? .tabBar : .container("Navigation"))
        return [.ifPresent(search, within: 2, then: [], else: [.back, .pause(seconds: 1)])]
    }

    // MARK: The gallery

    var openGallery: [Step] {
        [.tap(Self.galleryInList), .wait(Self.readPill)]
    }

    var read: [Step] {
        [
            .tap(Self.readPill),
            .pause(seconds: 3),
            .screenshot("reader"),
            .swipe(.left, on: nil), .pause(seconds: 1),
            .swipe(.left, on: nil), .pause(seconds: 1),
            .swipe(.left, on: nil), .pause(seconds: 1),
            .screenshot("reader-page-3"),
            .group("show the controls", .tapPoint(x: 0.5, y: 0.45), .wait(Self.close), .screenshot("reader-controls")),
            .group("hide the controls", .tapPoint(x: 0.5, y: 0.45), .pause(seconds: 1.5), .screenshot("reader-hidden")),
            .group("close", .tapPoint(x: 0.5, y: 0.45), .tap(Self.close), .wait(Self.readPill)),
        ]
    }

    var favourite: [Step] {
        if environment.isSignedIn {
            return [
                .tap(Self.favourite), .pause(seconds: 1.5), .screenshot("favourited"),
                .tap(Self.favourite), .pause(seconds: 1.5), .screenshot("unfavourited"),
            ]
        }
        // Signed out, Favourite opens Settings at Sign in.
        return [
            .tap(Self.favourite), .wait(Target.label("Sign in")), .screenshot("favourite-sign-in"),
        ] + Self.closeSettings + [.wait(Self.readPill)]
    }

    var comments: [Step] {
        let open: [Step] = switch choices.gallery {
        case .wall: [.tap(Target.id("dock.menu")), .pause(seconds: 1), .tap(Target.button("Comments"))]
        case .shelf, .ledger: [.tap(Target.button("Comments"))]
        }
        return open + [
            .wait(Target(matches: [.identifier("Comments"), .label("Comments")], type: .navigationBar)),
            .screenshot("comments"), .back, .wait(Self.readPill),
        ]
    }

    // MARK: Search

    var search: [Step] {
        let open: [Step] = switch choices.bar {
        case .tabs: leaveGallery + Self.openTab("Search")
        case .command: leaveGallery + [.tap(Target.button("Search").in(.container("Navigation")))]
        }
        return open + [
            .wait(Self.searchField),
            .screenshot("search"),
            .type("glass", into: Self.searchField),
            .pause(seconds: 1.5),
            .screenshot("search-suggestions"),
            .tap(Target(matches: [.labelContains("glasses")], type: .any)),
            .type("\n", into: nil),
            .wait(Self.galleryInList),
            .screenshot("search-results"),
            .tap(Self.galleryInList), .wait(Self.readPill), .screenshot("search-gallery"),
        ] + closeSearch
    }

    /// Back from the result's gallery and out of the search surface, which under `command` is
    /// an overlay with its own Cancel or Close.
    var closeSearch: [Step] {
        var steps: [Step] = [.ifPresent(Self.readPill, within: 1, then: [.back], else: []), .pause(seconds: 1)]
        if choices.bar == .command {
            steps += [.tapIfPresent(Target(matches: [.label("Cancel"), .label("Close")], type: .button), within: 2), .pause(seconds: 1)]
        }
        return steps
    }

    // MARK: Library

    var library: [Step] {
        let open: [Step] = switch choices.bar {
        case .tabs: Self.openTab("Library")
        case .command: choosePlace("Favorites")
        }
        if environment.isSignedIn {
            // The fixture's first named folder (`PartHarnessAccount`).
            return open + [
                .pause(seconds: 2), .screenshot("library"),
                .optional([.tap(Target(matches: [.labelPrefix("To Read")])), .pause(seconds: 2), .screenshot("library-folder")]),
            ]
        }
        // Signed out the library says so, unless the harness shows its fixture rows there.
        return open + [
            .pause(seconds: 2), .expect(Target(matches: [.labelContains("Sign in")]) | Self.galleryInList),
            .screenshot("library"),
        ]
    }

    // MARK: Settings

    /// The part the walk changes in Settings, and to what: Lists, to the next design.
    var settingsChange: (part: Part, to: Style) {
        let index = Style.allCases.firstIndex(of: choices.list) ?? 0
        return (.list, Style.allCases[(index + 1) % Style.allCases.count])
    }

    var changePartInSettings: [Step] {
        let open: [Step] = switch choices.bar {
        case .tabs: [.tap(Self.accountButton)]
        case .command: choosePlace("Settings")
        }
        let change = settingsChange
        return open + [
            .wait(Self.customise), .screenshot("settings"),
            .tap(Self.customise), .wait(Self.experienceBar),
            .scrollTo(Self.partRow(change.part), screens: 6),
            .screenshot("experience"),
            .tap(Self.partRow(change.part)), .pause(seconds: 1.5), .screenshot("options"),
            .tap(Self.optionCard(change.to.name)), .pause(seconds: 1),
            .screenshot("option-chosen"),
        ] + Self.closeSettings + [
            .pause(seconds: 1.5),
        ] + openSecondList + [.expect(Self.galleryRow(in: change.to)), .screenshot("applied")]
    }
}
