import Foundation

/// What to make of a finished download task: pure, so the rules are tested on the host.
enum ModelChunkDelivery {
    /// The request for one range: the range, the token for this address, and nothing else
    /// about the app or the user.
    static func urlRequest(for request: ModelChunkRequest) -> URLRequest {
        urlRequest(url: request.url, range: request.range, token: request.token)
    }

    static func urlRequest(url: URL, range: Range<Int64>, token: String?) -> URLRequest {
        var urlRequest = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        urlRequest.httpShouldHandleCookies = false
        urlRequest.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")
        // Compressed bytes would not be the range that was asked for.
        urlRequest.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        // The default names the app to every host; the hosts need to know nothing.
        urlRequest.setValue("ModelStore/1", forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return urlRequest
    }

    /// Moves the downloaded file into place when it is the range that was asked for.
    static func deliver(
        _ location: URL, response: URLResponse?, ticket: ModelChunkTicket, root: URL
    ) -> ModelChunkOutcome {
        guard let response = response as? HTTPURLResponse else { return .refused(status: 0, retryAfter: nil) }
        let outcome = judge(
            status: response.statusCode, contentRange: response.value(forHTTPHeaderField: "Content-Range"),
            retryAfter: response.value(forHTTPHeaderField: "Retry-After"), length: ModelFiles.size(of: location),
            ticket: ticket
        )
        guard outcome == .finished else { return outcome }
        do {
            try ModelFiles.move(location, to: ticket.destination(in: root))
            return .finished
        } catch {
            return .refused(status: 0, retryAfter: nil)
        }
    }

    static func judge(
        status: Int, contentRange: String?, retryAfter: String?, length: Int64?, ticket: ModelChunkTicket
    ) -> ModelChunkOutcome {
        let refused = ModelChunkOutcome.refused(status: status, retryAfter: delay(fromRetryAfter: retryAfter))
        guard length == ticket.count else { return refused }
        guard status == 206 || status == 200 else { return refused }
        // Where the bytes start decides, when the answer says it. A range that starts
        // elsewhere is not ours, whatever its length. ModelScope answers a range of a
        // small file with status 200 and a `Content-Range`: that is the range too.
        if let first = firstByte(ofContentRange: contentRange) {
            return first == ticket.first ? .finished : refused
        }
        // An answer that does not say: a 206 is believed. A 200 is the whole file (the
        // source ignored `Range`), which is the range only when the range is the whole file.
        return status == 206 || ticket.first == 0 ? .finished : refused
    }

    /// `bytes 100-199/1000` → 100.
    static func firstByte(ofContentRange value: String?) -> Int64? {
        guard let value, let unitEnd = value.firstIndex(of: " "), let dash = value.firstIndex(of: "-"),
              unitEnd < dash
        else { return nil }
        return Int64(value[value.index(after: unitEnd)..<dash].trimmingCharacters(in: .whitespaces))
    }

    /// `Retry-After` as seconds or as an HTTP date.
    static func delay(fromRetryAfter value: String?, now: Date = Date()) -> Duration? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if let seconds = Double(value) { return .seconds(max(0, seconds)) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: value) else { return nil }
        return .seconds(max(0, date.timeIntervalSince(now)))
    }

    /// The request to follow a redirect with. The token goes along when the redirect stays
    /// on the host the token was meant for (a store may point to another path of itself),
    /// and never to another host. The system has usually dropped it from `request` either
    /// way, so it is taken from the request the task started with.
    static func redirected(_ request: URLRequest, from original: URLRequest?) -> URLRequest {
        var request = request
        let token = original?.value(forHTTPHeaderField: "Authorization")
        request.setValue(isSameOrigin(request.url, original?.url) ? token : nil, forHTTPHeaderField: "Authorization")
        return request
    }

    /// Where `response` redirects to, when that is still the host the request started at.
    /// `nil` for an answer that is not a redirect, and for one that leads elsewhere.
    static func sameHostRedirect(in response: URLResponse, from current: URL, startedAt origin: URL) -> URL? {
        guard let response = response as? HTTPURLResponse, (300..<400).contains(response.statusCode),
              let location = response.value(forHTTPHeaderField: "Location"),
              let next = URL(string: location, relativeTo: current)?.absoluteURL, isSameOrigin(next, origin)
        else { return nil }
        return next
    }

    static func isSameOrigin(_ url: URL?, _ other: URL?) -> Bool {
        guard let url, let other, let host = url.host(), let otherHost = other.host() else { return false }
        return host.lowercased() == otherHost.lowercased() && url.scheme?.lowercased() == other.scheme?.lowercased()
            && port(of: url) == port(of: other)
    }

    private static func port(of url: URL) -> Int {
        url.port ?? (url.scheme?.lowercased() == "http" ? 80 : 443)
    }
}
