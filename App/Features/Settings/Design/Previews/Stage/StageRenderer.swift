import EhCore
import EhModels
import os
import SwiftUI

/// The three presets' palettes, each drawn in its own look as a preset tile is, resolved once
/// on the main actor and handed to the canvas.
nonisolated struct StagePalettes: Equatable, Sendable {
    let shelf: SchematicPalette
    let wall: SchematicPalette
    let ledger: SchematicPalette

    subscript(style: DesignStyle) -> SchematicPalette {
        switch style {
        case .shelf: shelf
        case .wall: wall
        case .ledger: ledger
        }
    }
}

extension StagePalettes {
    init(accent: RGBColor, colorScheme: ColorScheme, contrast: ColorSchemeContrast) {
        func palette(_ style: DesignStyle) -> SchematicPalette {
            let look = Look(style)
            let tint = look.tint(for: accent)
            return SchematicPalette(
                look: look, accent: tint.tint, onAccent: tint.onTint, colorScheme: colorScheme, contrast: contrast
            )
        }
        self.init(shelf: palette(.shelf), wall: palette(.wall), ledger: palette(.ledger))
    }
}

/// Draws a frame of the stage: pure, and called by an asynchronous canvas off the main thread.
///
/// Each scene is its storyboard's layers at the scene's time, bottom to top, then its
/// fingertips. A layer that is invisible, off the stage or under an opaque layer that covers
/// the stage is not drawn, and a list that scrolls draws only the rows that reach the stage.
/// A layer or scene part way through a fade is drawn into its own layer and faded as a whole,
/// as the generator's opacity on a group of shapes does.
nonisolated enum StageRenderer {
    /// The stage's corner radius in points (the generator's 16 px on a 150 px stage).
    static let cornerRadius: CGFloat = 16

    private static let signposter = OSSignposter(
        subsystem: PerformanceSignposts.subsystem, category: PerformanceSignposts.category
    )

    /// The canvas's renderer for `frame`. Made here, outside the main actor, so the closure is
    /// not isolated to it and can run where the asynchronous canvas runs it.
    static func renderer(
        _ frame: StageFrame, palettes: StagePalettes
    ) -> @Sendable (inout GraphicsContext, CGSize) -> Void {
        { context, size in render(frame, palettes: palettes, into: context, size: size) }
    }

    static func render(_ frame: StageFrame, palettes: StagePalettes, into context: GraphicsContext, size: CGSize) {
        guard size.width > 0, size.height > 0, let bottom = frame.scenes.first else { return }
        let interval = signposter.beginInterval("StageDraw")
        defer { signposter.endInterval("StageDraw", interval) }
        let unit = size.width / SchematicRenderer.gridWidth
        let stage = CGRect(x: 0, y: 0, width: SchematicRenderer.gridWidth, height: size.height / unit)
        let shape = SchematicCanvas.shape(stage, cornerRadius / unit)
        var grid = context
        grid.scaleBy(x: unit, y: unit)
        var clipped = grid
        clipped.clip(to: shape)
        clipped.fill(Path(stage), with: .color(palettes[bottom.style].background))
        for scene in frame.scenes {
            let palette = palettes[scene.style]
            if scene.opacity >= 0.999 {
                draw(scene, palette: palette, stage: stage, unit: unit, in: clipped)
            } else if scene.opacity > 0.001 {
                var faded = clipped
                faded.opacity = scene.opacity
                faded.drawLayer { layer in draw(scene, palette: palette, stage: stage, unit: unit, in: layer) }
            }
        }
        grid.stroke(
            SchematicCanvas.shape(stage.insetBy(dx: 0.25 / unit, dy: 0.25 / unit), cornerRadius / unit),
            with: .color(palettes[bottom.style].separator),
            lineWidth: 0.5 / unit
        )
    }

    private static func draw(
        _ scene: StageScene, palette: SchematicPalette, stage: CGRect, unit: CGFloat, in context: GraphicsContext
    ) {
        let storyboard = scene.storyboard
        let poses = storyboard.layers.map { $0.track.pose(at: scene.time) }
        // Nothing under the topmost layer that covers the stage can be seen.
        var lowest = 0
        for index in poses.indices.reversed() where covers(storyboard.layers[index], poses[index], stage) {
            lowest = index
            break
        }
        for index in lowest..<storyboard.layers.count {
            draw(storyboard.layers[index], pose: poses[index], palette: palette, stage: stage, unit: unit, in: context)
        }
        for fingertip in storyboard.fingertips where fingertip.isShown(at: scene.time) {
            StagePieces.fingertip(fingertip.track.pose(at: scene.time), in: context)
        }
    }

    private static func draw(
        _ layer: StageLayer, pose: LayerPose, palette: SchematicPalette, stage: CGRect, unit: CGFloat,
        in context: GraphicsContext
    ) {
        guard pose.opacity > 0.001, pose.scale > 0.001 else { return }
        let box = frame(of: layer, pose)
        guard box.intersects(stage) else { return }
        // The part of the box above the stage's bottom edge, in the box's units: a list that
        // scrolls stops its rows there.
        let origin = layer.transformOrigin
        let visibleHeight = origin.y + (stage.maxY - origin.y - pose.y) / pose.scale
        let height = min(layer.height, max(visibleHeight.rounded(.up), 0))
        let body = { (target: GraphicsContext) in
            var placed = target
            placed.translateBy(x: origin.x + pose.x, y: origin.y + pose.y)
            placed.scaleBy(x: pose.scale, y: pose.scale)
            placed.translateBy(x: -origin.x, y: -origin.y)
            if layer.fillsGround {
                placed.fill(Path(CGRect(x: 0, y: 0, width: SchematicRenderer.gridWidth, height: height)),
                            with: .color(palette.background))
            }
            let canvas = SchematicCanvas(context: placed, palette: palette, height: height, hairline: 0.5 / unit)
            StagePieces.draw(layer.drawing, in: canvas)
        }
        if pose.opacity >= 0.999 {
            body(context)
        } else {
            var faded = context
            faded.opacity = pose.opacity
            faded.drawLayer { body($0) }
        }
    }

    /// The layer's box on the stage at `pose`.
    private static func frame(of layer: StageLayer, _ pose: LayerPose) -> CGRect {
        let origin = layer.transformOrigin
        return CGRect(
            x: origin.x + pose.x - origin.x * pose.scale,
            y: origin.y + pose.y - origin.y * pose.scale,
            width: SchematicRenderer.gridWidth * pose.scale,
            height: layer.height * pose.scale
        )
    }

    private static func covers(_ layer: StageLayer, _ pose: LayerPose, _ stage: CGRect) -> Bool {
        layer.fillsGround && pose.opacity >= 0.999 && frame(of: layer, pose).contains(stage)
    }
}
