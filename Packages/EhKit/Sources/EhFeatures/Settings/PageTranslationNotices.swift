import EhLlama
import EhPageTranslation
import Foundation

/// A notice that a licence asks to go with every copy of the app: llama.cpp's, and those of
/// the fonts translated pages are lettered in. Names and legal texts are their own English
/// and are not translated.
nonisolated public struct PageTranslationNotice: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var source: URL?
    /// The copyright lines, where the notice keeps them apart from its licence.
    public var copyright: String?
    public var text: String

    public init(name: String, source: URL? = nil, copyright: String? = nil, text: String) {
        self.name = name
        self.source = source
        self.copyright = copyright
        self.text = text
    }

    /// llama.cpp's MIT notice, which needs nothing read.
    public static let llama = PageTranslationNotice(
        name: "\(LlamaLicense.name) \(LlamaLicense.version)", source: URL(string: LlamaLicense.source),
        text: LlamaLicense.notice
    )
}

extension PageTranslationSettingsModel {
    /// Reads the fonts' notices from their files, off the main actor, once. Called from the
    /// Models and licences screen's `task`.
    public func loadNotices() async {
        guard notices.isEmpty else { return }
        notices = [.llama] + (await Self.readFontNotices())
    }

    @concurrent
    nonisolated private static func readFontNotices() async -> [PageTranslationNotice] {
        FontLibrary.bundledNotices().map { font in
            PageTranslationNotice(name: font.name, copyright: font.copyright, text: font.licence)
        }
    }
}
