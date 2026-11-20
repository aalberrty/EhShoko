/// Where each patch goes in a page's atlas: shelves of patches, tallest first, in an atlas about
/// as wide as it is tall. A page's patches are a few dozen rectangles at most, so this simple
/// packing leaves little empty space, and the PNG encoder spends almost nothing on what is left.
struct AtlasLayout: Equatable {
    /// Transparent pixels between patches.
    static let gutter = 1

    let width: Int
    let height: Int
    /// The top-left corner of each patch, in the order of `sizes`.
    let origins: [Origin]

    struct Origin: Equatable {
        var x: Int
        var y: Int
    }

    init(sizes: [(width: Int, height: Int)]) {
        guard !sizes.isEmpty else {
            self.init(width: 0, height: 0, origins: [])
            return
        }
        let gutter = Self.gutter
        let area = sizes.reduce(0) { $0 + ($1.width + gutter) * ($1.height + gutter) }
        let widest = sizes.map(\.width).max() ?? 0
        let shelfWidth = max(widest, Int(Double(area).squareRoot().rounded(.up)))
        // Tallest first, then widest; ties keep the given order, so the layout is deterministic.
        let order = sizes.indices.sorted { lhs, rhs in
            let left = sizes[lhs], right = sizes[rhs]
            if left.height != right.height { return left.height > right.height }
            if left.width != right.width { return left.width > right.width }
            return lhs < rhs
        }
        var origins = [Origin](repeating: Origin(x: 0, y: 0), count: sizes.count)
        var x = 0, y = 0, shelfHeight = 0, usedWidth = 0
        for index in order {
            let size = sizes[index]
            if x > 0, x + size.width > shelfWidth {
                y += shelfHeight + gutter
                x = 0
                shelfHeight = 0
            }
            origins[index] = Origin(x: x, y: y)
            usedWidth = max(usedWidth, x + size.width)
            shelfHeight = max(shelfHeight, size.height)
            x += size.width + gutter
        }
        self.init(width: usedWidth, height: y + shelfHeight, origins: origins)
    }

    private init(width: Int, height: Int, origins: [Origin]) {
        self.width = width
        self.height = height
        self.origins = origins
    }
}
