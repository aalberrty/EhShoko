#if DEBUG || HARNESS
import SwiftUI

/// What a device shows between two recordings of a measuring session (`-Harness rest`): a
/// black screen with one dim line that keeps moving.
///
/// A session records on a phone nobody touches, and between recordings the Mac saves a trace
/// for a while. Left alone the phone would sit on its home screen at full brightness, which
/// is what burnt an OLED display once; locked, it would need its owner for the next
/// recording. So `Scripts/measure.sh rest` launches this instead: nearly every pixel is off,
/// the line is dim and never rests on the same pixels, and the screen stays awake (the gate
/// switches the idle timer off for every harness), so the next recording starts by itself.
///
/// `-HarnessRestLabel <text>` is the line's second half: what the session is doing.
struct HarnessRestView: View {
    private let label = UserDefaults.standard.string(forKey: "HarnessRestLabel") ?? ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            GeometryReader { proxy in
                let seconds = timeline.date.timeIntervalSinceReferenceDate
                Text(verbatim: label.isEmpty ? "EhShoko is being measured" : "EhShoko is being measured · \(label)")
                    .font(.footnote.monospaced())
                    .foregroundStyle(Color(white: 0.28))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: min(proxy.size.width - 48, 420))
                    .position(Self.position(at: seconds, in: proxy.size))
                    .animation(.linear(duration: 1), value: Int(seconds))
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
    }

    /// Two slow sweeps of unequal periods, so the line crosses the whole screen and takes
    /// hours to come back to a place.
    private static func position(at seconds: Double, in size: CGSize) -> CGPoint {
        func sweep(_ period: Double) -> Double {
            let phase = seconds.truncatingRemainder(dividingBy: period) / period
            return phase < 0.5 ? phase * 2 : 2 - phase * 2
        }
        let inset = CGSize(width: min(size.width / 2, 234), height: 60)
        return CGPoint(
            x: inset.width + (size.width - inset.width * 2) * sweep(97),
            y: inset.height + (size.height - inset.height * 2) * sweep(61)
        )
    }
}
#endif
