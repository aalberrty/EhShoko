import CoreGraphics
import Foundation
import Testing
@testable import EhCore

/// An overlay's patches as the reader's engine reads them, and as the reader harness writes
/// its made-up ones.
@Suite struct PageTranslationOverlayPatchesTests {
    @Test func patchesComeBackWhereTheyWereWritten() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let overlay = PageTranslationOverlay(patchFile: directory.appending(path: "1.patch"), variant: "test")
        let written = PageTranslationPatches(
            pageSize: CGSize(width: 800, height: 1_200),
            patches: [
                .init(rect: CGRect(x: 100, y: 200, width: 60, height: 40), image: try Self.fill(60, 40, [255, 0, 0, 255])),
                // Touches the page's far corner.
                .init(rect: CGRect(x: 780, y: 1_170, width: 20, height: 30), image: try Self.fill(20, 30, [0, 255, 0, 255])),
                // Half transparent: stored and read back premultiplied.
                .init(rect: CGRect(x: 0, y: 0, width: 10, height: 10), image: try Self.fill(10, 10, [0, 0, 128, 128]))
            ]
        )
        try await written.write(to: overlay.patchFile)

        let read = try await overlay.patches()
        #expect(read.pageSize == CGSize(width: 800, height: 1_200))
        #expect(read.patches.map(\.rect) == written.patches.map(\.rect))
        #expect(read.patches.map { CGSize(width: $0.image.width, height: $0.image.height) }
            == [CGSize(width: 60, height: 40), CGSize(width: 20, height: 30), CGSize(width: 10, height: 10)])
        #expect(try Self.pixel(of: read.patches[0].image, x: 30, y: 20) == [255, 0, 0, 255])
        #expect(try Self.pixel(of: read.patches[1].image, x: 19, y: 29) == [0, 255, 0, 255])
        // A PNG stores the colour without its alpha, so a premultiplied value may come back
        // one level off.
        let faint = try Self.pixel(of: read.patches[2].image, x: 5, y: 5)
        #expect(faint[0] == 0 && faint[1] == 0 && abs(Int(faint[2]) - 128) <= 1 && faint[3] == 128)
    }

    @Test func aPatchKeepsItsOwnEdges() async throws {
        // Two patches that end up side by side in the file: each image is its own, and its
        // last column is its own colour, not the neighbour's.
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let overlay = PageTranslationOverlay(patchFile: directory.appending(path: "2.patch"), variant: "test")
        try await PageTranslationPatches(
            pageSize: CGSize(width: 400, height: 400),
            patches: [
                .init(rect: CGRect(x: 0, y: 0, width: 50, height: 50), image: try Self.fill(50, 50, [255, 0, 0, 255])),
                .init(rect: CGRect(x: 40, y: 40, width: 50, height: 50), image: try Self.fill(50, 50, [0, 0, 255, 255]))
            ]
        ).write(to: overlay.patchFile)

        let read = try await overlay.patches()
        #expect(read.patches.map(\.rect.origin) == [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 40)])
        for (patch, colour) in zip(read.patches, [[255, 0, 0, 255], [0, 0, 255, 255]] as [[UInt8]]) {
            #expect(try Self.pixel(of: patch.image, x: 0, y: 0) == colour)
            #expect(try Self.pixel(of: patch.image, x: 49, y: 49) == colour)
        }
    }

    @Test func aRectangleBetweenPixelsIsTakenToWholePixels() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let overlay = PageTranslationOverlay(patchFile: directory.appending(path: "3.patch"), variant: "test")
        try await PageTranslationPatches(
            pageSize: CGSize(width: 300, height: 300),
            patches: [
                .init(rect: CGRect(x: 10.4, y: 20.6, width: 30.2, height: 9.9), image: try Self.fill(31, 11, [9, 9, 9, 255]))
            ]
        ).write(to: overlay.patchFile)
        #expect(try await overlay.patches().patches.map(\.rect) == [CGRect(x: 10, y: 20, width: 31, height: 11)])
    }

    @Test func aPageWithNothingToDrawHasNoPatches() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let overlay = PageTranslationOverlay(patchFile: directory.appending(path: "4.patch"), variant: "test")
        try await PageTranslationPatches(pageSize: CGSize(width: 640, height: 900), patches: []).write(to: overlay.patchFile)
        let read = try await overlay.patches()
        #expect(read.patches.isEmpty)
        #expect(read.pageSize == CGSize(width: 640, height: 900))
    }

    @Test func aPatchOutsideThePageIsNotWritten() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "5.patch")
        let patches = PageTranslationPatches(
            pageSize: CGSize(width: 100, height: 100),
            patches: [.init(rect: CGRect(x: 90, y: 90, width: 20, height: 20), image: try Self.fill(20, 20, [1, 2, 3, 255]))]
        )
        await #expect(throws: (any Error).self) { try await patches.write(to: url) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aMissingOrDamagedFileIsUnreadable() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = PageTranslationOverlay(patchFile: directory.appending(path: "none.patch"), variant: "test")
        await #expect(throws: PageTranslationOverlayUnreadable.self) { _ = try await missing.patches() }

        let damaged = PageTranslationOverlay(patchFile: directory.appending(path: "damaged.patch"), variant: "test")
        try await PageTranslationPatches(
            pageSize: CGSize(width: 200, height: 200),
            patches: [.init(rect: CGRect(x: 0, y: 0, width: 40, height: 40), image: try Self.fill(40, 40, [7, 7, 7, 255]))]
        ).write(to: damaged.patchFile)
        let whole = try Data(contentsOf: damaged.patchFile)
        try whole.prefix(whole.count - 20).write(to: damaged.patchFile)
        await #expect(throws: PageTranslationOverlayUnreadable.self) { _ = try await damaged.patches() }

        try Data("not a patch file".utf8).write(to: damaged.patchFile)
        await #expect(throws: PageTranslationOverlayUnreadable.self) { _ = try await damaged.patches() }
    }

    @Test func aCancelledReadIsACancellation() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let overlay = PageTranslationOverlay(patchFile: directory.appending(path: "6.patch"), variant: "test")
        try await PageTranslationPatches(
            pageSize: CGSize(width: 200, height: 200),
            patches: [.init(rect: CGRect(x: 0, y: 0, width: 40, height: 40), image: try Self.fill(40, 40, [7, 7, 7, 255]))]
        ).write(to: overlay.patchFile)
        let task = Task {
            // Cancelled before the read begins, so the outcome does not depend on timing.
            withUnsafeCurrentTask { $0?.cancel() }
            return try await overlay.patches()
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    // MARK: Helpers

    static func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "OverlayPatches-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// An image of one premultiplied RGBA colour.
    static func fill(_ width: Int, _ height: Int, _ colour: [UInt8]) throws -> CGImage {
        var pixels = Data(capacity: width * height * 4)
        for _ in 0..<(width * height) { pixels.append(contentsOf: colour) }
        let provider = try #require(CGDataProvider(data: pixels as CFData))
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        return try #require(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
    }

    /// One pixel of an image as premultiplied RGBA in sRGB; `y` counts from the top.
    static func pixel(of image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        var pixel = [UInt8](repeating: 0, count: 4)
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        try pixel.withUnsafeMutableBytes { raw in
            let context = try #require(CGContext(
                data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.setBlendMode(.copy)
            context.interpolationQuality = .none
            // The context's one pixel shows the image's pixel (x, y from the top).
            context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        }
        return pixel
    }
}
