import EhModels
import SwiftUI

// The density's controls besides the pinch (`wall.md` section 3): its three choices in the More
// menu, and the capsule that names the columns after a change.

/// The three densities in the More menu, for people who cannot pinch (`wall.md` section 3).
struct WallDensityMenu: View {
    let density: WallDensity
    let choose: (WallDensity) -> Void

    var body: some View {
        Picker(selection: Binding(get: { density }, set: { choose($0) })) {
            ForEach(WallDensity.allCases, id: \.self) { density in
                Label(density.title, systemImage: density.systemImage).tag(density)
            }
        } label: {
            EmptyView()
        }
        .pickerStyle(.inline)
    }
}

extension WallDensity {
    var title: String {
        switch self {
        case .large: L10n.Localizable.List.Density.large
        case .medium: L10n.Localizable.List.Density.medium
        case .small: L10n.Localizable.List.Density.small
        }
    }

    var systemImage: String {
        switch self {
        case .large: "square.grid.2x2"
        case .medium: "square.grid.3x3"
        case .small: "square.grid.4x3.fill"
        }
    }

    /// One step towards larger covers (`+1`) or smaller ones (`-1`); `nil` at either end.
    func stepped(_ direction: Int) -> WallDensity? {
        switch (self, direction.signum()) {
        case (.small, 1): .medium
        case (.medium, 1): .large
        case (.large, -1): .medium
        case (.medium, -1): .small
        default: nil
        }
    }
}

/// What the capsule says after a density change: "2 columns · pinch for 3 or 5".
struct WallDensityHint: Equatable {
    let density: WallDensity
    let columns: Int
    /// The other two densities' columns, when the three differ.
    let others: [Int]
    /// Counts the changes, so that one made while the capsule shows starts its time again.
    let serial: Int

    init(density: WallDensity, columns: [WallDensity: Int], serial: Int) {
        self.density = density
        self.columns = columns[density] ?? 0
        let others = WallDensity.allCases.filter { $0 != density }.compactMap { columns[$0] }.sorted()
        // At an accessibility text size two densities share a column count: then the capsule
        // names the density instead.
        self.others = Set(others + [self.columns]).count == 3 ? others : []
        self.serial = serial
    }

    var title: String {
        others.isEmpty ? density.title : L10n.Localizable.List.Density.columns(columns)
    }

    var detail: String? {
        others.count == 2 ? L10n.Localizable.List.Density.hint(others[0], others[1]) : nil
    }

    var announcement: String {
        [title, detail].compactMap(\.self).joined(separator: ", ")
    }
}

/// The capsule at the top of the wall after a density change, for a second and a half. It
/// floats above the covers for a moment, so it is glass (`Design/designs/README.md`
/// section 13): one shape of its own, outside the scrolling content.
struct WallDensityHintView: View {
    let hint: WallDensityHint?

    @Environment(\.look) private var look
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let hint {
                HStack(spacing: 7) {
                    Image(systemName: hint.density.systemImage)
                        .foregroundStyle(look.secondaryLabel)
                    Text(hint.title)
                        .fontWeight(.semibold)
                        .foregroundStyle(look.label)
                    if let detail = hint.detail {
                        Text(verbatim: "· " + detail)
                            .foregroundStyle(look.secondaryLabel)
                    }
                }
                .font(.subheadline)
                .lineLimit(1)
                .padding(.leading, 12)
                .padding(.trailing, 15)
                .frame(minHeight: 38)
                .glassSurface(in: .capsule)
                .padding(.top, 8)
                .padding(.horizontal, 16)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
                // VoiceOver hears it once, as an announcement.
                .accessibilityHidden(true)
            }
        }
        .animation(.snappy(duration: 0.25), value: hint != nil)
        .allowsHitTesting(false)
    }
}
