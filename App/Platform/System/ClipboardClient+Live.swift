import Dependencies
import EhCore
import ImageIO
import UIKit

extension ClipboardClient: @retroactive DependencyKey {
    nonisolated public static let liveValue = ClipboardClient(
        changeCount: { UIPasteboard.general.changeCount },
        url: {
            let pasteboard = UIPasteboard.general
            if pasteboard.hasURLs {
                return pasteboard.url
            }
            return pasteboard.string.flatMap { URL(string: $0) }
        },
        copyText: { text in UIPasteboard.general.string = text },
        copyImage: { data in await copyImageData(data) },
        hasProbableURL: { await hasProbableWebURL() }
    )

    /// Pattern detection reads no contents, so it shows no paste prompt.
    @MainActor
    private static func hasProbableWebURL() async -> Bool {
        let pasteboard = UIPasteboard.general
        if pasteboard.hasURLs { return true }
        guard pasteboard.hasStrings else { return false }
        let patterns = try? await pasteboard.detectedPatterns(for: [\.probableWebURL])
        return patterns?.contains(\.probableWebURL) == true
    }

    /// Puts the original bytes on the pasteboard under their own type so a GIF stays animated
    /// and nothing is re-encoded.
    @concurrent
    nonisolated private static func copyImageData(_ data: Data) async {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String?
        else { return }
        UIPasteboard.general.setData(data, forPasteboardType: type)
    }
}
