import Foundation
import os
import Testing

@testable import EhCore

struct PerformanceSignpostsTests {
    private let signposter = OSSignposter(subsystem: "app.ehgaro.tests", category: "Performance")

    @Test func intervalEndsOnce() {
        let interval = PerformanceSignposts.begin(.listPage, "frontpage first")
        #expect(!interval.isEnded)
        interval.end("25 galleries")
        #expect(interval.isEnded)
        // A second end and a late event are ignored rather than recorded as a stray end.
        interval.end("failed")
        interval.event("Stored")
        #expect(interval.isEnded)
    }

    @Test func everyNameHasItsStaticName() {
        for name in PerformanceSignposts.Name.allCases {
            #expect("\(name.staticName)" == name.rawValue)
        }
    }

    @Test func launchEndsOnlyAfterItStarted() {
        let launch = LaunchSignposts(signposter: signposter)
        #expect(!launch.rootAppeared())
        #expect(!launch.contentShown("home"))
        launch.start()
        #expect(launch.rootAppeared())
        #expect(!launch.rootAppeared())
    }

    @Test func firstContentEndsOnFirstCallOnly() {
        let launch = LaunchSignposts(signposter: signposter)
        launch.start()
        launch.ready()
        #expect(launch.contentShown("home"))
        #expect(!launch.contentShown("frontpage"))
    }

    @Test func startingAgainDoesNotRestart() {
        let launch = LaunchSignposts(signposter: signposter)
        launch.start()
        #expect(launch.contentShown("home"))
        launch.start()
        // `Launch` is still the first one; `FirstContent` does not begin a second time.
        #expect(!launch.contentShown("home"))
        #expect(launch.rootAppeared())
        launch.start()
        #expect(!launch.rootAppeared())
    }

    @Test func processStartIsInThePast() throws {
        let milliseconds = try #require(ProcessStart.millisecondsSinceStart())
        #expect(milliseconds >= 0)
        #expect(milliseconds < 24 * 60 * 60 * 1_000)
    }
}
