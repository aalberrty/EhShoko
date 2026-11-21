import CoreGraphics
@testable import EhPageTranslation
import EhModels
import Foundation
import Testing

@Suite struct PageDrawerTests {
    @Test func storedRegionsComeBackAsTheBlocksTheyWere() throws {
        let page = try PageBitmap.blank(width: 1487, height: 2048)
        var dialogue = TextBlock.stub(.dialogue, x: 1203, y: 311, width: 41, height: 187, inBalloon: true)
        dialogue.source = "こんにちは"
        dialogue.translation = "你好"
        let effect = TextBlock.stub(.soundEffect, x: 97, y: 1500, width: 250, height: 333)
        let text = PageText(imageWidth: page.width, imageHeight: page.height, blocks: [dialogue, effect])

        let stored = text.translation(gid: "1", pageIndex: 3, modelSetKey: "k", createdAt: .now)
        let blocks = PageDrawer.blocks(of: stored, on: page)

        #expect(blocks.count == 2)
        for (block, original) in zip(blocks, [dialogue, effect]) {
            #expect(block.kind == original.kind && block.isVertical == original.isVertical)
            #expect(block.source == original.source && block.translation == original.translation)
            for (a, b) in [(block.box, original.box), (block.balloon?.box ?? .zero, original.balloon?.box ?? .zero)] {
                #expect(abs(a.minX - b.minX) < 1e-6 && abs(a.minY - b.minY) < 1e-6)
                #expect(abs(a.width - b.width) < 1e-6 && abs(a.height - b.height) < 1e-6)
            }
        }
        // A stored page has no mask: drawing finds the balloon's interior from the pixels.
        #expect(blocks[0].balloon?.mask == nil && blocks[1].balloon == nil)
    }

    /// The first drawing, right after the text was made, and a drawing from the row the
    /// database gives back later are the same picture: both start from the stored form.
    @Test(.oneDrawingTestAtATime) func aPageDrawnAgainFromItsStoredTextEqualsItsFirstDrawing() async throws {
        let page = try SyntheticImages.letteredPage(width: 260, height: 300, letterings: [
            SyntheticImages.Lettering(
                columns: ["今日は良い", "天気ですね"], fontSize: 20, centre: CGPoint(x: 130, y: 140),
                balloonSize: CGSize(width: 150, height: 220), translation: "今天天气真好！", hint: .mask
            )
        ])
        let text = PageText(imageWidth: page.bitmap.width, imageHeight: page.bitmap.height, blocks: page.blocks)
        let made = text.translation(gid: "1", pageIndex: 1, modelSetKey: "k", createdAt: Date(timeIntervalSince1970: 0))
        // The row as the database stores it: regions as JSON text.
        let regions = try JSONDecoder().decode([TranslatedRegion].self, from: JSONEncoder().encode(made.regions))
        var read = made
        read.regions = regions

        let first = try await PageDrawer.draw(made, on: page.bitmap)
        let again = try await PageDrawer.draw(read, on: page.bitmap)

        #expect(first.patches.count == 1)
        #expect(first.patches == again.patches)
        #expect(first.failedRepaints == 0 && first.repaintedBlocks == 0)
        // Something was erased and lettered.
        #expect(first.patches.first?.isTransparent == false)
    }

    @Test func theReadersFilesMustBeThoseOfTheSetsReader() async throws {
        let nowhere = URL(fileURLWithPath: "/nowhere")
        let configuration = PipelineConfiguration(
            modelSet: PageTranslationModelSet(reader: .narSmall), detector: nowhere,
            reader: .cpt2(encoder: nowhere, decoder: nowhere, vocabulary: nowhere), translator: nowhere
        )
        // Refused before any file is opened.
        await #expect(throws: PipelineConfigurationError.readerMismatch(expected: .narSmall, files: .cpt2)) {
            try await PagePipeline.load(configuration)
        }
    }
}
