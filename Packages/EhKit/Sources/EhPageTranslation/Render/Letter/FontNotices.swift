import CoreText
import Foundation

/// What the licence of a font the lettering embeds asks to go with every copy of the app:
/// the font's name, its copyright and the SIL Open Font License, all from its files. The
/// texts are the files' own English and are not translated.
public struct BundledFontNotice: Sendable, Hashable {
    /// The family name the font file gives.
    public let name: String
    /// The copyright lines at the head of the licence file.
    public let copyright: String
    /// The rest of the licence file: the OFL's text.
    public let licence: String
}

extension FontLibrary {
    /// The notices of the bundled fonts, in the order of `BundledFont`. Reads files: call it
    /// off the main actor. A font whose licence file cannot be read is left out.
    public static func bundledNotices() -> [BundledFontNotice] {
        BundledFont.allCases.compactMap(\.notice)
    }
}

extension FontLibrary.BundledFont {
    var licenceURL: URL? {
        Bundle.module.url(forResource: licenceName, withExtension: "txt", subdirectory: "Fonts")
    }

    private var licenceName: String {
        switch self {
        case .dialogue: "NotoSansSC-OFL"
        case .serif: "NotoSerifSC-OFL"
        case .handwritten: "EhShokoKai-OFL"
        }
    }

    var notice: BundledFontNotice? {
        guard let url = licenceURL, let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let (copyright, licence) = Self.split(text)
        return BundledFontNotice(name: familyName ?? rawValue, copyright: copyright, licence: licence)
    }

    /// The family name in the font's name table, read without registering the font.
    private var familyName: String? {
        FontLibrary.bundledDescriptor(self)
            .flatMap { CTFontDescriptorCopyAttribute($0, kCTFontFamilyNameAttribute) as? String }
    }

    /// An OFL file opens with its copyright lines, then a blank line, then the licence.
    static func split(_ text: String) -> (copyright: String, licence: String) {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        let head = lines.drop { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        let copyright = head.prefix { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let licence = head.dropFirst(copyright.count).joined(separator: "\n")
        return (copyright.joined(separator: "\n"), licence.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
