import Foundation
import Testing
@testable import EhCore

/// The transport's rules without a session: what an answer is taken for, what a request
/// carries, where the token may go, and how a range is named across launches.
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

    /// ModelScope answers a range of a small file with status 200, the range's bytes and a
    /// `Content-Range` (seen 2026-11-19). Where the bytes start decides, not the status.
    @Test func aRangeLabelled200IsTakenWhenItSaysWhereItStarts() {
        #expect(judge(200, range: "bytes 1024-2047/48538") == .finished)
        #expect(judge(200, range: "bytes 0-1023/48538") == .refused(status: 200, retryAfter: nil))
        #expect(judge(200, range: "bytes 1024-2047/48538", length: 100) == .refused(status: 200, retryAfter: nil))
        let whole = ModelChunkTicket(path: "ocr-nar-small/Manifest.json.chunk-0", first: 0, count: 617)
        #expect(ModelChunkDelivery.judge(
            status: 200, contentRange: "bytes 0-616/617", retryAfter: nil, length: 617, ticket: whole
        ) == .finished)
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

    /// The token is for the host it was sent to. A redirect anywhere else loses it, also
    /// when whoever follows the redirect would have carried it over.
    @Test(arguments: [
        ("https://cdn.example/signed/weight.bin?sig=1", false),
        ("https://store.example:8443/a/weight.bin", false),
        ("http://store.example/a/weight.bin", false),
        ("https://evil.store.example/a/weight.bin", false),
        ("https://store.example/b/weight.bin", true),
        ("https://STORE.example:443/b/weight.bin", true)
    ])
    func aRedirectCarriesTheTokenOnlyOnTheSameHost(target: String, keeps: Bool) {
        var original = URLRequest(url: URL(string: "https://store.example/a/weight.bin")!)
        original.setValue("Bearer made-up-token", forHTTPHeaderField: "Authorization")
        for carried in [true, false] {
            var proposed = URLRequest(url: URL(string: target)!)
            if carried { proposed.setValue("Bearer made-up-token", forHTTPHeaderField: "Authorization") }
            proposed.setValue("bytes=0-99", forHTTPHeaderField: "Range")

            let followed = ModelChunkDelivery.redirected(proposed, from: original)

            // The system takes the token off every redirect; for the same host it is put back.
            #expect(followed.value(forHTTPHeaderField: "Authorization") == (keeps ? "Bearer made-up-token" : nil))
            #expect(followed.value(forHTTPHeaderField: "Range") == "bytes=0-99")
            #expect(followed.url == proposed.url)
        }
    }

    @Test func aRequestWithoutATokenGetsNoneOnARedirect() {
        let original = URLRequest(url: URL(string: "https://author.example/a/weight.bin")!)
        var proposed = URLRequest(url: URL(string: "https://author.example/b/weight.bin")!)
        proposed.setValue("Bearer from-somewhere", forHTTPHeaderField: "Authorization")

        #expect(ModelChunkDelivery.redirected(proposed, from: original).value(forHTTPHeaderField: "Authorization") == nil)
    }

    /// Hugging Face answers a small file with a 307 to another path of its own host; a
    /// large one with a 302 to a signed address elsewhere.
    @Test func aRedirectToTheSameHostIsToldFromOneThatLeaves() throws {
        let start = URL(string: "https://store.example/models/a/resolve/main/vocab.txt")!
        func response(_ status: Int, _ location: String?) -> HTTPURLResponse {
            HTTPURLResponse(
                url: start, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: location.map { ["Location": $0] } ?? [:]
            )!
        }
        func next(_ status: Int, _ location: String?) -> String? {
            ModelChunkDelivery.sameHostRedirect(in: response(status, location), from: start, startedAt: start)?.absoluteString
        }

        #expect(next(307, "/api/resolve-cache/models/a/abc123/vocab.txt?x=1")
            == "https://store.example/api/resolve-cache/models/a/abc123/vocab.txt?x=1")
        #expect(next(302, "https://store.example/elsewhere/vocab.txt") == "https://store.example/elsewhere/vocab.txt")
        #expect(next(301, "other.txt") == "https://store.example/models/a/resolve/main/other.txt")
        #expect(next(302, "https://cdn.example/signed/abc?sig=1") == nil)
        #expect(next(302, "http://store.example/models/a/vocab.txt") == nil)
        #expect(next(302, nil) == nil)
        #expect(next(206, "/api/resolve-cache/x") == nil)
        #expect(next(404, nil) == nil)
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
