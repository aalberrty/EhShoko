@testable import EhPageTranslation
import Foundation
import Testing

/// The notices of the three bundled fonts, which their licence asks to go with the app.
@Suite struct FontNoticesTests {
    @Test func eachFontHasItsNameCopyrightAndLicence() throws {
        let notices = FontLibrary.bundledNotices()
        #expect(notices.map(\.name) == ["Noto Sans SC", "Noto Serif SC", "EhShoko Kai"])
        for notice in notices {
            #expect(notice.copyright.hasPrefix("Copyright"))
            #expect(!notice.copyright.contains("This Font Software"))
            #expect(notice.licence.hasPrefix("This Font Software is licensed under the SIL Open Font License"))
            #expect(notice.licence.contains("SIL OPEN FONT LICENSE Version 1.1"))
        }
        // LXGW WenKai's copyright keeps its reserved names and the font it was derived from.
        let kai = try #require(notices.last)
        #expect(kai.copyright.split(separator: "\n").count == 2)
        #expect(kai.copyright.contains("LXGW"))
        #expect(kai.copyright.contains("The Klee Project Authors"))
    }

    @Test func theCopyrightIsTheLinesBeforeTheFirstBlankLine() {
        let (copyright, licence) = FontLibrary.BundledFont.split("\r\nCopyright A\r\nCopyright B\r\n\r\nThe licence.\n\nMore.\n")
        #expect(copyright == "Copyright A\nCopyright B")
        #expect(licence == "The licence.\n\nMore.")
        #expect(FontLibrary.BundledFont.split("Only a line") == ("Only a line", ""))
    }
}
