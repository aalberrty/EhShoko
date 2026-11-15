import SwiftUI

/// The ring in the tint and the check around a selected preview (a preset tile, an option
/// card's picture in the wizard's tiles). It follows the preview's rounded corners and sits
/// just outside it, so the drawing is never covered.
struct SelectionRing: View {
    let isSelected: Bool
    /// The preview's width, which sets its corner radius.
    let width: CGFloat
    var showsCheck = true

    @Environment(\.look) private var look
    @Environment(\.onTint) private var onTint

    private static let gap: CGFloat = 2
    private static let lineWidth: CGFloat = 2.5

    var body: some View {
        let outset = Self.gap + Self.lineWidth
        let radius = width * SchematicRenderer.cornerRadius / SchematicRenderer.gridWidth + outset
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(.tint, lineWidth: Self.lineWidth)
            .padding(-outset)
            .overlay(alignment: .topTrailing) {
                if showsCheck {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(onTint, .tint)
                        .background(Circle().fill(look.raised).padding(-1.5))
                        .offset(x: 8, y: -8)
                }
            }
            .opacity(isSelected ? 1 : 0)
            .accessibilityHidden(true)
    }
}
