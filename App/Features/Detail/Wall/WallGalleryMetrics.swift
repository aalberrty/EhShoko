import SwiftUI

/// The card's measures (`wall.md` section 4). Pushed or in the gallery sheet it is the card as
/// drawn for a phone; in the side pane it is the smaller card of the iPad drawing, on the
/// look's surface.
///
/// The drawing counts from the top of a phone with a 54 pt status bar: the cover 70 pt down,
/// the panel 318. The page counts from the bottom edge of its top bar instead, which every
/// surrounding has and which sits 106 pt down on that phone, so the cover keeps its place
/// beside the bar's buttons on any device, in the pane and in a sheet, with nothing measured.
nonisolated struct WallGalleryMetrics: Equatable, Sendable {
    /// In the side pane: the panel is on the surface, and fills that sit on it are the
    /// look's faintest fill.
    let isPane: Bool
    /// How far the backdrop's colours reach down from the top edge.
    let backdropHeight: CGFloat
    let coverSize: CGSize
    /// How far the cover's top is above the bottom of the top bar.
    let coverLift: CGFloat
    /// From the cover's bottom to the panel's top.
    let panelGap: CGFloat
    let panelCorner: CGFloat
    /// The panel's side margins.
    let margin: CGFloat
    let showsGrabber: Bool

    /// - Parameter isShort: a compact height (a phone on its side), where the top bar is
    ///   lower than the lift the drawing gives the cover.
    init(isPane: Bool, isShort: Bool) {
        self.isPane = isPane
        if isPane {
            backdropHeight = 300
            coverSize = CGSize(width: 140, height: 200)
            panelGap = 12
            panelCorner = 26
            margin = 18
        } else {
            backdropHeight = 400
            coverSize = CGSize(width: 160, height: 229)
            panelGap = 19
            panelCorner = 32
            margin = 20
        }
        coverLift = isShort ? 20 : 36
        showsGrabber = !isPane
    }

    /// The widest the panel's content is laid out.
    static let readableWidth: CGFloat = 640

    /// The clear stretch at the top of the scrolling content, through which the cover shows:
    /// the panel starts below it and scrolls up over the cover.
    var panelInset: CGFloat {
        coverSize.height - coverLift + panelGap
    }

    /// The title: 23 pt bold as drawn for a phone, 20 in the pane.
    var titleFont: Font {
        isPane ? .title3.bold() : .title2.bold()
    }

    /// What the card stands on: the look's background, or its surface in the pane.
    func ground(_ look: Look) -> Color {
        isPane ? look.surface : look.background
    }

    /// The fill of what sits on the panel: round actions, chips, blocks.
    func fill(_ look: Look) -> Color {
        isPane ? look.fill3 : look.surface
    }
}
