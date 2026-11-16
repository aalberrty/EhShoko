import Foundation

/// A named list of steps, run as one test (`WalkTests`). Its id is the test's name
/// (`test_<id>`), the prefix of its screenshots and its row in the results table.
struct Walk: Sendable {
    /// Letters, digits and dashes: `preset-shelf`, `swap-wall-list-ledger`, `mix-3`.
    var id: String
    /// What it walks, for the table.
    var title: String
    /// The launch arguments every `launch` step of this walk starts with.
    var launch: [String]
    var steps: [Step]

    init(id: String, title: String, launch: [String], steps: [Step]) {
        self.id = id
        self.title = title
        self.launch = launch
        self.steps = steps
    }
}

/// What the app runs on during a walk, from the runner's environment.
///
/// | Variable (given to `xcodebuild` as `TEST_RUNNER_<name>`) | Meaning |
/// |---|---|
/// | `WALKS` | Which walks: set names (`presets`, `swaps`, `mixes`, `device`, `all`) and walk ids, comma-separated. Default `presets`. |
/// | `WALK_FIXTURE` | `offline` (default): the part harness's whole shell, its seeded database and offline client. `signedIn`: the same with the harness's signed-in fixture, once it exists (`WALK_FIXTURE_ARGS` says which arguments turn it on). `live`: the real app on its own data and the network. |
/// | `WALK_FIXTURE_ARGS` | Launch arguments that turn the signed-in fixture on, space-separated. Default `-HarnessAccount signedIn`. |
/// | `WALK_EXTRA_ARGS` | More launch arguments for every launch, space-separated. |
/// | `WALK_ATTACH` | `YES`: the first launch of a walk activates the app that is already running (started by Instruments) instead of launching it. |
/// | `WALK_PATIENCE` | Seconds to wait for an element (default 20); raise it on a loaded Mac. |
/// | `WALK_HOLD` | Seconds to wait after the walk's first launch before its next step, so that Instruments can attach to the app (`trace_walk.sh`). |
/// | `WALK_DUMPS` | `YES`: every screenshot also attaches the screen's accessibility tree, for writing a walk. |
struct WalkEnvironment: Sendable {
    enum Fixture: String, Sendable {
        case offline, signedIn, live
    }

    var selection: [String]
    var fixture: Fixture
    var fixtureArguments: [String]
    var extraArguments: [String]
    var attachesToRunningApp: Bool
    var patience: Double
    var dumpsTrees: Bool
    var holdAfterFirstLaunch: Double

    static let current = WalkEnvironment(ProcessInfo.processInfo.environment)

    init(_ environment: [String: String]) {
        func words(_ key: String) -> [String] {
            (environment[key] ?? "").split(separator: " ").map(String.init)
        }
        selection = (environment["WALKS"] ?? "presets").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        fixture = environment["WALK_FIXTURE"].flatMap(Fixture.init(rawValue:)) ?? .offline
        let fixtureArguments = words("WALK_FIXTURE_ARGS")
        self.fixtureArguments = fixtureArguments.isEmpty ? ["-HarnessAccount", "signedIn"] : fixtureArguments
        extraArguments = words("WALK_EXTRA_ARGS")
        attachesToRunningApp = environment["WALK_ATTACH"] == "YES"
        patience = environment["WALK_PATIENCE"].flatMap(Double.init) ?? Step.patience
        dumpsTrees = environment["WALK_DUMPS"] == "YES"
        holdAfterFirstLaunch = environment["WALK_HOLD"].flatMap(Double.init) ?? 0
    }

    var isSignedIn: Bool { fixture == .signedIn }

    /// What every launch passes, whatever the walk: English labels, no tips, and the fixture.
    var baseArguments: [String] {
        var arguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-Tips", "hide"]
        switch fixture {
        case .offline:
            arguments += ["-Harness", "part", "-HarnessPart", "shell", "-HarnessPanel", "NO"]
        case .signedIn:
            arguments += ["-Harness", "part", "-HarnessPart", "shell", "-HarnessPanel", "NO"] + fixtureArguments
        case .live:
            break
        }
        return arguments + extraArguments
    }
}
