import CoreGraphics
@testable import EhPageTranslation
import EhModels
import Foundation
import ImageIO
import Testing

/// Drawing a page: patches out.
@Suite struct PageRendererTests {
    typealias Lettering = SyntheticImages.Lettering

    static let letterings: [Lettering] = [
        Lettering(columns: ["今日は良い天気", "ですね散歩に", "行きましょう"], fontSize: 28, centre: CGPoint(x: 170, y: 220),
                  balloonSize: CGSize(width: 220, height: 330), translation: "今天天气真好，我们一起去散步吧！"),
        Lettering(columns: ["はい"], fontSize: 30, centre: CGPoint(x: 420, y: 150), balloonSize: CGSize(width: 120, height: 160),
                  translation: "好的", hint: .none),
        Lettering(columns: ["昨日の夜から", "ずっと雨が", "降っている"], fontSize: 24, centre: CGPoint(x: 640, y: 200), shape: .box,
                  balloonSize: CGSize(width: 160, height: 230), translation: "从昨天晚上开始就一直在下雨。", hint: .mask),
        Lettering(columns: ["何だって", "本当なの"], fontSize: 26, centre: CGPoint(x: 420, y: 480), shape: .none,
                  translation: "你说什么？是真的吗？")
    ]

    private func page(_ ground: SyntheticImages.Ground = .white) throws -> SyntheticImages.LetteredPage {
        try SyntheticImages.letteredPage(width: 800, height: 640, ground: ground, letterings: Self.letterings)
    }

    /// The colour and alpha of a patch's pixel at (`x`, `y`) of the page.
    private func pixel(_ patch: Patch, _ x: Int, _ y: Int) -> (color: PixelColor, alpha: UInt8) {
        let offset = ((y - patch.rect.y0) * patch.rect.width + x - patch.rect.x0) * 4
        return (PixelColor(red: patch.pixels[offset], green: patch.pixels[offset + 1], blue: patch.pixels[offset + 2]),
                patch.pixels[offset + 3])
    }

    @Test(arguments: [SyntheticImages.Ground.white, .gradient, .texture])
    func everyTranslatedBlockBecomesAPatch(ground: SyntheticImages.Ground) async throws {
        let page = try page(ground)
        let render = try await PageRenderer().render(page: page.bitmap, blocks: page.blocks)
        #expect(render.blocks.map(\.index) == [0, 1, 2, 3])
        #expect(render.blocks.map(\.kind) == [.dialogue, .dialogue, .caption, .aside])
        #expect(render.blocks.map(\.isInBalloon) == [true, true, true, false])
        #expect(render.blocks.allSatisfy { $0.isVertical && !$0.isRepainted })
        #expect(render.blocks[0].lines == ["今天天气真好，", "我们一起去散步吧！"])
        #expect(render.blocks[1].lines == ["好的"])
        #expect(render.failedRepaints == 0)
        #expect(render.patches.count == 4)
        for (block, lettering) in zip(render.blocks, Self.letterings) {
            // Between the dots of a screentone a note's size is anyone's guess.
            if block.isInBalloon || ground != .texture {
                #expect(abs(block.measuredFontSize / Double(lettering.fontSize) - 1) < 0.15)
            }
            #expect(block.fontSize <= block.measuredFontSize * 1.08 + 0.001)
        }
        // In balloons the text fits; the first three are balloons.
        #expect(render.blocks.prefix(3).allSatisfy { !$0.overflows })
        #expect(render.timings.total > .zero && render.timings.repainting == .zero)
    }

    @Test(arguments: [SyntheticImages.Ground.white, .gradient, .texture])
    func aPatchIsOpaqueOnlyWhereItErasedOrLettered(ground: SyntheticImages.Ground) async throws {
        let page = try page(ground)
        let render = try await PageRenderer().render(page: page.bitmap, blocks: page.blocks)
        for block in render.blocks {
            let patch = block.patch
            let analysis = try #require(BlockAnalyzer().analyze(page: page.bitmap, block: page.blocks[block.index], index: block.index))
            #expect(patch.rect == patch.rect.clamped(width: 800, height: 640))
            #expect(patch.rect.union(analysis.erase.rect) == patch.rect)
            var transparent = 0, lettered = 0
            for y in patch.rect.y0..<patch.rect.y1 {
                for x in patch.rect.x0..<patch.rect.x1 {
                    let (color, alpha) = pixel(patch, x, y)
                    if analysis.erase.contains(x, y) {
                        #expect(alpha == 255)
                    } else if alpha == 0 {
                        transparent += 1
                        #expect(color == .black)
                    } else {
                        // Outside the erased pixels only the lettering is drawn: black ink,
                        // premultiplied, so every channel is zero.
                        lettered += 1
                        #expect(color.luma <= 2)
                    }
                }
            }
            #expect(transparent > 0, "block \(block.index)")
            // In a balloon the new columns do not stand where the old ones did.
            if block.isInBalloon { #expect(lettered > 0, "block \(block.index)") }
            #expect(!patch.isTransparent)
            let fraction = patch.fractionalRect(imageWidth: 800, imageHeight: 640)
            #expect(fraction.x >= 0 && fraction.y >= 0 && fraction.maxX <= 1 && fraction.maxY <= 1)
            #expect(abs(fraction.x * 800 - Double(patch.rect.x0)) < 1e-9 && abs(fraction.height * 640 - Double(patch.rect.height)) < 1e-9)
        }
    }

    @Test(arguments: [SyntheticImages.Ground.white, .gradient, .texture])
    func theLetteringStaysInsideItsBalloon(ground: SyntheticImages.Ground) async throws {
        let page = try page(ground)
        let render = try await PageRenderer().render(page: page.bitmap, blocks: page.blocks)
        let image = try #require(render.composited(over: page.bitmap))
        let after = try PageBitmap(data: #require(SyntheticImages.encode(image, as: "public.png")))
        for block in render.blocks.prefix(3) {
            let interior = try #require(page.interiors[block.index])
            // Every dark pixel the patch draws lies inside the balloon's outline.
            for y in block.patch.rect.y0..<block.patch.rect.y1 {
                for x in block.patch.rect.x0..<block.patch.rect.x1 {
                    let (color, alpha) = pixel(block.patch, x, y)
                    if alpha > 128, color.luma < 100 { #expect(interior.contains(x, y), "block \(block.index) at (\(x), \(y))") }
                }
            }
            // The balloon holds dark pixels again: the new text.
            var dark = 0
            for y in interior.rect.y0..<interior.rect.y1 {
                for x in interior.rect.x0..<interior.rect.x1 where interior.contains(x, y) && after.rgb(x, y).red < 100 {
                    dark += 1
                }
            }
            #expect(dark > 50)
        }
    }

    @Test func soundEffectsAndBlocksWithoutATranslationAreLeftAlone() async throws {
        var page = try page()
        page.blocks[0].kind = .soundEffect
        page.blocks[1].translation = ""
        page.blocks[2].translation = " \n"
        let render = try await PageRenderer().render(page: page.bitmap, blocks: page.blocks)
        #expect(render.blocks.map(\.index) == [3])
        let none = try await PageRenderer().render(page: page.bitmap, blocks: [])
        #expect(none.blocks.isEmpty && none.patches.isEmpty)
        #expect(none.composited(over: page.bitmap) != nil)
    }

    @Test func drawingTwiceGivesTheSamePatches() async throws {
        let page = try page(.gradient)
        let first = try await PageRenderer().render(page: page.bitmap, blocks: page.blocks)
        let second = try await PageRenderer().render(page: page.bitmap, blocks: page.blocks)
        #expect(first.patches == second.patches)
    }

    @Test func drawingRunsOffTheCallersActor() async throws {
        let page = try page()
        let patches = await MainActor.run { page.blocks }
        let render = try await Task { @MainActor in
            try await PageRenderer().render(page: page.bitmap, blocks: patches)
        }.value
        #expect(render.patches.count == 4)
    }

    @Test func aCancelledTaskDrawsNothing() async throws {
        let page = try page()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await PageRenderer().render(page: page.bitmap, blocks: page.blocks)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func textOnArtworkIsRepaintedByTheModelAndBalloonsAreNot() async throws {
        let page = try page(.gradient)
        let stub = StubInpainter()
        let render = try await PageRenderer().render(page: page.bitmap, blocks: page.blocks, inpainter: stub)
        #expect(render.blocks.map(\.isRepainted) == [false, false, false, true])
        #expect(await stub.calls.count == 1)
        #expect(render.timings.repainting > .zero)
        // The erased pixels of the note carry what the model painted, except under the lettering.
        let patch = render.blocks[3].patch
        let analysis = try #require(BlockAnalyzer().analyze(page: page.bitmap, block: page.blocks[3], index: 3))
        var painted = 0, erased = 0
        for y in analysis.erase.rect.y0..<analysis.erase.rect.y1 {
            for x in analysis.erase.rect.x0..<analysis.erase.rect.x1 where analysis.erase.contains(x, y) {
                erased += 1
                if pixel(patch, x, y).color == PixelColor(red: 10, green: 200, blue: 30) { painted += 1 }
            }
        }
        #expect(Double(painted) > 0.6 * Double(erased))
    }

    @Test func aRepaintModelThatFailsCostsNoTranslation() async throws {
        let page = try page(.gradient)
        let stub = StubInpainter(fails: true)
        let render = try await PageRenderer().render(page: page.bitmap, blocks: page.blocks, inpainter: stub)
        #expect(render.failedRepaints == 1)
        #expect(render.blocks.count == 4)
        #expect(render.blocks[3].isRepainted == false && !render.blocks[3].patch.isTransparent)
    }

    @Test func twoBlocksInOneBalloonKeepToTheirOwnHalves() async throws {
        // One wide balloon holding two blocks, left and right.
        let balloon = Lettering(columns: [], fontSize: 26, centre: CGPoint(x: 300, y: 230), balloonSize: CGSize(width: 440, height: 300))
        let left = Lettering(columns: ["今日は良い", "天気ですね"], fontSize: 26, centre: CGPoint(x: 210, y: 230),
                             shape: .none, translation: "今天天气真好啊，适合出门走走。")
        let right = Lettering(columns: ["散歩に行き", "ましょうか"], fontSize: 26, centre: CGPoint(x: 390, y: 230),
                              shape: .none, translation: "我们一起去公园散步吧，好不好？")
        var page = try SyntheticImages.letteredPage(width: 600, height: 460, letterings: [balloon, left, right])
        #expect(page.blocks.count == 2)
        for index in page.blocks.indices {
            page.blocks[index].kind = .dialogue
            page.blocks[index].balloon = Balloon(box: balloon.balloonRect)
        }
        let render = try await PageRenderer().render(page: page.bitmap, blocks: page.blocks)
        #expect(render.blocks.count == 2)
        func inked(_ patch: Patch) -> PixelRect {
            var rect = PixelRect.zero
            for y in patch.rect.y0..<patch.rect.y1 {
                for x in patch.rect.x0..<patch.rect.x1 {
                    let (color, alpha) = pixel(patch, x, y)
                    if alpha > 128, color.luma < 100 { rect = rect.union(PixelRect(x: x, y: y, width: 1, height: 1)) }
                }
            }
            return rect
        }
        let leftInk = inked(render.blocks[0].patch), rightInk = inked(render.blocks[1].patch)
        #expect(!leftInk.isEmpty && !rightInk.isEmpty)
        #expect(leftInk.intersection(rightInk).isEmpty)
        #expect(leftInk.x1 <= rightInk.x0)
    }

    @Test func aPatchFileCarriesThePagesColourSpace() async throws {
        let displayP3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let lettering = Self.letterings[0]
        let plain = try SyntheticImages.letteredPage(width: 340, height: 440, letterings: [lettering])
        let image = try #require(SyntheticImages.image(width: 340, height: 440, space: displayP3) { context in
            context.translateBy(x: 0, y: 440)
            context.scaleBy(x: 1, y: -1)
            context.draw(plain.image, in: CGRect(x: 0, y: 0, width: 340, height: 440))
        })
        let page = try PageBitmap(data: #require(SyntheticImages.encode(image, as: "public.png")))
        #expect(page.colorSpace.name == CGColorSpace.displayP3)
        let render = try await PageRenderer().render(page: page, blocks: plain.blocks)
        let patch = try #require(render.patches.first)
        let data = try #require(patch.pngData(colorSpace: page.colorSpace))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == patch.rect.width && decoded.height == patch.rect.height)
        #expect(decoded.colorSpace?.name == CGColorSpace.displayP3)
        #expect(decoded.alphaInfo == .premultipliedLast || decoded.alphaInfo == .last)
    }
}

/// The cost of drawing a page.
@Suite struct RenderTimingTests {
    /// A page of about two megapixels with ten balloons of dialogue.
    static func tenBalloonPage() throws -> SyntheticImages.LetteredPage {
        let texts: [([String], String)] = [
            (["今日は良い天気", "ですね散歩に", "行きましょう"], "今天天气真好，我们一起去散步吧！"),
            (["昨日の夜から", "ずっと雨が", "降っている"], "从昨天晚上开始就一直在下雨。"),
            (["何だって", "本当なの"], "你说什么？是真的吗？"),
            (["漢字の勉強は", "難しいですね"], "学习汉字真的很难啊……"),
            (["明日の朝早く", "駅前で待って", "いますから", "来てください"], "明天一大早我在车站前等你，一定要来啊。"),
            (["はい"], "好的"),
            (["そんな事を", "言われても", "困ります"], "你这么说我也很为难。"),
            (["え？"], "诶？"),
            (["もう一度だけ", "考えさせて", "ください"], "请让我再考虑一次。"),
            (["ありがとう", "ございます"], "非常感谢！")
        ]
        var letterings: [SyntheticImages.Lettering] = []
        for (index, text) in texts.enumerated() {
            let column = index % 3, row = index / 3
            letterings.append(SyntheticImages.Lettering(
                columns: text.0, fontSize: 30, centre: CGPoint(x: 220 + column * 400, y: 230 + row * 400),
                balloonSize: CGSize(width: 250, height: 340), translation: text.1, hint: index % 2 == 0 ? .mask : .box
            ))
        }
        return try SyntheticImages.letteredPage(width: 1200, height: 1700, ground: .texture, letterings: letterings)
    }

    /// A generous bound for a debug build among other tests, which still catches work that
    /// grows with the page instead of the text. Measured on the development Mac in a release
    /// build: see the task's report.
    @Test func aTwoMegapixelPageWithTenBalloons() async throws {
        let page = try Self.tenBalloonPage()
        #expect(page.bitmap.width * page.bitmap.height == 2_040_000)
        let renderer = PageRenderer()
        // The first use of the fonts measures their weights once.
        _ = FontLibrary.bundled
        let render = try await renderer.render(page: page.bitmap, blocks: page.blocks)
        #expect(render.blocks.count == 10)
        #expect(render.blocks.allSatisfy { $0.isInBalloon && !$0.overflows })
        #expect(render.timings.total < .seconds(60), "\(render.timings)")
    }
}
