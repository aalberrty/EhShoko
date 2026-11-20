import CoreGraphics
import EhModels
import Foundation
import ImageIO

/// One page's patches as one file: a short layout header, then one PNG that packs every patch
/// (the atlas). What a translated page shows over the original, kept in Caches so a page is
/// drawn once.
///
/// A missing or unreadable file means "draw the page again from its text", never an error the
/// user sees, so every way a file can be wrong is one error, `PatchFileError.unreadable`.
public struct PatchFile: Sendable {
    /// Where one patch's pixels are in the atlas and where they go on the page.
    public struct Placement: Sendable, Hashable {
        /// In pixels of the page bitmap the patch was made on.
        public var pageRect: PixelRect
        /// In pixels of the atlas; the same size as `pageRect`.
        public var atlasRect: PixelRect

        public init(pageRect: PixelRect, atlasRect: PixelRect) {
            self.pageRect = pageRect
            self.atlasRect = atlasRect
        }
    }

    /// The size of the page bitmap the patches were made on; `pageRect`s are in its pixels.
    public let imageWidth: Int
    public let imageHeight: Int
    /// In the order the patches were given, transparent ones left out.
    public let placements: [Placement]
    /// Every patch's pixels, decoded, in the page bitmap's colour space; `nil` when the page has
    /// nothing to draw.
    public let atlas: CGImage?

    init(imageWidth: Int, imageHeight: Int, placements: [Placement], atlas: CGImage?) {
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.placements = placements
        self.atlas = atlas
    }

    /// Where `placement` goes, as fractions of the page, so it stays right at any size the page
    /// is shown at.
    public func fractionalRect(of placement: Placement) -> FractionalRect {
        placement.pageRect.fractional(imageWidth: imageWidth, imageHeight: imageHeight)
    }

    /// The pixels of `placement` as an image that shares the atlas's memory. An overlay draws
    /// each patch from its own image rather than from a part of the atlas, so that scaling
    /// never blends in a neighbour's edge.
    public func image(of placement: Placement) -> CGImage? {
        atlas?.cropping(to: placement.atlasRect.cgRect)
    }
}

public enum PatchFileError: Error, Equatable {
    /// No file: the page was never drawn, or the system emptied Caches.
    case missing
    /// Not a patch file this build reads: damaged, cut short or of another format version.
    case unreadable
    /// Writing: a patch reaches outside the page, or the PNG could not be made.
    case unwritable
}

extension PatchFile {
    /// Encodes `patches` and writes them to `url` atomically, creating its folder; returns the
    /// file's size in bytes. Runs on the global executor: packing and the PNG encoder take
    /// milliseconds.
    ///
    /// `colorSpace` is the page bitmap's; the PNG carries it, so the patches are shown in the
    /// same colours as the page under them.
    @concurrent
    public static func write(
        _ patches: [Patch], imageWidth: Int, imageHeight: Int, colorSpace: CGColorSpace, to url: URL
    ) async throws -> Int {
        let data = try encode(patches, imageWidth: imageWidth, imageHeight: imageHeight, colorSpace: colorSpace)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return data.count
    }

    /// Reads and decodes the file at `url` on the global executor. Throws `PatchFileError`, or
    /// `CancellationError` when the calling task is cancelled before the PNG is decoded.
    @concurrent
    public static func read(from url: URL) async throws -> PatchFile {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw PatchFileError.missing
        } catch {
            throw PatchFileError.unreadable
        }
        try Task.checkCancellation()
        return try decode(data)
    }
}

// MARK: - Encoding

extension PatchFile {
    /// The file's bytes: the header, then the atlas as a PNG (absent when nothing is drawn).
    static func encode(
        _ patches: [Patch], imageWidth: Int, imageHeight: Int, colorSpace: CGColorSpace
    ) throws(PatchFileError) -> Data {
        let page = PixelRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
        guard imageWidth > 0, imageHeight > 0,
              patches.allSatisfy({ $0.rect.intersection(page) == $0.rect || $0.rect.isEmpty })
        else { throw .unwritable }
        let drawn = patches.filter { !$0.rect.isEmpty && !$0.isTransparent }
        let layout = AtlasLayout(sizes: drawn.map { (width: $0.rect.width, height: $0.rect.height) })
        let placements = zip(drawn, layout.origins).map { patch, origin in
            Placement(
                pageRect: patch.rect,
                atlasRect: PixelRect(x: origin.x, y: origin.y, width: patch.rect.width, height: patch.rect.height)
            )
        }
        var png = Data()
        if !drawn.isEmpty {
            let pixels = atlasPixels(drawn, placements: placements, width: layout.width, height: layout.height)
            png = try Self.png(pixels, width: layout.width, height: layout.height, colorSpace: colorSpace)
        }
        var data = PatchFileHeader(
            imageWidth: imageWidth, imageHeight: imageHeight,
            atlasWidth: layout.width, atlasHeight: layout.height, placements: placements, pngLength: png.count
        ).encoded()
        data.append(png)
        return data
    }

    /// The atlas's premultiplied RGBA pixels: every patch copied row by row to its place,
    /// transparent between them.
    private static func atlasPixels(_ patches: [Patch], placements: [Placement], width: Int, height: Int) -> Data {
        let bytesPerRow = width * 4
        var pixels = Data(count: bytesPerRow * height)
        pixels.withUnsafeMutableBytes { atlas in
            guard let atlasBase = atlas.baseAddress else { return }
            for (patch, placement) in zip(patches, placements) {
                let rowLength = patch.rect.width * 4
                patch.pixels.withUnsafeBytes { source in
                    guard let sourceBase = source.baseAddress else { return }
                    for row in 0..<patch.rect.height {
                        let target = (placement.atlasRect.y0 + row) * bytesPerRow + placement.atlasRect.x0 * 4
                        atlasBase.advanced(by: target)
                            .copyMemory(from: sourceBase.advanced(by: row * rowLength), byteCount: rowLength)
                    }
                }
            }
        }
        return pixels
    }

    private static func png(_ pixels: Data, width: Int, height: Int, colorSpace: CGColorSpace) throws(PatchFileError) -> Data {
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: colorSpace, bitmapInfo: Patch.bitmapInfo, provider: provider, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent
              )
        else { throw .unwritable }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil)
        else { throw .unwritable }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw .unwritable }
        return output as Data
    }
}

// MARK: - Decoding

extension PatchFile {
    static func decode(_ data: Data) throws(PatchFileError) -> PatchFile {
        let header = try PatchFileHeader(decoding: data)
        guard !header.placements.isEmpty else {
            return PatchFile(imageWidth: header.imageWidth, imageHeight: header.imageHeight, placements: [], atlas: nil)
        }
        let png = data.subdata(in: header.length..<data.count)
        guard let source = CGImageSourceCreateWithData(png as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              // The PNG's own size is checked before it is decoded, so a damaged file cannot make
              // the decoder allocate more than the header allows.
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == header.atlasWidth,
              (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == header.atlasHeight,
              // Decoded here, off the main actor, rather than when the image is first drawn.
              let atlas = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              ),
              atlas.width == header.atlasWidth, atlas.height == header.atlasHeight
        else { throw .unreadable }
        return PatchFile(
            imageWidth: header.imageWidth, imageHeight: header.imageHeight,
            placements: header.placements, atlas: atlas
        )
    }

    /// Every patch's pixels, premultiplied RGBA in `colorSpace`, as `Patch` values: what the
    /// file was written from, up to the rounding of the PNG's unpremultiplied alpha.
    func patches(colorSpace: CGColorSpace) -> [Patch]? {
        guard let atlas else { return placements.isEmpty ? [] : nil }
        let width = atlas.width, height = atlas.height, bytesPerRow = width * 4
        var pixels = Data(count: bytesPerRow * height)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: colorSpace, bitmapInfo: Patch.bitmapInfo.rawValue
            ) else { return false }
            context.setBlendMode(.copy)
            context.draw(atlas, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        return placements.map { placement in
            var patchPixels = Data(capacity: placement.atlasRect.area * 4)
            for row in placement.atlasRect.y0..<placement.atlasRect.y1 {
                let start = row * bytesPerRow + placement.atlasRect.x0 * 4
                patchPixels.append(pixels[start..<(start + placement.atlasRect.width * 4)])
            }
            return Patch(rect: placement.pageRect, pixels: patchPixels)
        }
    }
}
