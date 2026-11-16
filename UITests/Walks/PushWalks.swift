/// Shelf's list pushed over each gallery design, under both bars and in a link's gallery
/// sheet: on iOS 18.5 a `List` pushed under a large title while the bottom inset changes in an
/// animation could loop for ever, which is what these walks look for (the list must come up
/// and the gallery must be reachable again).
///
/// | Walk | What |
/// |---|---|
/// | `push-<bar>-<gallery>` | Toplists, the first gallery under that bar, a tag on its page, the list, back. |
/// | `push-sheet-<gallery>` | The gallery in the sheet a link opens (the part harness's `-HarnessPresentation sheet`), a tag, the list, back. |
///
/// The set `pushes` holds all nine.
enum PushWalks {
    static var ids: [String] {
        let bars = Bar.allCases.flatMap { bar in Style.allCases.map { "push-\(bar.rawValue)-\($0.rawValue)" } }
        return bars + Style.allCases.map { "push-sheet-\($0.rawValue)" }
    }

    /// A tag of the signed-in fixture's fuller page (`PartHarnessRichPage`) with no translation,
    /// so it reads the same in every design: a chip (a button) in Shelf's and Wall's pages, a
    /// link inside the namespace's line of text in Ledger's. The exact label: the title, which
    /// names the artist too, is a button that expands it.
    static let tag = Target(matches: [.label("hoshino kanae")], type: .any)

    static func walk(id: String, in environment: WalkEnvironment) -> Walk? {
        let words = id.split(separator: "-").map(String.init)
        guard words.count == 3, words[0] == "push", let gallery = Style(rawValue: words[2]) else { return nil }
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
        return Walk(id: id, title: "Shelf's list over \(gallery.name)'s gallery", launch: launch, steps: [
            .launch(extra: []), screens.waitForFirstScreen,
        ] + screens.openSecondList + screens.openGallery + [.screenshot("gallery")] + pushAndReturn)
    }

    private static var pushAndReturn: [Step] {
        [
            .scrollTo(tag, screens: 8), .screenshot("tag"),
            .tap(tag), .pause(seconds: 2),
            .wait(Screens.galleryInList), .screenshot("list-pushed"),
            .scroll(.down, screens: 1, on: nil), .screenshot("list-scrolled"),
            .back, .wait(Screens.readPill), .screenshot("back-on-gallery"),
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
