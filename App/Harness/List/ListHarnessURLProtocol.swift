#if DEBUG
import Foundation
import Kingfisher
import os
import UIKit

/// Stands in for the site's thumbnail server in the list harness: every cover URL is answered
/// with a generated 250 × 354 JPEG (the size of a real list thumbnail) after the latency the
/// URL asks for. Covers go through Kingfisher's real download, disk cache and decode path.
///
/// `@unchecked Sendable`: URL loading hands a protocol instance between its own threads, and
/// the only state added here is the stop flag, which is behind a lock.
nonisolated final class ListHarnessURLProtocol: URLProtocol, @unchecked Sendable {
    static let host = "list-harness.invalid"
    static let coverSize = CGSize(width: 250, height: 354)

    private static let queue = DispatchQueue(
        label: "app.ehshoko.list-harness", qos: .userInitiated, attributes: .concurrent
    )
    /// Covers served since launch, for the run's result.
    static let servedCount = OSAllocatedUnfairLock(initialState: 0)

    private let isStopped = OSAllocatedUnfairLock(initialState: false)

    /// A cover's URL. `session` makes every run's URLs new, so covers are downloaded and
    /// decoded again instead of coming from the disk cache.
    static func coverURL(index: Int, session: String, latency: Double) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/\(session)/\(index)_250.jpg"
        components.queryItems = [URLQueryItem(name: "latency", value: String(format: "%.3f", latency))]
        return components.url
    }

    /// Makes Kingfisher's default downloader, which loads every cover, answer harness URLs.
    /// Safe to call more than once. Kingfisher's downloader is configured on the main thread only.
    @MainActor
    static func install() {
        let downloader = ImageDownloader.default
        guard let configuration = downloader.sessionConfiguration.copy() as? URLSessionConfiguration else { return }
        let installed = configuration.protocolClasses ?? []
        guard !installed.contains(where: { $0 == ListHarnessURLProtocol.self }) else { return }
        configuration.protocolClasses = [ListHarnessURLProtocol.self] + installed
        downloader.sessionConfiguration = configuration
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == host
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let index = Int(url.lastPathComponent.split(separator: "_").first ?? "")
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let latency = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "latency" }?.value.flatMap(Double.init) ?? 0
        Self.queue.asyncAfter(deadline: .now() + latency) {
            guard !self.isStopped.withLock({ $0 }), let client = self.client else { return }
            guard let data = ListHarnessCovers.jpeg(index: index, size: Self.coverSize),
                  let response = HTTPURLResponse(
                    url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "image/jpeg", "Content-Length": String(data.count)]
                  )
            else {
                client.urlProtocol(self, didFailWithError: URLError(.cannotDecodeContentData))
                return
            }
            Self.servedCount.withLock { $0 += 1 }
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: data)
            client.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        isStopped.withLock { $0 = true }
    }
}

/// Draws the harness covers: a gradient, a few shapes and the gallery's number, so each JPEG
/// has the size and decode cost of a real thumbnail (about 15 to 25 KB) and is easy to tell apart.
nonisolated enum ListHarnessCovers {
    static func jpeg(index: Int, size: CGSize) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let hue = CGFloat((index * 47) % 360) / 360
            let top = UIColor(hue: hue, saturation: 0.55, brightness: 0.95, alpha: 1)
            let bottom = UIColor(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.45, alpha: 1)
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1]
            ) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            for shape in 0..<6 {
                let seed = CGFloat((index * 31 + shape * 97) % 100) / 100
                UIColor(white: shape.isMultiple(of: 2) ? 1 : 0, alpha: 0.18).setFill()
                let diameter = 40 + seed * 120
                cg.fillEllipse(in: CGRect(
                    x: seed * size.width - diameter / 2, y: CGFloat(shape) / 6 * size.height, width: diameter, height: diameter
                ))
            }
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 72, weight: .heavy),
                .foregroundColor: UIColor.white.withAlphaComponent(0.9),
                .paragraphStyle: style
            ]
            ("\(index)" as NSString).draw(
                in: CGRect(x: 0, y: size.height / 2 - 48, width: size.width, height: 96), withAttributes: attributes
            )
        }
        return image.jpegData(compressionQuality: 0.85)
    }
}
#endif
