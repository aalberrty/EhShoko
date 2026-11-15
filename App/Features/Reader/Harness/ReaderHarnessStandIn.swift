#if DEBUG || HARNESS
import SwiftUI

/// Stands in the slot after the last page until the closing page exists
/// (`ReaderClosingPage`, which replaces it in the reader and here). It has what the slot must
/// be shown to carry: controls that take their own taps, a height of its own for the vertical
/// strip, and no gesture on its background, so the engine's tap zones work on every empty part.
struct ReaderHarnessStandIn: View {
    let model: ReaderHarnessModel

    /// The controller the engine is handed for its slot.
    static func makeController(model: ReaderHarnessModel) -> UIViewController {
        let host = UIHostingController(rootView: ReaderHarnessStandIn(model: model))
        // A change of the column's ideal height reaches the engine, which measures it again.
        host.sizingOptions = .preferredContentSize
        host.view.backgroundColor = .clear
        return host
    }

    var body: some View {
        VStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 9)
                .fill(.tint.opacity(0.35))
                .frame(width: 84, height: 120)
            Text(verbatim: "THE END · \(model.galleryPageCount) PAGES")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(verbatim: "Stand-in for the closing page")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
            HStack(spacing: 10) {
                tile("Favourite", symbol: "heart")
                tile("Comments", symbol: "bubble.left")
                tile("Gallery", symbol: "doc.text")
            }
            Button {
                model.standInWasTapped("more")
            } label: {
                Text(verbatim: "More by this artist ›")
            }
            .accessibilityIdentifier("standin.more")
            Button {
                model.isStandInTall.toggle()
                model.standInWasTapped("height")
            } label: {
                Text(verbatim: model.isStandInTall ? "Shorter" : "Taller")
            }
            .accessibilityIdentifier("standin.height")
            Text(verbatim: taps)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            if model.isStandInTall {
                Color.clear.frame(height: 240)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: 420)
        // The column's own height is what the strip is told; the slot is filled around it.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }

    private var taps: String {
        let counts = model.standInTaps.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }
        return counts.isEmpty ? "no taps yet" : counts.joined(separator: " · ")
    }

    private func tile(_ title: String, symbol: String) -> some View {
        Button {
            model.standInWasTapped(title.lowercased())
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                Text(verbatim: title).font(.caption)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("standin.\(title.lowercased())")
    }
}
#endif
