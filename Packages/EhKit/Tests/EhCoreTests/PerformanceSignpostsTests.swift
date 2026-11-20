import EhNetworking
import Foundation
import os
import Testing

@testable import EhCore

struct PerformanceSignpostsTests {
    private let signposter = OSSignposter(subsystem: "app.ehshoko.tests", category: "Performance")

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

    @Test func responsesAreMarkedOnlyDuringTheOperation() async {
        let interval = PerformanceSignposts.begin(.listPage, "frontpage first")
        #expect(ResponseArrival.observer == nil)

        let value = await interval.markingResponses {
            // What `EhClient.send` does when a request is answered.
            #expect(ResponseArrival.observer != nil)
            ResponseArrival.observer?()
            return 25
        }

        #expect(value == 25)
        #expect(ResponseArrival.observer == nil)
        #expect(!interval.isEnded)
        // An answer after the interval ended (a second fetch of the same screen) marks nothing.
        interval.end("25 galleries")
        await interval.markingResponses { ResponseArrival.observer?() }
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
