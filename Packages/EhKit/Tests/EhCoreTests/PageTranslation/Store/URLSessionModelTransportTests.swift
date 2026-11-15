import Foundation
import Synchronization
import Testing
@testable import EhCore

// MARK: The rules, without a session

@Suite struct ModelChunkDeliveryTests {
    private let ticket = ModelChunkTicket(path: "det-v4s/weight.bin.chunk-1", first: 1024, count: 1024)

    private func judge(_ status: Int, range: String? = nil, retryAfter: String? = nil, length: Int64? = 1024) -> ModelChunkOutcome {
        ModelChunkDelivery.judge(status: status, contentRange: range, retryAfter: retryAfter, length: length, ticket: ticket)
    }

    @Test func aRangeOfTheRightLengthIsTaken() {
        #expect(judge(206, range: "bytes 1024-2047/16777216") == .finished)
        // A server that says nothing about where the range starts is believed.
        #expect(judge(206) == .finished)
    }

    @Test func anythingElseIsRefused() {
        #expect(judge(206, range: "bytes 0-1023/16777216") == .refused(status: 206, retryAfter: nil))
        #expect(judge(206, range: "bytes 1024-2047/16777216", length: 1000) == .refused(status: 206, retryAfter: nil))
        #expect(judge(206, length: nil) == .refused(status: 206, retryAfter: nil))
        #expect(judge(403, length: 211) == .refused(status: 403, retryAfter: nil))
        #expect(judge(404) == .refused(status: 404, retryAfter: nil))
        #expect(judge(500) == .refused(status: 500, retryAfter: nil))
        #expect(judge(429, retryAfter: "17", length: 0) == .refused(status: 429, retryAfter: .seconds(17)))
    }

    /// A source that ignores `Range` sends the whole file, which is the range only when
    /// the range is the whole file.
    @Test func aWholeFileIsTheRangeOnlyWhenTheRangeIsTheWholeFile() {
        #expect(judge(200) == .refused(status: 200, retryAfter: nil))
        let whole = ModelChunkTicket(path: "det-v4s/LICENSE.chunk-0", first: 0, count: 400)
        #expect(ModelChunkDelivery.judge(status: 200, contentRange: nil, retryAfter: nil, length: 400, ticket: whole) == .finished)
        #expect(ModelChunkDelivery.judge(status: 200, contentRange: nil, retryAfter: nil, length: 9000, ticket: whole)
            == .refused(status: 200, retryAfter: nil))
    }

    @Test func retryAfterIsSecondsOrADate() {
        #expect(ModelChunkDelivery.delay(fromRetryAfter: "120") == .seconds(120))
        #expect(ModelChunkDelivery.delay(fromRetryAfter: " 2 ") == .seconds(2))
        #expect(ModelChunkDelivery.delay(fromRetryAfter: nil) == nil)
        #expect(ModelChunkDelivery.delay(fromRetryAfter: "soon") == nil)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(ModelChunkDelivery.delay(fromRetryAfter: "Tue, 14 Nov 2023 22:14:20 GMT", now: now) == .seconds(60))
        // A date that has passed means now.
        #expect(ModelChunkDelivery.delay(fromRetryAfter: "Tue, 14 Nov 2023 22:00:00 GMT", now: now) == .seconds(0))
    }

    @Test func theRequestCarriesTheRangeAndNothingAboutTheUser() {
        let request = ModelChunkRequest(
            url: URL(string: "https://store.example/a/1/weight.bin")!, range: 33_554_432..<67_108_864,
            token: "made-up-token", destination: URL(fileURLWithPath: "/tmp/x")
        )

        let urlRequest = ModelChunkDelivery.urlRequest(for: request)

        #expect(urlRequest.value(forHTTPHeaderField: "Range") == "bytes=33554432-67108863")
        #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == "Bearer made-up-token")
        #expect(urlRequest.value(forHTTPHeaderField: "User-Agent") == "ModelStore/1")
        #expect(urlRequest.value(forHTTPHeaderField: "Accept-Encoding") == "identity")
        #expect(urlRequest.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(!urlRequest.httpShouldHandleCookies)
        #expect(urlRequest.cachePolicy == .reloadIgnoringLocalCacheData)

        var withoutToken = request
        withoutToken.token = nil
        #expect(ModelChunkDelivery.urlRequest(for: withoutToken).value(forHTTPHeaderField: "Authorization") == nil)
    }

    /// The token is for the host it was sent to. A redirect anywhere else loses it.
    @Test(arguments: [
        ("https://cdn.example/signed/weight.bin?sig=1", false),
        ("https://store.example:8443/a/weight.bin", false),
        ("http://store.example/a/weight.bin", false),
        ("https://evil.store.example/a/weight.bin", false),
        ("https://store.example/b/weight.bin", true),
        ("https://STORE.example:443/b/weight.bin", true)
    ])
    func aRedirectKeepsTheTokenOnlyOnTheSameHost(target: String, keeps: Bool) {
        let original = URL(string: "https://store.example/a/weight.bin")!
        var proposed = URLRequest(url: URL(string: target)!)
        proposed.setValue("Bearer made-up-token", forHTTPHeaderField: "Authorization")
        proposed.setValue("bytes=0-99", forHTTPHeaderField: "Range")

        let followed = ModelChunkDelivery.redirected(proposed, from: original)

        #expect(followed.value(forHTTPHeaderField: "Authorization") == (keeps ? "Bearer made-up-token" : nil))
        #expect(followed.value(forHTTPHeaderField: "Range") == "bytes=0-99")
        #expect(followed.url == proposed.url)
    }

    // MARK: Tickets

    @Test func aTicketNamesItsRangeRelativeToTheStore() throws {
        let root = URL(fileURLWithPath: "/var/mobile/Containers/Data/Application/ABC/Library/Application Support/PageTranslationModels")
        let request = ModelChunkRequest(
            url: URL(string: "https://store.example/x")!, range: 2048..<3072, token: nil,
            destination: root.appending(path: "mt-jmt-fast-1/coreml/decoder.mlpackage/Data/weights/weight.bin.chunk-2")
        )

        let ticket = try #require(ModelChunkTicket(request, root: root))

        #expect(ticket.description == "v1:2048:1024:mt-jmt-fast-1/coreml/decoder.mlpackage/Data/weights/weight.bin.chunk-2")
        #expect(ModelChunkTicket(description: ticket.description) == ticket)
        // The app's container moves when the app is updated: the ticket follows the new root.
        let moved = URL(fileURLWithPath: "/var/mobile/Containers/Data/Application/XYZ/Library/Application Support/PageTranslationModels")
        #expect(ticket.destination(in: moved).path(percentEncoded: false)
            == moved.path(percentEncoded: false) + "/mt-jmt-fast-1/coreml/decoder.mlpackage/Data/weights/weight.bin.chunk-2")
    }

    @Test func aDestinationOutsideTheStoreHasNoTicket() {
        let root = URL(fileURLWithPath: "/tmp/store")
        func ticket(_ path: String, _ range: Range<Int64> = 0..<10) -> ModelChunkTicket? {
            ModelChunkTicket(
                ModelChunkRequest(url: URL(string: "https://x.example")!, range: range, token: nil, destination: URL(fileURLWithPath: path)),
                root: root
            )
        }
        #expect(ticket("/tmp/store/a/file") != nil)
        #expect(ticket("/tmp/elsewhere/file") == nil)
        #expect(ticket("/tmp/store/../elsewhere/file") == nil)
        #expect(ticket("/tmp/storeroom/file") == nil)
        #expect(ticket("/tmp/store") == nil)
        #expect(ticket("/tmp/store/a/file", 5..<5) == nil)
    }

    @Test(arguments: [
        nil, "", "something else", "v2:0:10:a/b", "v1:x:10:a/b", "v1:0:0:a/b", "v1:-1:10:a/b", "v1:0:10:",
        "v1:0:10:/etc/passwd", "v1:0:10:a/../../b"
    ] as [String?])
    func aDescriptionThatIsNotATicketIsIgnored(description: String?) {
        #expect(ModelChunkTicket(description: description) == nil)
    }

    @Test func aPathMayHoldAColon() {
        let ticket = ModelChunkTicket(path: "a/odd:name.bin.chunk-0", first: 0, count: 5)
        #expect(ModelChunkTicket(description: ticket.description) == ticket)
    }
}

// MARK: The transport over a session

/// Answers the transport's requests inside the test process. Each test uses host names
/// of its own, so the tests can run side by side.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    enum Reply: Sendable {
        case answer(status: Int, headers: [String: String] = [:], body: Data = Data())
        /// A careless redirect: every header is carried over.
        case redirect(URL)
        case never
    }

    struct Seen: Sendable {
        var url: URL
        var headers: [String: String]
    }

    private struct State {
        var replies: [String: @Sendable (URLRequest) -> Reply] = [:]
        var seen: [String: [Seen]] = [:]
    }

    private static let state = Mutex(State())

    static func answer(host: String, _ reply: @escaping @Sendable (URLRequest) -> Reply) {
        state.withLock { $0.replies[host] = reply }
    }

    static func seen(host: String) -> [Seen] {
        state.withLock { $0.seen[host] ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host() else { return }
        let reply = Self.state.withLock { state -> Reply in
            state.seen[host, default: []].append(Seen(url: url, headers: request.allHTTPHeaderFields ?? [:]))
            return state.replies[host]?(request) ?? .answer(status: 404)
        }
        switch reply {
        case .never:
            break
        case .redirect(let target):
            var next = request
            next.url = target
            let response = HTTPURLResponse(
                url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": target.absoluteString]
            )!
            client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
        case .answer(let status, let headers, let body):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    /// Serves `data` with `Range` support, the way a store does.
    static func serve(_ data: Data, host: String) {
        answer(host: host) { request in
            guard let header = request.value(forHTTPHeaderField: "Range"), header.hasPrefix("bytes=") else {
                return .answer(status: 200, body: data)
            }
            let bounds = header.dropFirst(6).split(separator: "-").compactMap { Int($0) }
            guard bounds.count == 2, bounds[0] < data.count else { return .answer(status: 416) }
            let last = min(bounds[1], data.count - 1)
            return .answer(
                status: 206, headers: ["Content-Range": "bytes \(bounds[0])-\(last)/\(data.count)"],
                body: data.subdata(in: bounds[0]..<last + 1)
            )
        }
    }
}

/// The app's transport class on a session that is not a background one: the same
/// delegate, tickets and judging, with the network replaced.
@Suite struct URLSessionModelTransportTests {
    private let root = StoreSamples.temporaryFolder()
    private let data = StoreSamples.bytes(5000, seed: 77)
    /// Host names of this test alone.
    private let store = "store-\(UUID().uuidString.lowercased()).example"
    private let cdn = "cdn-\(UUID().uuidString.lowercased()).example"

    private func makeTransport() -> URLSessionModelTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSessionModelTransport(configuration: configuration, identifier: nil, root: root)
    }

    private func request(_ range: Range<Int64>, host: String? = nil, token: String? = StoreSamples.token) -> ModelChunkRequest {
        ModelChunkRequest(
            url: URL(string: "https://\(host ?? store)/a/1/weight.bin")!, range: range, token: token,
            destination: root.appending(path: "a/weight.bin.chunk-\(range.lowerBound / 1024)")
        )
    }

    @Test func aRangeIsFetchedIntoItsDestination() async throws {
        StubURLProtocol.serve(data, host: store)
        let transport = makeTransport()
        let received = Shared<[Int64]>([])
        let request = request(1024..<2048)

        let outcome = try await transport.fetch(request) { bytes in received.update { $0.append(bytes) } }

        #expect(outcome == .finished)
        #expect(try Data(contentsOf: request.destination) == data.subdata(in: 1024..<2048))
        let seen = StubURLProtocol.seen(host: store)
        #expect(seen.count == 1)
        #expect(seen.first?.headers["Range"] == "bytes=1024-2047")
        #expect(seen.first?.headers["Authorization"] == "Bearer \(StoreSamples.token)")
        #expect(seen.first?.headers["User-Agent"] == "ModelStore/1")
        #expect(seen.first?.headers["Cookie"] == nil)
        #expect(received.get().allSatisfy { $0 <= 1024 })
    }

    @Test func theLastRangeOfAFileIsShorter() async throws {
        StubURLProtocol.serve(data, host: store)
        let request = request(4096..<5000)

        #expect(try await makeTransport().fetch(request) { _ in } == .finished)
        #expect(try Data(contentsOf: request.destination) == data.subdata(in: 4096..<5000))
    }

    /// A store redirects to a signed address on another host. The range goes along; the
    /// token does not, even when whoever follows the redirect would carry it over.
    @Test func theTokenIsNotCarriedToAnotherHost() async throws {
        let target = URL(string: "https://\(cdn)/signed/weight.bin?sig=abc")!
        StubURLProtocol.answer(host: store) { _ in .redirect(target) }
        StubURLProtocol.serve(data, host: cdn)
        let request = request(2048..<3072)

        let outcome = try await makeTransport().fetch(request) { _ in }

        #expect(outcome == .finished)
        #expect(try Data(contentsOf: request.destination) == data.subdata(in: 2048..<3072))
        #expect(StubURLProtocol.seen(host: store).first?.headers["Authorization"] == "Bearer \(StoreSamples.token)")
        let followed = StubURLProtocol.seen(host: cdn)
        #expect(followed.count == 1)
        #expect(followed.first?.headers["Authorization"] == nil)
        #expect(followed.first?.headers["Range"] == "bytes=2048-3071")
        #expect(followed.first?.url == target)
    }

    @Test func anAnswerWithoutTheRangeIsRefused() async throws {
        StubURLProtocol.answer(host: store) { request in
            request.url?.lastPathComponent == "weight.bin"
                ? .answer(status: 429, headers: ["Retry-After": "3"], body: Data("slow down".utf8))
                : .answer(status: 404, body: Data("not here".utf8))
        }
        let transport = makeTransport()
        let limited = request(0..<1024)
        var missing = request(1024..<2048)
        missing.url = URL(string: "https://\(store)/a/1/other.bin")!

        #expect(try await transport.fetch(limited) { _ in } == .refused(status: 429, retryAfter: .seconds(3)))
        #expect(try await transport.fetch(missing) { _ in } == .refused(status: 404, retryAfter: nil))
        // An answer's body never lands where a range belongs.
        #expect(!FileManager.default.fileExists(atPath: limited.destination.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: missing.destination.path(percentEncoded: false)))
    }

    @Test func aSourceThatIgnoresRangeIsRefusedUnlessTheRangeIsTheFile() async throws {
        StubURLProtocol.answer(host: store) { [data] _ in .answer(status: 200, body: data) }
        let transport = makeTransport()

        #expect(try await transport.fetch(request(1024..<2048)) { _ in } == .refused(status: 200, retryAfter: nil))
        let whole = request(0..<5000)
        #expect(try await transport.fetch(whole) { _ in } == .finished)
        #expect(try Data(contentsOf: whole.destination) == data)
    }

    /// A range that arrived while nobody waited for it is there; it is not fetched again.
    @Test func aRangeThatIsAlreadyInPlaceIsNotAskedFor() async throws {
        StubURLProtocol.serve(data, host: store)
        let request = request(0..<1024)
        try FileManager.default.createDirectory(at: request.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.prefix(1024).write(to: request.destination)

        #expect(try await makeTransport().fetch(request) { _ in } == .finished)
        #expect(StubURLProtocol.seen(host: store).isEmpty)
    }

    @Test func cancellingStopsTheTransfer() async throws {
        StubURLProtocol.answer(host: store) { _ in .never }
        let transport = makeTransport()
        let request = request(0..<1024)
        let fetch = Task { try await transport.fetch(request) { _ in } }
        while StubURLProtocol.seen(host: store).isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }

        fetch.cancel()

        await #expect(throws: CancellationError.self) { try await fetch.value }
        #expect(!FileManager.default.fileExists(atPath: request.destination.path(percentEncoded: false)))
    }

    @Test func aRangeMustLandInsideTheStore() async throws {
        var request = request(0..<1024)
        request.destination = URL.temporaryDirectory.appending(path: "elsewhere-\(UUID().uuidString)")

        await #expect(throws: ModelTransportFailure.destinationOutsideStore) {
            try await makeTransport().fetch(request) { _ in }
        }
        #expect(StubURLProtocol.seen(host: store).isEmpty)
    }

    @Test func onlyItsOwnBackgroundSessionIsIts() {
        let transport = URLSessionModelTransport(configuration: .ephemeral, identifier: "the.session", root: root)

        #expect(transport.handleBackgroundEvents(identifier: "the.session") {})
        #expect(!transport.handleBackgroundEvents(identifier: "another.session") {})
        #expect(!makeTransport().handleBackgroundEvents(identifier: "the.session") {})
    }
}
