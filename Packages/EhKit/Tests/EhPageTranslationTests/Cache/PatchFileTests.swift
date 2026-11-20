import CoreGraphics
import EhModels
import Foundation
import Testing
@testable import EhPageTranslation

@Suite struct PatchFileTests {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    @Test func patchesComeBackAsTheyWereWritten() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "1/variant/3.patch")
        let opaque = Self.patch(PixelRect(x: 100, y: 40, width: 60, height: 90), seed: 1)
        let edged = Self.patch(PixelRect(x: 10, y: 300, width: 33, height: 17), seed: 2, edgeAlpha: 128)
        let empty = Patch(rect: PixelRect(x: 0, y: 0, width: 4, height: 4), pixels: Data(count: 64))

        let bytes = try await PatchFile.write(
            [opaque, empty, edged], imageWidth: 400, imageHeight: 600, colorSpace: Self.sRGB, to: url
        )
        #expect(bytes == (try Data(contentsOf: url)).count)
        let file = try await PatchFile.read(from: url)
        #expect(file.imageWidth == 400 && file.imageHeight == 600)
        // The transparent patch has nothing to draw and is left out.
        #expect(file.placements.map(\.pageRect) == [opaque.rect, edged.rect])
        let patches = try #require(file.patches(colorSpace: Self.sRGB))
        #expect(patches[0] == opaque)
        // Half-transparent pixels go through the PNG's unpremultiplied alpha: off by one at most.
        #expect(patches[1].rect == edged.rect)
        #expect(Self.largestDifference(patches[1].pixels, edged.pixels) <= 1)
    }

    @Test func placementsAreFractionsOfThePageAndImagesOfTheirOwn() async throws {
        let rect = PixelRect(x: 100, y: 150, width: 50, height: 75)
        let data = try PatchFile.encode(
            [Self.patch(rect, seed: 3)], imageWidth: 400, imageHeight: 600, colorSpace: Self.sRGB
        )
        let file = try PatchFile.decode(data)
        let placement = try #require(file.placements.first)
        #expect(file.fractionalRect(of: placement) == FractionalRect(x: 0.25, y: 0.25, width: 0.125, height: 0.125))
        let image = try #require(file.image(of: placement))
        #expect(image.width == 50 && image.height == 75)
    }

    @Test func aPageWithNothingToDrawHasOnlyAHeader() async throws {
        let data = try PatchFile.encode([], imageWidth: 800, imageHeight: 1200, colorSpace: Self.sRGB)
        #expect(data.count == PatchFileHeader.fixedLength)
        let file = try PatchFile.decode(data)
        #expect(file.placements.isEmpty && file.atlas == nil)
        #expect(file.imageWidth == 800 && file.imageHeight == 1200)
    }

    @Test func theAtlasKeepsThePagesColourSpace() async throws {
        let displayP3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let patch = Self.patch(PixelRect(x: 0, y: 0, width: 20, height: 20), seed: 4)
        let data = try PatchFile.encode([patch], imageWidth: 40, imageHeight: 40, colorSpace: displayP3)
        let file = try PatchFile.decode(data)
        #expect(file.atlas?.colorSpace?.name == CGColorSpace.displayP3)
        #expect(try #require(file.patches(colorSpace: displayP3)) == [patch])
    }

    @Test func writingAgainReplacesTheFileAndLeavesNothingElse() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "1.patch")
        let first = Self.patch(PixelRect(x: 0, y: 0, width: 10, height: 10), seed: 5)
        let second = Self.patch(PixelRect(x: 5, y: 5, width: 12, height: 8), seed: 6)
        _ = try await PatchFile.write([first], imageWidth: 20, imageHeight: 20, colorSpace: Self.sRGB, to: url)
        _ = try await PatchFile.write([second], imageWidth: 20, imageHeight: 20, colorSpace: Self.sRGB, to: url)
        #expect(try await PatchFile.read(from: url).placements.map(\.pageRect) == [second.rect])
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["1.patch"])
    }

    @Test func aMissingFileIsMissing() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "EhShokoTests-\(UUID().uuidString).patch")
        await #expect(throws: PatchFileError.missing) { try await PatchFile.read(from: url) }
    }

    @Test func aDamagedFileIsUnreadable() throws {
        let patch = Self.patch(PixelRect(x: 10, y: 10, width: 30, height: 20), seed: 7)
        let data = try PatchFile.encode([patch], imageWidth: 100, imageHeight: 100, colorSpace: Self.sRGB)
        var otherVersion = data
        otherVersion[4] = 2
        var wrongMagic = data
        wrongMagic[0] = 0
        var outsideThePage = data
        outsideThePage[32] = 90  // the patch's x: 90 + 30 is past the page's 100 pixels
        var tooManyPatches = data
        tooManyPatches[8] = 2
        let damaged: [Data] = [
            Data(), data.prefix(20), data.prefix(PatchFileHeader.fixedLength + 10), data.dropLast(40),
            otherVersion, wrongMagic, outsideThePage, tooManyPatches
        ].map { Data($0) }
        for bytes in damaged {
            #expect(throws: PatchFileError.unreadable) { try PatchFile.decode(bytes) }
        }
    }

    @Test func aPatchOutsideThePageIsNotWritten() {
        let patch = Self.patch(PixelRect(x: 90, y: 0, width: 20, height: 10), seed: 8)
        #expect(throws: PatchFileError.unwritable) {
            try PatchFile.encode([patch], imageWidth: 100, imageHeight: 100, colorSpace: Self.sRGB)
        }
    }

    @Test func theAtlasPacksPatchesApartAndInsideIt() {
        let sizes = [(40, 10), (12, 60), (30, 30), (5, 5), (70, 8), (12, 60), (1, 1)]
            .map { (width: $0.0, height: $0.1) }
        let layout = AtlasLayout(sizes: sizes)
        let rects = zip(sizes, layout.origins).map { size, origin in
            PixelRect(x: origin.x, y: origin.y, width: size.width, height: size.height)
        }
        let atlas = PixelRect(x: 0, y: 0, width: layout.width, height: layout.height)
        for (index, rect) in rects.enumerated() {
            #expect(rect.intersection(atlas) == rect)
            for other in rects[(index + 1)...] {
                // Apart by the gutter, not only not overlapping.
                #expect(rect.insetBy(-AtlasLayout.gutter, -AtlasLayout.gutter).intersection(other).isEmpty)
            }
        }
        // Not much larger than the patches and their gutters.
        let area = sizes.reduce(0) { $0 + ($1.width + 1) * ($1.height + 1) }
        #expect(atlas.area < area * 2)
        #expect(AtlasLayout(sizes: sizes) == layout)
        #expect(AtlasLayout(sizes: []).origins.isEmpty)
    }

    /// A patch file of about 300 KB, the large end of a page, written and read back. The plan
    /// estimated 20 ms for both. On the development Mac (debug build, load 20 to 60) writing
    /// took 40 to 65 ms, nearly all of it the system's PNG encoder, and reading 2 to 6 ms. The
    /// bounds only catch work that grows out of proportion.
    @Test func aLargePatchFileIsQuickToWriteAndRead() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "1.patch")
        let patches: [Patch] = (0..<10).map { (index: Int) -> Patch in
            let x: Int = (index % 2) * 600
            let y: Int = (index / 2) * 360
            let rect = PixelRect(x: x, y: y, width: 200, height: 190)
            return Self.patch(rect, seed: UInt64(index + 10), noise: 1)
        }
        let clock = ContinuousClock()
        let start = clock.now
        let bytes = try await PatchFile.write(patches, imageWidth: 1280, imageHeight: 1810, colorSpace: Self.sRGB, to: url)
        let written = clock.now
        let file = try await PatchFile.read(from: url)
        let read = clock.now
        #expect((200_000...400_000).contains(bytes), "\(bytes) bytes")
        #expect(file.placements.count == 10)
        #expect(written - start < .seconds(1), "write \(written - start)")
        #expect(read - written < .seconds(1), "read \(read - written)")
    }

    // MARK: - Helpers

    /// A patch like a lettered balloon: a light background with a little noise, darker strokes,
    /// opaque everywhere, or with a half-transparent border of `edgeAlpha`.
    static func patch(_ rect: PixelRect, seed: UInt64, edgeAlpha: UInt8? = nil, noise: Int = 2) -> Patch {
        var random = SplitMix(seed: seed)
        var pixels = Data(count: rect.area * 4)
        let levels = UInt64(2 * noise + 1)
        pixels.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            for y in 0..<rect.height {
                for x in 0..<rect.width {
                    let stroke: Bool = (x / 3 + y / 7) % 5 == 0
                    let base: Int = stroke ? 40 : 235
                    let jitter: Int = Int(random.next() % levels) - noise
                    let value: Int = min(max(base + jitter, 0), 255)
                    let border: Bool = x == 0 || y == 0 || x == rect.width - 1 || y == rect.height - 1
                    let alpha: Int = border ? Int(edgeAlpha ?? 255) : 255
                    // Premultiplied, as patches are.
                    let premultiplied: Int = (value * alpha + 127) / 255
                    let offset: Int = (y * rect.width + x) * 4
                    raw[offset] = UInt8(premultiplied)
                    raw[offset + 1] = UInt8(premultiplied)
                    raw[offset + 2] = UInt8(premultiplied * 9 / 10)
                    raw[offset + 3] = UInt8(alpha)
                }
            }
        }
        return Patch(rect: rect, pixels: pixels)
    }

    static func largestDifference(_ lhs: Data, _ rhs: Data) -> Int {
        zip(lhs, rhs).map { abs(Int($0) - Int($1)) }.max() ?? 0
    }

    static func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "EhShokoTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
