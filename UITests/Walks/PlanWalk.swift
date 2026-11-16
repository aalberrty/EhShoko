/// The plan's walk (`PLAN.md`, the paragraph after I5), for one set of design choices:
/// launch; scroll the first screen two screens down and back; open a second list; open a
/// gallery; open the reader, turn three pages, show and hide the controls, close; favourite
/// and unfavourite from the gallery page; open comments and return; search for a tag from
/// suggestions and open a result; open the library and a folder (signed in) or see the
/// sign-in state; open Settings from this bar's entry, change one part on its options
/// screen, close, and see it applied; rotate (iPad).
///
/// What differs between designs (how a list is reached, where Comments is) comes from
/// `Screens`; the order and the screenshots are the same for every walk, so the screenshots
/// of two walks line up.
struct PlanWalk {
    var id: String
    var title: String
    var choices: Choices
    var environment: WalkEnvironment

    var walk: Walk {
        Walk(
            id: id, title: "\(title): \(choices.summary)",
            launch: environment.baseArguments + choices.arguments(for: environment.fixture) + Screens.searchFixtureArguments,
            steps: steps
        )
    }

    private var screens: Screens { Screens(choices: choices, environment: environment) }

    var steps: [Step] {
        let screens = screens
        return [
            .group("launch", .launch(extra: []), screens.waitForFirstScreen, .screenshot("first-screen")),
            .group(
                "scroll the first screen",
                .scroll(.down, screens: 2, on: nil), .screenshot("first-screen-scrolled"),
                .scroll(.up, screens: 2, on: nil)
            ),
            .group("open a second list", screens.openSecondList + [.screenshot("second-list")]),
            .group("open a gallery", screens.openGallery + [.screenshot("gallery")]),
            .group("read", screens.read),
            .group("favourite", screens.favourite),
            .group("comments", screens.comments),
            .group("search", screens.search),
            .group("library", screens.library),
            .group("settings", screens.changePartInSettings),
            .onPad([
                .group(
                    "rotate",
                    .rotate(.landscapeLeft), .screenshot("landscape"), .rotate(.portrait), .screenshot("portrait")
                ),
            ]),
        ]
    }
}
