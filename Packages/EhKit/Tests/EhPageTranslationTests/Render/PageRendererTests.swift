import CoreGraphics
@testable import EhPageTranslation
import EhModels
import Foundation
import Testing

/// One page with its analysis and its drawing, made once: many tests look at the same result,
/// and making it is what costs. Its ground is white, a gradient and a screentone side by
/// side, with two blocks on each.
actor DrawnPage {
    static let shared = DrawnPage()

    typealias Lettering = SyntheticImages.Lettering

    struct Drawn: Sendable {
        var page: SyntheticImages.LetteredPage
        var analysis: PageAnalysis
        var render: PageRender
    }

    static let letterings: [Lettering] = [
        // On white: a balloon, and a note on the paper.
        Lettering(columns: ["今日は良い天気", "ですね散歩に", "行きましょう"], fontSize: 20, centre: CGPoint(x: 85, y: 120),
                  balloonSize: CGSize(width: 150, height: 220), translation: "今天天气真好，我们一起去散步吧！"),
        Lettering(columns: ["何だって", "本当なの"], fontSize: 20, centre: CGPoint(x: 150, y: 320), shape: .none,
                  translation: "你说什么？是真的吗？"),
        // On the gradient: a balloon with a gradient of its own and furigana, and a caption box.
        Lettering(columns: ["漢字の勉強", "難しいです"], fontSize: 24, centre: CGPoint(x: 325, y: 120),
                  balloonSize: CGSize(width: 150, height: 220), ruby: ["かんじのべん", ""], balloonGray: 0.96, balloonGrayBottom: 0.74,
                  translation: "学习汉字真的很难啊……", hint: .mask),
        Lettering(columns: ["昨日の夜から", "ずっと雨が", "降っている"], fontSize: 18, centre: CGPoint(x: 400, y: 305), shape: .box,
                  balloonSize: CGSize(width: 110, height: 170), translation: "从昨天晚上开始就一直在下雨。", hint: .mask),
        // On the screentone: a balloon, and a shout the detector gave no balloon for.
        Lettering(columns: ["もう一度だけ", "考えさせて", "ください"], fontSize: 20, centre: CGPoint(x: 570, y: 120),
                  balloonSize: CGSize(width: 150, height: 220), translation: "请让我再考虑一次。", hint: .mask),
        Lettering(columns: ["え？"], fontSize: 32, centre: CGPoint(x: 650, y: 315), balloonSize: CGSize(width: 100, height: 140),
                  fontName: "HiraginoSans-W8", translation: "诶？", hint: .none)
    ]
    static let width = 720, height = 400
    /// The index of the note, the one block that stands in no balloon.
    static let note = 1

    static func page() throws -> SyntheticImages.LetteredPage {
        try SyntheticImages.letteredPage(width: width, height: height, ground: .thirds, letterings: letterings)
    }

    private var task: Task<Drawn, any Error>?

    func drawn() async throws -> Drawn {
        if let task { return try await task.value }
        let task = Task<Drawn, any Error> {
            let page = try Self.page()
            let analysis = try PageAnalyzer().analyze(page: page.bitmap, blocks: page.blocks)
            let render = try await PageRenderer().draw(analysis, page: page.bitmap, blocks: page.blocks)
            return Drawn(page: page, analysis: analysis, render: render)
        }
        self.task = task
        return try await task.value
    }
}

/// Drawing a page: patches out.
@Suite(.oneDrawingTestAtATime) struct PageRendererTests {
    typealias Lettering = SyntheticImages.Lettering

    /// The colour and alpha of a patch's pixel at (`x`, `y`) of the page.
    private func pixel(_ patch: Patch, _ x: Int, _ y: Int) -> (color: PixelColor, alpha: UInt8) {
        let offset = ((y - patch.rect.y0) * patch.rect.width + x - patch.rect.x0) * 4
        return (PixelColor(red: patch.pixels[offset], green: patch.pixels[offset + 1], blue: patch.pixels[offset + 2]),
                patch.pixels[offset + 3])
    }

    @Test func everyTranslatedBlockBecomesAPatch() async throws {
        let render = try await DrawnPage.shared.drawn().render
        #expect(render.blocks.map(\.index) == [0, 1, 2, 3, 4, 5])
        #expect(render.blocks.map(\.kind) == [.dialogue, .aside, .dialogue, .caption, .dialogue, .dialogue])
        #expect(render.blocks.map(\.isInBalloon) == [true, false, true, true, true, true])
        #expect(render.blocks.allSatisfy { $0.isVertical && !$0.isRepainted })
        #expect(render.blocks[0].lines.joined() == "今天天气真好，我们一起去散步吧！")
        #expect(render.blocks[0].lines.count >= 2)
        #expect(render.blocks[5].lines == ["诶？"])
        #expect(render.failedRepaints == 0)
        #expect(render.patches.count == 6)
        for (block, lettering) in zip(render.blocks, DrawnPage.letterings) {
            #expect(abs(block.measuredFontSize / Double(lettering.fontSize) - 1) < 0.15, "block \(block.index)")
            #expect(block.fontSize <= block.measuredFontSize * 1.08 + 0.001)
            // In balloons the text fits.
            if block.isInBalloon { #expect(!block.overflows, "block \(block.index)") }
        }
        #expect(render.timings.repainting == .zero)
    }

    @Test func aPatchIsOpaqueOnlyWhereItErasedOrLettered() async throws {
        let drawn = try await DrawnPage.shared.drawn()
        let page = drawn.page, render = drawn.render
        let width = page.bitmap.width, height = page.bitmap.height
        for block in render.blocks {
            let patch = block.patch
            let analysis = try #require(drawn.analysis.blocks.first { $0.index == block.index })
            #expect(patch.rect == patch.rect.clamped(width: width, height: height))
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
            let fraction = patch.fractionalRect(imageWidth: width, imageHeight: height)
            #expect(fraction.x >= 0 && fraction.y >= 0 && fraction.maxX <= 1 && fraction.maxY <= 1)
            #expect(abs(fraction.x * Double(width) - Double(patch.rect.x0)) < 1e-9)
            #expect(abs(fraction.height * Double(height) - Double(patch.rect.height)) < 1e-9)
        }
    }

    @Test func theLetteringStaysInsideItsBalloon() async throws {
        let drawn = try await DrawnPage.shared.drawn()
        for block in drawn.render.blocks where block.isInBalloon {
            let interior = try #require(drawn.page.interiors[block.index])
            // Every dark pixel the patch draws lies inside the balloon's outline, and there
            // are some: the new text.
            var dark = 0
            for y in block.patch.rect.y0..<block.patch.rect.y1 {
                for x in block.patch.rect.x0..<block.patch.rect.x1 {
                    let (color, alpha) = pixel(block.patch, x, y)
                    guard alpha > 128, color.luma < 100 else { continue }
                    dark += 1
                    #expect(interior.contains(x, y), "block \(block.index) at (\(x), \(y))")
                }
            }
            #expect(dark > 50)
        }
    }

    @Test func soundEffectsAndBlocksWithoutATranslationAreLeftAlone() async throws {
        var page = try DrawnPage.page()
        for index in page.blocks.indices where index != DrawnPage.note {
            if index % 2 == 0 { page.blocks[index].kind = .soundEffect } else { page.blocks[index].translation = " \n" }
        }
        let render = try await PageRenderer().render(page: page.bitmap, blocks: page.blocks)
        #expect(render.blocks.map(\.index) == [DrawnPage.note])
        #expect(render.timings.analysis > .zero)
        let none = try await PageRenderer().render(page: page.bitmap, blocks: [])
        #expect(none.blocks.isEmpty && none.patches.isEmpty)
        // The page with its one patch over it, as the reader shows it.
        let image = try #require(render.composited(over: page.bitmap))
        #expect(image.width == page.bitmap.width && image.height == page.bitmap.height)
    }

    @Test func drawingAgainOffTheCallersActorGivesTheSamePatches() async throws {
        let drawn = try await DrawnPage.shared.drawn()
        let page = drawn.page
        // Called from the main actor, the work still runs elsewhere.
        let second = try await Task { @MainActor in
            try await PageRenderer().render(page: page.bitmap, blocks: page.blocks)
        }.value
        #expect(drawn.render.patches == second.patches)
    }

    @Test func aCancelledTaskDrawsNothing() async throws {
        let page = try SyntheticImages.letteredPage(width: 190, height: 260, letterings: [DrawnPage.letterings[0]])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await PageRenderer().render(page: page.bitmap, blocks: page.blocks)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func textOnArtworkIsRepaintedByTheModelAndBalloonsAreNot() async throws {
        let stub = StubInpainter()
        let drawn = try await DrawnPage.shared.drawn()
        let page = drawn.page
        let render = try await PageRenderer().draw(drawn.analysis, page: page.bitmap, blocks: page.blocks, inpainter: stub)
        #expect(render.blocks.map(\.isRepainted) == [false, true, false, false, false, false])
        #expect(await stub.calls.count == 1)
        #expect(render.timings.repainting > .zero)
        // The erased pixels of the note carry what the model painted, except under the lettering.
        let patch = render.blocks[DrawnPage.note].patch
        let analysis = drawn.analysis.blocks[DrawnPage.note]
        var painted = 0, erased = 0
        for y in analysis.erase.rect.y0..<analysis.erase.rect.y1 {
            for x in analysis.erase.rect.x0..<analysis.erase.rect.x1 where analysis.erase.contains(x, y) {
                erased += 1
                if pixel(patch, x, y).color == PixelColor(red: 10, green: 200, blue: 30) { painted += 1 }
            }
        }
        #expect(Double(painted) > 0.6 * Double(erased))
        // A model that fails costs no translation: the note is filled instead.
        let failing = try await PageRenderer().render(
            page: page.bitmap, blocks: [page.blocks[DrawnPage.note]], inpainter: StubInpainter(fails: true)
        )
        #expect(failing.failedRepaints == 1 && failing.blocks.count == 1)
        #expect(failing.blocks[0].isRepainted == false && !failing.blocks[0].patch.isTransparent)
    }

    @Test func twoBlocksInOneBalloonKeepToTheirOwnHalves() async throws {
        // One wide balloon holding two blocks, left and right.
        let balloon = Lettering(columns: [], fontSize: 20, centre: CGPoint(x: 190, y: 130), balloonSize: CGSize(width: 320, height: 220))
        let left = Lettering(columns: ["今日は良い", "天気ですね"], fontSize: 20, centre: CGPoint(x: 125, y: 130),
                             shape: .none, translation: "今天天气真好啊，适合出门走走。")
        let right = Lettering(columns: ["散歩に行き", "ましょうか"], fontSize: 20, centre: CGPoint(x: 255, y: 130),
                              shape: .none, translation: "我们一起去公园散步吧，好不好？")
        var page = try SyntheticImages.letteredPage(width: 380, height: 260, letterings: [balloon, left, right])
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

    @Test func thePatchIsDrawnInThePagesColourSpace() async throws {
        // A page in Display P3 with grey lettering: the lettering goes into the patch as the
        // values it was measured at, not converted through another colour space.
        let displayP3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        // Heavy lettering, so that its strokes are wide enough to hold pixels of the ink alone.
        let lettering = Lettering(
            columns: ["駄目だ"], fontSize: 44, centre: CGPoint(x: 95, y: 130), balloonSize: CGSize(width: 150, height: 230),
            fontName: "HiraginoSans-W8", inkGray: 0.4, translation: "不行啊"
        )
        let plain = try SyntheticImages.letteredPage(width: 190, height: 260, letterings: [lettering])
        let page = try PageBitmap(
            width: 190, height: 260, originalWidth: 190, originalHeight: 260, pixels: plain.bitmap.pixels,
            colorSpace: displayP3
        )
        let render = try await PageRenderer().render(page: page, blocks: plain.blocks)
        let patch = try #require(render.patches.first)
        let image = try #require(patch.makeImage(colorSpace: page.colorSpace))
        #expect(image.colorSpace?.name == CGColorSpace.displayP3)
        #expect(image.alphaInfo == .premultipliedLast)
        // Inside a stroke of the new lettering the patch holds the ink's own grey, 102.
        var greys = [Int](repeating: 0, count: 256)
        for y in patch.rect.y0..<patch.rect.y1 {
            for x in patch.rect.x0..<patch.rect.x1 {
                let (color, alpha) = pixel(patch, x, y)
                if alpha == 255, color.luma < 180 { greys[color.luma] += 1 }
            }
        }
        let commonest = try #require(greys.indices.max { greys[$0] < greys[$1] })
        #expect(abs(commonest - 102) <= 3)
        #expect(greys[commonest] > 100)
    }
}

/// The cost of drawing a page.
@Suite(.oneDrawingTestAtATime) struct RenderTimingTests {
    static let texts: [([String], String)] = [
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

    /// A page of `count` balloons of dialogue, three to a row, on a screentone. At a scale of
    /// 1 and ten balloons it is the page the drawing's budget is set for: 1200 × 1700, about
    /// two megapixels.
    static func page(balloons count: Int, scale: CGFloat) throws -> SyntheticImages.LetteredPage {
        var letterings: [SyntheticImages.Lettering] = []
        for (index, text) in texts.prefix(count).enumerated() {
            let column = CGFloat(index % 3), row = CGFloat(index / 3)
            letterings.append(SyntheticImages.Lettering(
                columns: text.0, fontSize: 30 * scale, centre: CGPoint(x: (220 + column * 400) * scale, y: (230 + row * 400) * scale),
                balloonSize: CGSize(width: 250 * scale, height: 340 * scale), translation: text.1,
                hint: index % 2 == 0 ? .mask : .box
            ))
        }
        let rows = CGFloat((count + 2) / 3)
        return try SyntheticImages.letteredPage(
            width: Int(1200 * scale), height: Int((rows * 400 + 100) * scale), ground: .texture, letterings: letterings
        )
    }

    /// A debug build among other tests draws a small page and only has to finish in good
    /// time: that still catches work that grows with the page instead of the text. An
    /// optimised build draws the two-megapixel page with ten balloons, whose budget on the
    /// development Mac is 300 ms when the Mac is otherwise idle; the bound here leaves room
    /// for a shared machine.
    @Test func drawingAPageOfBalloonsKeepsToItsTime() async throws {
        #if DEBUG
        let page = try Self.page(balloons: 3, scale: 0.6)
        let bound = Duration.seconds(30)
        #else
        let page = try Self.page(balloons: 10, scale: 1)
        #expect(page.bitmap.width * page.bitmap.height == 2_040_000)
        let bound = Duration.seconds(1)
        #endif
        // The first use of the fonts measures their weights, once in a process.
        _ = FontLibrary.bundled
        let render = try await PageRenderer().render(page: page.bitmap, blocks: page.blocks)
        #expect(render.blocks.count == page.blocks.count)
        #expect(render.blocks.allSatisfy { $0.isInBalloon && !$0.overflows })
        #expect(render.timings.total < bound, "\(render.timings)")
    }
}
