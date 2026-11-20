import CoreGraphics
import CoreText
@testable import EhPageTranslation
import Foundation
import Testing

/// The three subset fonts the target carries.
@Suite(.oneDrawingTestAtATime) struct FontsTests {
    @Test(arguments: FontLibrary.BundledFont.allCases)
    func eachBundledFontLoads(font: FontLibrary.BundledFont) throws {
        let url = try #require(font.url)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let descriptor = try #require(FontLibrary.bundledDescriptor(font))
        let loaded = CTFontCreateWithFontDescriptor(descriptor, 40, nil)
        // The 6,763 characters of GB2312 and more.
        #expect(CTFontGetGlyphCount(loaded) > 7000)
        for character in "你我他的是不了在有这个上们来到时大地为子中说生国年着就那和要她出也得里后自以会家可下而过天去能对小多然于心学么之都好看起发当没成只如事把还用第样道想作种开美总从无情己面最女但现前些所同日手又行意动方期它头经长儿回位分爱老因很给名法间斯知世什两次使身者被高已亲其进此话常与活正感" {
            var units = Array(String(character).utf16), glyphs = [CGGlyph](repeating: 0, count: 1)
            #expect(CTFontGetGlyphsForCharacters(loaded, &units, &glyphs, 1), "\(font) lacks \(character)")
        }
    }

    @Test func theLicencesComeWithTheFonts() throws {
        for name in ["NotoSansSC-OFL", "NotoSerifSC-OFL", "EhShokoKai-OFL"] {
            let url = try #require(Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fonts"))
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.contains("SIL Open Font License") || text.contains("SIL OPEN FONT LICENSE"))
        }
    }

    @Test func theRenamedSubsetCarriesNoReservedName() throws {
        let descriptor = try #require(FontLibrary.bundledDescriptor(.handwritten))
        let font = CTFontCreateWithFontDescriptor(descriptor, 20, nil)
        let names = [CTFontCopyFamilyName(font), CTFontCopyFullName(font), CTFontCopyPostScriptName(font)].map { $0 as String }
        #expect(names == ["EhShoko Kai", "EhShoko Kai", "EhShokoKai-Regular"])
        for name in names {
            for reserved in ["LXGW", "霞鹜", "霞鶩", "落霞孤鹜", "落霞孤鶩"] { #expect(!name.contains(reserved)) }
        }
        // Its copyright notice is kept, as the licence asks.
        let copyright = try #require(CTFontCopyName(font, kCTFontCopyrightNameKey) as String?)
        #expect(copyright.contains("LXGW"))
    }

    @Test(arguments: FontLibrary.BundledFont.allCases)
    func eachBundledFontHasVerticalForms(font: FontLibrary.BundledFont) throws {
        let descriptor = try #require(FontLibrary.bundledDescriptor(font))
        let loaded = CTFontCreateWithFontDescriptor(descriptor, 40, nil)
        let features = (CTFontCopyFeatures(loaded) as? [[CFString: Any]]) ?? []
        #expect(!features.isEmpty)
        // Set vertically, the marks that sit differently in a column take another glyph.
        let typesetter = Typesetter()
        for mark in ["，", "。", "、", "「", "」", "（", "）"] {
            func glyph(isVertical: Bool) -> CGGlyph {
                let line = typesetter.line(mark, loaded, isVertical: isVertical)
                let runs = CTLineGetGlyphRuns(line)
                let run = unsafeBitCast(CFArrayGetValueAtIndex(runs, 0), to: CTRun.self)
                var glyph = CGGlyph(0)
                CTRunGetGlyphs(run, CFRange(location: 0, length: 1), &glyph)
                return glyph
            }
            #expect(glyph(isVertical: true) != glyph(isVertical: false), "\(font) has no vertical form of \(mark)")
        }
    }

    @Test func theLibraryGivesAFaceForEachKindOfLettering() {
        let library = FontLibrary.bundled
        #expect(library.face(.dialogue).name == "NotoSansSC-VF-GB2312")
        #expect(library.face(.bold).name == "NotoSansSC-VF-GB2312")
        #expect(library.face(.serif).name == "NotoSerifSC-VF-GB2312")
        #expect(library.face(.handwritten).name == "EhShokoKai-Regular")
        #expect(library.face(.dialogue).axis == 100...900)
        #expect(library.face(.serif).axis != nil)
        #expect(library.face(.handwritten).axis == nil)
    }

    @Test func aVariableFaceIsBroughtToTheMeasuredWeight() throws {
        let face = FontLibrary.bundled.face(.dialogue)
        // The calibration rises with the axis.
        let weights = face.calibration.map(\.weight)
        #expect(weights.count == 7 && weights == weights.sorted())
        let lightest = try #require(weights.first), heaviest = try #require(weights.last)
        #expect(lightest < 0.05 && heaviest > 0.12)
        // A weight inside the face's range needs no extra stroke, and comes out as asked.
        for target in [0.06, 0.08, 0.11] {
            let match = face.matching(weight: target, size: 100)
            #expect(match.extraStroke == 0)
            #expect(abs(FontFace.strokeRatio(match.font) - target) < 0.012, "\(target)")
        }
        // Beyond the heaviest weight the rest is stroked on.
        let heavy = face.matching(weight: weights[6] + 0.03, size: 40)
        #expect(abs(heavy.extraStroke - 1.2) < 0.01)
        // Below the lightest, the lightest stands.
        #expect(abs(FontFace.strokeRatio(face.matching(weight: 0.001, size: 100).font) - weights[0]) < 0.005)
    }

    @Test func aStaticFaceIsStrokedUpToTheMeasuredWeight() throws {
        let face = FontLibrary.bundled.face(.handwritten)
        let own = try #require(face.calibration.first).weight
        #expect(face.calibration.count == 1 && own > 0.03 && own < 0.12)
        #expect(face.matching(weight: own, size: 30).extraStroke == 0)
        #expect(face.matching(weight: own + 0.005, size: 30).extraStroke == 0)
        #expect(abs(face.matching(weight: own + 0.05, size: 30).extraStroke - 1.5) < 0.01)
        #expect(face.matching(weight: own - 0.03, size: 30).extraStroke == 0)
    }
}
