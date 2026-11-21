import CoreGraphics
import EhPageTranslation
import Foundation

/// A translated page's patches, read and decoded: what the reader's engine lays over the
/// page's image.
///
/// The app reads an overlay through this type. The patch file's own code (`PatchFile`) is in
/// `EhPageTranslation`, which the app does not import.
public struct PageTranslationPatches: Sendable {
    /// One patch: an image and where it goes on the page.
    public struct Patch: Sendable {
        /// In pixels of the page bitmap the patches were made on, from its top left corner.
        public var rect: CGRect
        /// The patch's pixels, premultiplied, in the page bitmap's colour space: opaque where
        /// the old text was erased, transparent where the page shows through. Composite it
        /// source-over.
        public var image: CGImage

        public init(rect: CGRect, image: CGImage) {
            self.rect = rect
            self.image = image
        }
    }

    /// The size of the page bitmap the patches were made on. That bitmap has at most four
    /// megapixels: it is neither the image the site sent nor the bitmap a reader shows. A
    /// patch is placed by the share of this size its rectangle takes.
    public var pageSize: CGSize
    /// In drawing order: a later patch lies over an earlier one.
    public var patches: [Patch]

    public init(pageSize: CGSize, patches: [Patch]) {
        self.pageSize = pageSize
        self.patches = patches
    }
}

/// An overlay's patch file is missing or is not one this build reads. The page is drawn again
/// from its stored text (`PageTranslationSession.retry`); the user is told nothing.
public struct PageTranslationOverlayUnreadable: Error, Equatable {
    public init() {}
}

extension PageTranslationOverlay {
    /// Reads the overlay's patch file and decodes it, on the global executor.
    ///
    /// Every patch is an image of its own, cut from the file's one decoded bitmap and sharing
    /// its memory, so scaling a patch never blends in its neighbour's edge.
    ///
    /// Throws `PageTranslationOverlayUnreadable`, or `CancellationError` when the calling task
    /// was cancelled before the file was decoded.
    @concurrent
    public func patches() async throws -> PageTranslationPatches {
        let file: PatchFile
        do {
            file = try await PatchFile.read(from: patchFile)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PageTranslationOverlayUnreadable()
        }
        var patches: [PageTranslationPatches.Patch] = []
        patches.reserveCapacity(file.placements.count)
        for placement in file.placements {
            // The header was checked against the bitmap when the file was decoded.
            guard let image = file.image(of: placement) else { throw PageTranslationOverlayUnreadable() }
            patches.append(PageTranslationPatches.Patch(rect: placement.pageRect.cgRect, image: image))
        }
        return PageTranslationPatches(
            pageSize: CGSize(width: file.imageWidth, height: file.imageHeight), patches: patches
        )
    }
}

extension PageTranslationPatches {
    /// Writes the patches as a patch file, on the global executor, for whoever shows an
    /// overlay without the service: the reader harness, with its made-up pages, and tests.
    /// The service writes the files of real pages itself.
    ///
    /// A patch's rectangle is taken to whole pixels and its image is drawn to that size. The
    /// file is in the first image's colour space, or sRGB.
    @concurrent
    public func write(to url: URL) async throws {
        let colorSpace = patches.first?.image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        var drawn: [EhPageTranslation.Patch] = []
        drawn.reserveCapacity(patches.count)
        for patch in patches {
            let rect = PixelRect(covering: patch.rect)
            guard let pixels = Self.pixels(of: patch.image, width: rect.width, height: rect.height, in: colorSpace)
            else { throw PatchFileError.unwritable }
            drawn.append(EhPageTranslation.Patch(rect: rect, pixels: pixels))
        }
        _ = try await PatchFile.write(
            drawn, imageWidth: Int(pageSize.width), imageHeight: Int(pageSize.height), colorSpace: colorSpace, to: url
        )
    }

    /// An image as a patch's pixels: premultiplied RGBA, rows of `width * 4` bytes, top row first.
    private static func pixels(of image: CGImage, width: Int, height: Int, in colorSpace: CGColorSpace) -> Data? {
        guard width > 0, height > 0 else { return Data() }
        var pixels = Data(count: width * height * 4)
        let isDrawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: colorSpace, bitmapInfo: EhPageTranslation.Patch.bitmapInfo.rawValue
            ) else { return false }
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return isDrawn ? pixels : nil
    }
}
