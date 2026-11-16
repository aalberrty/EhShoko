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
    static func tab(_ name: String) -> Target { Target.button(name).in(.tabBar) }
    static let accountButton = Target.button("Account and settings")

    /// A row or cell of the first gallery in a list (its label starts with the title and goes
    /// on with the circle, category and pages), not the Continue card, which is the title alone.
    static let galleryInList = Target(
        matches: [.labelPrefix(galleryTitle + ","), .labelPrefix(galleryTitle + " ·")], type: .button
    )
    /// The dock's pill: "Read", or "Continue" with the page.
    static let readPill = Target(
        matches: [.label("Read"), .labelPrefix("Continue,"), .labelPrefix("Continue ·"), .label("Continue"), .labelPrefix("Read,")],
        type: .button
    )
    static let favourite = Target.id("dock.favorite") | .id("dock.favorite.tip-anchor")
    static let close = Target.button("Close")
    static let searchField = Target(matches: [], type: .searchField)
    static let done = Target.button("Done")

    /// Settings' "Customize" row, which opens Experience.
    static let customise = Target(matches: [.labelPrefix("Customize")])
    /// Experience's row for a part ("Lists", with its choice after it).
    static func partRow(_ part: Part) -> Target { Target(matches: [.label(part.settingsTitle), .labelPrefix(part.settingsTitle + ",")]) }
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
            [.tap(Self.tab("Top")), .wait(Self.galleryInList)]
        case .command:
            choosePlace("Toplists") + [.wait(Self.galleryInList)]
        }
    }

    /// Opens the command bar's place menu and chooses an entry. On Ledger's Index (a phone's
    /// first screen) there is no menu: the Index's own row is the way.
    func choosePlace(_ title: String) -> [Step] {
        [
            .tap(Target(matches: [.label("Home"), .label("Frontpage"), .label("Index"), .label("Toplists"),
                                  .label("Popular"), .label("Watched"), .label("History"), .label("Favorites")],
                        type: .button)),
            .pause(seconds: 1),
            .dump("place-menu"),
            .tap(Target(matches: [.label(title)], type: .button).last),
        ]
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
            .tap(Self.done), .wait(Self.readPill),
        ]
    }

    var comments: [Step] {
        let open: [Step] = switch choices.gallery {
        case .wall: [.tap(Target.button("More")), .pause(seconds: 1), .tap(Target.button("Comments"))]
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
        case .tabs: [.tap(Self.tab("Search"))]
        case .command: [.back, .tap(Target.button("Search").in(.app))]
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
        ]
    }

    // MARK: Library

    var library: [Step] {
        let open: [Step] = switch choices.bar {
        case .tabs: [.tap(Self.tab("Library"))]
        case .command: choosePlace("Favorites")
        }
        if environment.isSignedIn {
            return open + [.pause(seconds: 2), .screenshot("library")]
        }
        return open + [.pause(seconds: 2), .expect(Target(matches: [.labelContains("Sign in")])), .screenshot("library-sign-in")]
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
            .tap(Self.customise), .wait(Self.partRow(change.part)),
            .screenshot("experience"),
            .tap(Self.partRow(change.part)), .pause(seconds: 1.5), .screenshot("options"),
            .tap(Self.optionCard(change.to.name)), .pause(seconds: 1),
            .screenshot("option-chosen"),
            .tap(Self.done), .pause(seconds: 1.5),
        ] + openSecondList + [.screenshot("applied")]
    }
}
