import SwiftUI

/// The accessory's trailing mark (`shelf.md` section 1): how far through the gallery the
/// reader is, as a 34 pt ring in the tint around a play symbol. Decorative: the accessory
/// reads the progress out itself.
struct TabsBarProgressRing: View {
    /// From 0 to 1.
    let fraction: Double

    @Environment(\.look) private var look
    @Environment(\.lookTint) private var tint

    private static var diameter: CGFloat { 34 }
    private static var lineWidth: CGFloat { 3 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(look.fill, lineWidth: Self.lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                // From twelve o'clock, clockwise.
                .rotationEffect(.degrees(-90))
            Image(systemName: "play.fill")
                .font(.caption)
                .foregroundStyle(look.label)
        }
        // The stroke is centred on its path: inset it so the ring is 34 pt over all.
        .padding(Self.lineWidth / 2)
        .frame(width: Self.diameter, height: Self.diameter)
        .accessibilityHidden(true)
    }
}
