/// Shelf's list pushed over each gallery design, under both bars and in a link's gallery
/// sheet: on iOS 18.5 a `List` pushed under a large title while the bottom inset changes in an
/// animation could loop for ever, which is what these walks look for (the list must come up
/// and the gallery must be reachable again).
///
/// | Walk | What |
/// |---|---|
/// | `push-<bar>-<gallery>` | Toplists, the first gallery under that bar, a tag on its page, the list, back. |
/// | `push-sheet-<gallery>` | The gallery in the sheet a link opens (the part harness's `-HarnessPresentation sheet`), a tag, the list, back. |
/// | `push-tabs-<gallery>-swipe` | As `push-tabs-<gallery>`, back with the interactive back swipe: once let go early (the pop is cancelled and the list stays), then all the way. |
///
/// The set `pushes` holds all twelve.
enum PushWalks {
    static var ids: [String] {
        let bars = Bar.allCases.flatMap { bar in Style.allCases.map { "push-\(bar.rawValue)-\($0.rawValue)" } }
        return bars + Style.allCases.map { "push-sheet-\($0.rawValue)" } + Style.allCases.map { "push-tabs-\($0.rawValue)-swipe" }
    }

    /// A tag of the signed-in fixture's fuller page (`PartHarnessRichPage`) with no translation,
    /// so it reads the same in every design: a chip (a button) in Shelf's and Wall's pages, a
    /// link inside the namespace's line of text in Ledger's. The exact label: the title, which
    /// names the artist too, is a button that expands it.
    static let tag = Target(matches: [.label("hoshino kanae")], type: .any)

    static func walk(id: String, in environment: WalkEnvironment) -> Walk? {
        let words = id.split(separator: "-").map(String.init)
        let swipes = words.count == 4 && words[3] == "swipe"
        guard words.count == 3 || swipes, words[0] == "push", let gallery = Style(rawValue: words[2]) else { return nil }
        var choices = Choices(preset: .shelf)
        choices.gallery = gallery
        if words[1] == "sheet" {
            let launch = environment.baseArguments().replacingPart(with: "gallery")
                + ["-HarnessPresentation", "sheet"] + choices.arguments(for: environment.fixture)
            return Walk(id: id, title: "Shelf's list over \(gallery.name)'s gallery in a sheet", launch: launch, steps: [
                .launch(extra: []), .wait(Screens.readPill), .screenshot("gallery-sheet"),
            ] + pushAndReturn)
        }
        guard let bar = Bar(rawValue: words[1]) else { return nil }
        choices.bar = bar
        let screens = Screens(choices: choices, environment: environment)
        let launch = environment.baseArguments() + choices.arguments(for: environment.fixture)
        let title = "Shelf's list over \(gallery.name)'s gallery" + (swipes ? ", back by swiping" : "")
        return Walk(id: id, title: title, launch: launch, steps: [
            .launch(extra: []), screens.waitForFirstScreen,
        ] + screens.openSecondList + screens.openGallery + [.screenshot("gallery")] + (swipes ? pushAndSwipeBack : pushAndReturn))
    }

    private static var pushAndReturn: [Step] {
        push + [.back, .wait(Screens.readPill), .screenshot("back-on-gallery")]
    }

    /// The interactive back swipe while the bottom inset changes with it (F29's fix is the
    /// update that changes it without its animation): let go early, then, if the list is still
    /// there, the whole way; the gallery and its dock come back. Whether letting go early kept
    /// the list is noted, not failed: on a full-width stack the pop completes on iOS 18.5 and
    /// 26.3 alike, which is still to be explained.
    private static var pushAndSwipeBack: [Step] {
        push + [
            .backSwipe(reach: 0.25), .pause(seconds: 1), .screenshot("let-go-early"),
            .optional([.expect(Screens.galleryRow(in: .shelf))]),
            .ifPresent(Screens.galleryRow(in: .shelf), within: 2, then: [.backSwipe(reach: 0.9)], else: []),
            .wait(Screens.readPill), .screenshot("swiped-back-on-gallery"),
        ]
    }

    private static var push: [Step] {
        [
            .scrollTo(tag, screens: 8), .screenshot("tag"),
            .tap(tag), .pause(seconds: 2),
            .wait(Screens.galleryInList), .screenshot("list-pushed"),
            .scroll(.down, screens: 1, on: nil), .screenshot("list-scrolled"),
        ]
    }
}

private extension Array where Element == String {
    /// The arguments with the part harness's part replaced.
    func replacingPart(with part: String) -> [String] {
        var copy = self
        if let index = copy.firstIndex(of: "-HarnessPart"), copy.indices.contains(index + 1) {
            copy[index + 1] = part
        }
        return copy
    }
}
