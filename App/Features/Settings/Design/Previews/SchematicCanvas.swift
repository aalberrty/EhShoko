import SwiftUI

/// What a schematic draws into: a `GraphicsContext` scaled so that one unit is a hundredth of
/// the preview's width (the grid of `tools/schematics.py`: 100 wide, 160 high), and the
/// palette.
///
/// Everything is a flat fill. Where the generator has a shadow, a drawing has a `drop`: a
/// flat, offset shape under the floating one. Blurs, materials and glass are never drawn.
nonisolated struct SchematicCanvas {
    var context: GraphicsContext
    let palette: SchematicPalette
    /// The height to fill, in grid units: 160 for a preview, more for a layer that scrolls.
    let height: CGFloat
    /// Half a point, in grid units.
    let hairline: CGFloat

    init(context: GraphicsContext, palette: SchematicPalette, height: CGFloat, hairline: CGFloat) {
        self.context = context
        self.palette = palette
        self.height = height
        self.hairline = hairline
    }

    // MARK: Shapes

    /// A filled rounded rectangle; the generator's `r`.
    func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color, _ radius: CGFloat = 1.2) {
        context.fill(Self.shape(CGRect(x: x, y: y, width: w, height: h), radius), with: .color(color))
    }

    /// A filled circle of diameter `d` whose bounding box starts at `x`, `y`; the generator's `c`.
    func circle(_ x: CGFloat, _ y: CGFloat, _ d: CGFloat, _ color: Color) {
        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: d, height: d)), with: .color(color))
    }

    /// A circle's outline drawn inside its bounds.
    func ring(_ x: CGFloat, _ y: CGFloat, _ d: CGFloat, _ color: Color, _ width: CGFloat = 1.2) {
        let rect = CGRect(x: x, y: y, width: d, height: d).insetBy(dx: width / 2, dy: width / 2)
        context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: width)
    }

    /// A box with a hairline inside its edge: a card on a ground of nearly its colour.
    func card(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color, _ radius: CGFloat) {
        box(x, y, w, h, color, radius)
        outline(x, y, w, h, radius, palette.separator, hairline)
    }

    /// An outline drawn inside the box's edge.
    func outline(
        _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat, _ color: Color, _ width: CGFloat
    ) {
        let rect = CGRect(x: x, y: y, width: w, height: h).insetBy(dx: width / 2, dy: width / 2)
        context.stroke(Self.shape(rect, max(radius - width / 2, 0)), with: .color(color), lineWidth: width)
    }

    /// A ruled line `w` long; the generator's 0.4-high separators.
    func rule(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat) {
        box(x, y, w, 0.4, palette.separator, 0)
    }

    /// A vertical ruled line.
    func ruleDown(_ x: CGFloat, _ y: CGFloat, _ h: CGFloat) {
        box(x, y, 0.4, h, palette.separator, 0)
    }

    /// A flat stand-in for a shadow: the shape again, `dy` lower and a little wider, in the
    /// palette's drop colour at `strength`.
    func drop(
        _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat, dy: CGFloat, strength: Double = 1
    ) {
        let spread: CGFloat = 0.5
        let rect = CGRect(x: x - spread, y: y + dy - spread, width: w + spread * 2, height: h + spread * 2)
        context.fill(Self.shape(rect, radius + spread), with: .color(palette.drop.opacity(strength)))
    }

    /// A floating bar or button: glass in the app, here a near-opaque fill with a hairline and
    /// a drop.
    func chrome(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat) {
        drop(x, y, w, h, radius, dy: 0.8, strength: 0.7)
        box(x, y, w, h, palette.chrome, radius)
        outline(x, y, w, h, radius, palette.separator, hairline)
    }

    /// The ground fading in under a bottom bar, from `top` to the bottom edge.
    func fade(from top: CGFloat) {
        let ground = palette.background
        let gradient = Gradient(stops: [
            .init(color: ground.opacity(0), location: 0),
            .init(color: ground, location: 0.7),
            .init(color: ground, location: 1),
        ])
        let rect = CGRect(x: 0, y: top, width: 100, height: height - top)
        context.fill(
            Path(rect),
            with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: height))
        )
    }

    /// Draws `body` with the canvas turned by `degrees` about the centre of `rect`.
    func rotated(_ degrees: Double, about rect: CGRect, _ body: (SchematicCanvas) -> Void) {
        var turned = self
        turned.context.translateBy(x: rect.midX, y: rect.midY)
        turned.context.rotate(by: .degrees(degrees))
        turned.context.translateBy(x: -rect.midX, y: -rect.midY)
        body(turned)
    }

    static func shape(_ rect: CGRect, _ radius: CGFloat) -> Path {
        radius > 0 ? Path(roundedRect: rect, cornerRadius: min(radius, rect.width / 2, rect.height / 2)) : Path(rect)
    }
}
