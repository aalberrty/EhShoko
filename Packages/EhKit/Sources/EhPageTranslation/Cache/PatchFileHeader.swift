import Foundation

/// The layout header at the start of a patch file: little-endian 32-bit fields.
///
/// ```
/// "EhPT"  format version  patch count  PNG length
/// image width  image height  atlas width  atlas height
/// for each patch: page x, page y, width, height, atlas x, atlas y
/// ```
///
/// The PNG of the atlas follows it, and ends the file: a file cut short is told by its length,
/// since an image decoder may decode a cut PNG without an error.
struct PatchFileHeader: Equatable {
    static let magic: [UInt8] = Array("EhPT".utf8)
    /// Raise it when the layout changes: files of another version are unreadable, so their pages
    /// are drawn again.
    static let formatVersion: UInt32 = 1
    static let fixedLength = 32
    static let placementLength = 24
    /// More than any page has; a damaged count cannot make the reader allocate much.
    static let maximumPatchCount = 10_000
    /// The largest atlas a page can need: every pixel of a page at the 4-megapixel cap, with room
    /// for the gutters.
    static let maximumAtlasPixelCount = 16_000_000

    var imageWidth: Int
    var imageHeight: Int
    var atlasWidth: Int
    var atlasHeight: Int
    var placements: [PatchFile.Placement]
    /// The length of the PNG that follows; 0 when there are no patches.
    var pngLength: Int

    var length: Int { Self.fixedLength + placements.count * Self.placementLength }

    init(
        imageWidth: Int, imageHeight: Int, atlasWidth: Int, atlasHeight: Int,
        placements: [PatchFile.Placement], pngLength: Int
    ) {
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.atlasWidth = atlasWidth
        self.atlasHeight = atlasHeight
        self.placements = placements
        self.pngLength = pngLength
    }

    func encoded() -> Data {
        var data = Data(Self.magic)
        data.reserveCapacity(length)
        func append(_ value: Int) {
            withUnsafeBytes(of: UInt32(clamping: value).littleEndian) { data.append(contentsOf: $0) }
        }
        append(Int(Self.formatVersion))
        append(placements.count)
        append(pngLength)
        [imageWidth, imageHeight, atlasWidth, atlasHeight].forEach(append)
        for placement in placements {
            let page = placement.pageRect, atlas = placement.atlasRect
            [page.x0, page.y0, page.width, page.height, atlas.x0, atlas.y0].forEach(append)
        }
        return data
    }

    /// Reads the header at the start of `data` and checks that it describes a page this build
    /// can show: the file's length, every patch on the page and in the atlas, and sizes within
    /// bounds.
    init(decoding data: Data) throws(PatchFileError) {
        let fields: [Int]? = data.withUnsafeBytes { raw in
            guard raw.count >= Self.fixedLength, raw.prefix(4).elementsEqual(Self.magic) else { return nil }
            func field(_ index: Int) -> Int {
                Int(UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: 4 + index * 4, as: UInt32.self)))
            }
            let count = field(1), pngLength = field(2)
            guard field(0) == Self.formatVersion, count <= Self.maximumPatchCount,
                  raw.count == Self.fixedLength + count * Self.placementLength + pngLength
            else { return nil }
            return (0..<(7 + count * 6)).map(field)
        }
        guard let fields else { throw .unreadable }
        pngLength = fields[2]
        imageWidth = fields[3]
        imageHeight = fields[4]
        atlasWidth = fields[5]
        atlasHeight = fields[6]
        placements = stride(from: 7, to: fields.count, by: 6).map { start in
            let width = fields[start + 2], height = fields[start + 3]
            return PatchFile.Placement(
                pageRect: PixelRect(x: fields[start], y: fields[start + 1], width: width, height: height),
                atlasRect: PixelRect(x: fields[start + 4], y: fields[start + 5], width: width, height: height)
            )
        }
        guard isValid else { throw .unreadable }
    }

    private var isValid: Bool {
        let page = PixelRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
        let atlas = PixelRect(x: 0, y: 0, width: atlasWidth, height: atlasHeight)
        guard !page.isEmpty, placements.isEmpty == (pngLength == 0) else { return false }
        if placements.isEmpty { return true }
        return !atlas.isEmpty && atlas.area <= Self.maximumAtlasPixelCount && placements.allSatisfy { placement in
            !placement.pageRect.isEmpty
                && placement.pageRect.intersection(page) == placement.pageRect
                && placement.atlasRect.intersection(atlas) == placement.atlasRect
        }
    }
}
