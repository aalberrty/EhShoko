import EhModels
import EhNetworking
import EhTestSupport
import Foundation
import Synchronization
import Testing

/// The client tells a bound observer when each request is answered, and nothing otherwise.
struct ResponseArrivalTests {
    @Test func theObserverIsCalledOncePerAnsweredRequest() async throws {
        let harness = ClientHarness()
        harness.transport.on(.any, reply: .fixture(ClientFixture.list("FrontPageCompactList")))
        let arrivals = Mutex(0)

        try await ResponseArrival.$observer.withValue({ arrivals.withLock { $0 += 1 } }) {
            _ = try await harness.client.frontpage(filter: Filter())
            #expect(arrivals.withLock { $0 } == 1)
            _ = try await harness.client.popular(filter: Filter())
        }

        #expect(arrivals.withLock { $0 } == 2)
        #expect(harness.requests.count == 2)
    }

    @Test func aRequestThatFailsIsNotAnArrival() async throws {
        let harness = ClientHarness()
        harness.transport.on(.any, reply: .error(URLError(.timedOut)))
        let arrivals = Mutex(0)

        await #expect(throws: AppError.networkingFailed) {
            try await ResponseArrival.$observer.withValue({ arrivals.withLock { $0 += 1 } }) {
                _ = try await harness.client.frontpage(filter: Filter())
            }
        }

        #expect(arrivals.withLock { $0 } == 0)
    }

    @Test func nothingIsBoundOutsideAnObservedOperation() async throws {
        #expect(ResponseArrival.observer == nil)
        let harness = ClientHarness()
        harness.transport.on(.any, reply: .fixture(ClientFixture.list("FrontPageCompactList")))
        let page = try await harness.client.frontpage(filter: Filter())
        #expect(!page.galleries.isEmpty)
    }
}
