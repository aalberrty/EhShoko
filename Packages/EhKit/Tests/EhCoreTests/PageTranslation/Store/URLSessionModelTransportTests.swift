import Foundation
import Synchronization
import Testing
@testable import EhCore

/// Answers the transport's requests inside the test process. Each test uses host names
/// of its own, so the tests can run side by side.
class StubURLProtocol: URLProtocol, @unchecked Sendable {
    enum Reply: Sendable {
        case answer(status: Int, headers: [String: String] = [:], body: Data = Data())
        /// A careless redirect: every header is carried over.
        case redirect(URL)
        /// A redirect as the system proposes it: the token is already taken off.
        case redirectWithoutToken(URL)
        case failure(URLError.Code)
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

    /// Whether a redirect is answered as it is (what a session sees when its delegate
    /// refuses to follow) rather than handed to the session to follow.
    class var answersRedirectsItself: Bool { false }

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
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .redirect(let target), .redirectWithoutToken(let target):
            var next = request
            next.url = target
            if case .redirectWithoutToken = reply { next.setValue(nil, forHTTPHeaderField: "Authorization") }
            let response = HTTPURLResponse(
                url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": target.absoluteString]
            )!
            if Self.answersRedirectsItself {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocolDidFinishLoading(self)
            } else {
                client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
            }
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
        answer(host: host) { request in range(of: data, for: request) }
    }

    /// The answer of a store that has `data` to a request for a range of it.
    static func range(of data: Data, for request: URLRequest) -> Reply {
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

/// The same answers for the session that asks where an address leads: a redirect comes
/// back as the answer, as it does when a session's delegate refuses to follow it.
final class QuestionStubURLProtocol: StubURLProtocol, @unchecked Sendable {
    override class var answersRedirectsItself: Bool { true }
}

/// The app's transport class on a session that is not a background one: the same
/// delegate, tickets and judging, with the network replaced.
@Suite struct URLSessionModelTransportTests {
    private let root = StoreSamples.temporaryFolder()
    private let data = StoreSamples.bytes(5000, seed: 77)
    /// Host names of this test alone.
    private let store = "store-\(UUID().uuidString.lowercased()).example"
    private let cdn = "cdn-\(UUID().uuidString.lowercased()).example"

    /// - Parameter resolving: as in the app, where the session does not ask about
    ///   redirects: requests with a token are taken past their own host's redirects first.
    private func makeTransport(resolving: Bool = false) -> URLSessionModelTransport {
        func configuration(_ stub: AnyClass) -> URLSessionConfiguration {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [stub]
            return configuration
        }
        return URLSessionModelTransport(
            configuration: configuration(StubURLProtocol.self), identifier: nil, root: root,
            resolverConfiguration: resolving ? configuration(QuestionStubURLProtocol.self) : nil
        )
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

    /// A store that points to another path of itself still gets the token there: Hugging
    /// Face does this for every small file. The system has dropped it; it is put back.
    @Test func theTokenFollowsARedirectOnTheSameHost() async throws {
        let cached = URL(string: "https://\(store)/api/resolve-cache/a/abc123/weight.bin")!
        StubURLProtocol.answer(host: store) { [data] request in
            guard request.url == cached else { return .redirectWithoutToken(cached) }
            // Like a private repository: nothing without the token.
            guard request.value(forHTTPHeaderField: "Authorization") == "Bearer \(StoreSamples.token)" else {
                return .answer(status: 401)
            }
            return .answer(status: 206, headers: ["Content-Range": "bytes 0-1023/5000"], body: data.prefix(1024))
        }
        let request = request(0..<1024)

        #expect(try await makeTransport().fetch(request) { _ in } == .finished)
        #expect(try Data(contentsOf: request.destination) == data.prefix(1024))
        #expect(StubURLProtocol.seen(host: store).map(\.url) == [request.url, cached])
    }

    /// A background session does not ask before it follows a redirect, so a request with a
    /// token is taken past its own host's redirects first and the session is handed the
    /// address that answers.
    @Test func aBackgroundSessionIsHandedTheAddressThatAnswers() async throws {
        let cached = URL(string: "https://\(store)/api/resolve-cache/a/abc123/weight.bin")!
        StubURLProtocol.answer(host: store) { [data] request in
            guard request.url == cached else { return .redirectWithoutToken(cached) }
            guard request.value(forHTTPHeaderField: "Authorization") == "Bearer \(StoreSamples.token)" else {
                return .answer(status: 401)
            }
            return StubURLProtocol.range(of: data, for: request)
        }
        let transport = makeTransport(resolving: true)
        let first = request(0..<1024)
        let second = request(1024..<2048)

        #expect(try await transport.fetch(first) { _ in } == .finished)
        #expect(try await transport.fetch(second) { _ in } == .finished)

        #expect(try Data(contentsOf: second.destination) == data.subdata(in: 1024..<2048))
        let seen = StubURLProtocol.seen(host: store)
        // One question to the file's address and one to where it points, a byte each; then
        // the two ranges, asked of the address that answers. The question is asked once.
        #expect(seen.map(\.url) == [first.url, cached, cached, cached])
        #expect(seen.map { $0.headers["Range"] } == ["bytes=0-0", "bytes=0-0", "bytes=0-1023", "bytes=1024-2047"])
        #expect(seen.allSatisfy { $0.headers["Authorization"] == "Bearer \(StoreSamples.token)" })
    }

    /// A signed address on another host is not where the token goes: the session is handed
    /// the store's own address and follows from there without it.
    @Test func aBackgroundSessionKeepsTheStoresAddressWhenItPointsElsewhere() async throws {
        let signed = URL(string: "https://\(cdn)/signed/weight.bin?sig=abc")!
        StubURLProtocol.answer(host: store) { _ in .redirect(signed) }
        StubURLProtocol.serve(data, host: cdn)
        let request = request(2048..<3072)

        #expect(try await makeTransport(resolving: true).fetch(request) { _ in } == .finished)

        #expect(try Data(contentsOf: request.destination) == data.subdata(in: 2048..<3072))
        // The question, then the range: both to the store, with the token.
        #expect(StubURLProtocol.seen(host: store).map { $0.headers["Range"] } == ["bytes=0-0", "bytes=2048-3071"])
        #expect(StubURLProtocol.seen(host: store).allSatisfy { $0.url == request.url })
        // The other host sees the range once and never the token.
        let followed = StubURLProtocol.seen(host: cdn)
        #expect(followed.map { $0.headers["Range"] } == ["bytes=2048-3071"])
        #expect(followed.allSatisfy { $0.headers["Authorization"] == nil })
    }

    @Test func aRequestWithoutATokenIsNotAskedAbout() async throws {
        StubURLProtocol.serve(data, host: store)
        let request = request(0..<1024, token: nil)

        #expect(try await makeTransport(resolving: true).fetch(request) { _ in } == .finished)
        #expect(StubURLProtocol.seen(host: store).map { $0.headers["Range"] } == ["bytes=0-1023"])
    }

    @Test func aRangeInPlaceCostsNoQuestion() async throws {
        StubURLProtocol.serve(data, host: store)
        let request = request(0..<1024)
        try FileManager.default.createDirectory(at: request.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.prefix(1024).write(to: request.destination)

        #expect(try await makeTransport(resolving: true).fetch(request) { _ in } == .finished)
        #expect(StubURLProtocol.seen(host: store).isEmpty)
    }

    /// A store that cannot be reached for the question is asked for the range all the same.
    @Test func aQuestionThatFailsDoesNotStopTheRange() async throws {
        let asked = Shared(0)
        StubURLProtocol.answer(host: store) { [data] request in
            if request.value(forHTTPHeaderField: "Range") == "bytes=0-0" {
                asked.update { $0 += 1 }
                return .failure(.networkConnectionLost)
            }
            return StubURLProtocol.range(of: data, for: request)
        }
        let transport = makeTransport(resolving: true)

        #expect(try await transport.fetch(request(1024..<2048)) { _ in } == .finished)
        #expect(try await transport.fetch(request(2048..<3072)) { _ in } == .finished)
        // Not remembered: asked again for the next range.
        #expect(asked.get() == 2)
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
        let deadline = ContinuousClock.now + .seconds(60)
        while StubURLProtocol.seen(host: store).isEmpty {
            try #require(ContinuousClock.now < deadline, "The request never reached the network")
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
