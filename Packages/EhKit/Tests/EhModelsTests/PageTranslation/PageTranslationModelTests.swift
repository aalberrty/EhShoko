import EhModels
import Foundation
import Testing

@Suite struct PageTranslationModelSetTests {
    @Test func theDefaultSetIsTheResearchDefault() {
        let set = PageTranslationModelSet.default
        #expect(set.detector == .k2xl)
        #expect(set.reader == .cpt2)
        #expect(set.translator == .jmtFast1)
        #expect(set.key == "k2xl768.cpt2.jmt1.t1")
        #expect(set.artifacts == [.k2xl, .cpt2, .jmtFast1])
        #expect(RepaintChoice.default == .lamaManga)
    }

    @Test func everyDetectorReaderAndTranslatorGivesItsOwnKey() {
        let sets = TextDetectorChoice.allCases.flatMap { detector in
            TextReaderChoice.allCases.flatMap { reader in
                TranslatorChoice.allCases.map { PageTranslationModelSet(detector: detector, reader: reader, translator: $0) }
            }
        }
        #expect(sets.count == 4 * 2 * 5)
        #expect(Set(sets.map(\.key)).count == sets.count)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "."))
        #expect(sets.allSatisfy { $0.key.unicodeScalars.allSatisfy(allowed.contains) })
        #expect(RepaintChoice.allCases.allSatisfy { $0.key.unicodeScalars.allSatisfy(allowed.contains) })
        #expect(Set(RepaintChoice.allCases.map(\.key)).count == RepaintChoice.allCases.count)
    }

    /// The switch for drawn sound effects is part of a stored page's name, so a page stored
    /// under one rule is never found under the other; off, the name is the one kept before the
    /// switch existed.
    @Test func theSwitchForSoundEffectsJoinsTheKey() {
        let off = PageTranslationModelSet.default
        let on = PageTranslationModelSet(translatesSoundEffects: true)
        #expect(!off.translatesSoundEffects && !off.readsSoundEffects)
        #expect(on.readsSoundEffects)
        #expect(on.key == "k2xl768.cpt2.jmt1.t1.sfx")
        #expect(on.key != off.key && on != off)
        #expect(on.artifacts == off.artifacts)
        for detector in TextDetectorChoice.allCases where detector.labelsSoundEffects {
            let keys = [false, true].map { PageTranslationModelSet(detector: detector, translatesSoundEffects: $0).key }
            #expect(keys[0] != keys[1], "\(detector)")
        }
    }

    /// ogkalu v4-s has no sound-effect class: the switch changes nothing it reads, so it
    /// changes no key and no page is translated again for it.
    @Test func aDetectorWithoutSoundEffectsKeepsItsKeyWithTheSwitchOn() {
        #expect(TextDetectorChoice.allCases.filter { !$0.labelsSoundEffects } == [.v4s])
        let on = PageTranslationModelSet(detector: .v4s, translatesSoundEffects: true)
        #expect(!on.readsSoundEffects)
        #expect(on.key == PageTranslationModelSet(detector: .v4s).key)
    }

    @Test func everyChoiceNamesADistinctArtifact() {
        let artifacts = TextDetectorChoice.allCases.map(\.artifact) + TextReaderChoice.allCases.map(\.artifact)
            + TranslatorChoice.allCases.map(\.artifact) + RepaintChoice.allCases.compactMap(\.artifact)
        #expect(Set(artifacts).count == artifacts.count)
        #expect(artifacts.count == 13)
        #expect(RepaintChoice.off.artifact == nil)
    }

    /// The raw values are the names in the table of measured figures and in preferences.
    @Test func storedNamesNeverChange() {
        #expect(TextDetectorChoice.allCases.map(\.rawValue) == ["k2xl", "yolo26s", "v4s", "rtmdet2"])
        #expect(TextReaderChoice.allCases.map(\.rawValue) == ["cpt2", "narSmall"])
        #expect(TranslatorChoice.allCases.map(\.rawValue) == [
            "jmtFast1", "galTransl4B", "sakura1_5B", "hyMT2", "qwen35_4B"
        ])
        #expect(RepaintChoice.allCases.map(\.rawValue) == ["off", "lamaManga", "bigLama"])
    }
}

@Suite struct ModelArtifactIDTests {
    @Test func catalogNames() {
        #expect(ModelArtifactID.k2xl.rawValue == "det-k2xl-768")
        #expect(ModelArtifactID.narSmall.rawValue == "ocr-nar-small")
        #expect(ModelArtifactID.jmtFast1.rawValue == "mt-jmt-fast-1")
        #expect(ModelArtifactID.sakura1_5B.rawValue == "mt-sakura-1.5b")
        #expect(ModelArtifactID.qwen35_4B.rawValue == "mt-qwen3.5-4b")
        #expect(ModelArtifactID.lamaManga.description == "inp-lama-manga")
    }

    @Test func codesAsAPlainStringAndKeepsUnknownNames() throws {
        let data = try JSONEncoder().encode([ModelArtifactID.v4s, ModelArtifactID("det-future")])
        #expect(String(decoding: data, as: UTF8.self) == #"["det-v4s","det-future"]"#)
        let decoded = try JSONDecoder().decode([ModelArtifactID].self, from: data)
        #expect(decoded == [.v4s, ModelArtifactID(rawValue: "det-future")])
    }

    @Test func roleCoding() throws {
        #expect(ModelRole.allCases.map(\.rawValue) == ["detector", "reader", "translator", "repaint"])
        #expect(try roundTrip(ModelRole.repaint) == .repaint)
    }
}

@Suite struct PageTranslationValueTests {
    private static let region = TranslatedRegion(
        box: FractionalRect(x: 0.1, y: 0.2, width: 0.05, height: 0.3),
        balloonBox: FractionalRect(x: 0.05, y: 0.15, width: 0.15, height: 0.4),
        kind: .dialogue, isVertical: true, score: 0.91, source: "なんで", translation: "为什么"
    )

    @Test func pageRoundTripsThroughJSON() throws {
        let page = PageTranslation(
            gid: "123", pageIndex: 4, modelSetKey: PageTranslationModelSet.default.key,
            imageWidth: 1280, imageHeight: 1808,
            regions: [Self.region, TranslatedRegion(
                box: FractionalRect(x: 0.5, y: 0.5, width: 0.2, height: 0.1),
                kind: .soundEffect, isVertical: false, score: 0.4
            )],
            createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000)
        )
        #expect(try roundTrip(page) == page)
    }

    @Test func regionKindsCodeAsStrings() throws {
        let data = try JSONEncoder().encode(RegionKind.allCases)
        #expect(String(decoding: data, as: UTF8.self) == #"["dialogue","aside","caption","soundEffect"]"#)
    }

    @Test func onlyTranslatedTextCountsAsSomethingToDraw() {
        var page = PageTranslation(
            gid: "1", pageIndex: 1, modelSetKey: "k", imageWidth: 10, imageHeight: 10, regions: [],
            createdAt: Date()
        )
        #expect(!page.hasTranslatedText)
        // A sound effect stored unread, as it is with the switch for sound effects off.
        page.regions = [TranslatedRegion(box: Self.region.box, kind: .soundEffect, isVertical: true, score: 1)]
        #expect(!page.hasTranslatedText)
        page.regions.append(TranslatedRegion(box: Self.region.box, kind: .aside, isVertical: true, score: 1,
                                             source: "…", translation: ""))
        #expect(!page.hasTranslatedText)
        page.regions.append(Self.region)
        #expect(page.hasTranslatedText)
    }

    /// With the switch on a sound effect is read and translated, and then drawn like any text.
    @Test func aTranslatedSoundEffectIsDrawn() {
        let effect = TranslatedRegion(box: Self.region.box, kind: .soundEffect, isVertical: true, score: 1,
                                      source: "効果音", translation: "砰")
        #expect(effect.isTranslated)
        let page = PageTranslation(
            gid: "1", pageIndex: 1, modelSetKey: "k", imageWidth: 10, imageHeight: 10, regions: [effect],
            createdAt: Date()
        )
        #expect(page.hasTranslatedText)
    }

    @Test func fractionalRectFromPixelsIsClippedToTheImage() {
        let rect = FractionalRect(pixelX: -10, y: 50, width: 110, height: 100, imageWidth: 200, imageHeight: 100)
        #expect(rect == FractionalRect(x: 0, y: 0.5, width: 0.5, height: 0.5))
        #expect(rect.maxX == 0.5 && rect.maxY == 1)
        #expect(FractionalRect(pixelX: 300, y: 0, width: 10, height: 10, imageWidth: 200, imageHeight: 100).isEmpty)
        #expect(FractionalRect(pixelX: 0, y: 0, width: 1, height: 1, imageWidth: 0, imageHeight: 0).isEmpty)
    }

    @Test func displayModes() {
        #expect(!PageTranslationDisplay.original.showsTranslation)
        #expect(PageTranslationDisplay.translated.showsTranslation)
        #expect(PageTranslationDisplay.comparing(at: 0.3).showsTranslation)
        #expect(PageTranslationDisplay.comparing(at: -2) == .compare(fraction: 0))
        #expect(PageTranslationDisplay.comparing(at: 7) == .compare(fraction: 1))
        #expect(PageTranslationDisplay.comparing(at: .nan) == .compare(fraction: 0.5))
    }
}
