import EhFeatures
import SwiftUI

/// The command bar's centre capsule: a magnifier and the prompt for where the search looks,
/// or the keyword of the results on screen. It is a button: the search surface opens over
/// the screen, on the field's scope (`wall.md` section 1).
struct CommandBarSearchField: View {
    let field: CommandBarField
    let open: () -> Void

    /// Room for the magnifier and "Search": what the field keeps when the place's name
    /// takes the rest.
    @ScaledMetric(relativeTo: .body) private var minimumWidth: CGFloat = 112
    @Environment(\.look) private var look

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(look.secondaryLabel)
                text
            }
            .font(.body)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minWidth: minimumWidth, maxWidth: .infinity, minHeight: ActionDock.height, alignment: .leading)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .chromeShape(.centre, in: .capsule)
        .accessibilityLabel(field.prompt.text)
        .accessibilityValue(field.keyword ?? "")
        .accessibilityShowsLargeContentViewer {
            Label(field.keyword ?? field.prompt.text, systemImage: "magnifyingglass")
        }
    }

    @ViewBuilder
    private var text: some View {
        if let keyword = field.keyword {
            Text(keyword)
                .lookSyntaxDesign()
                .foregroundStyle(look.label)
                .truncationMode(.tail)
        } else if let short = field.prompt.shortText {
            ViewThatFits(in: .horizontal) {
                Text(field.prompt.text)
                Text(short)
            }
            .foregroundStyle(look.secondaryLabel)
        } else {
            Text(field.prompt.text)
                .foregroundStyle(look.secondaryLabel)
        }
    }
}

/// The command bar's trailing circle: what the top screen put there. A list's filter, with
/// a dot while the filter narrows something; its sort or, on a list with neither, its More
/// menu; the paste button of Ledger's Index.
struct CommandBarTrailingControl: View {
    let control: BarControl
    let perform: (BarAction) -> Void

    var body: some View {
        Group {
            switch control {
            case .button(let systemImage, _, let narrowing):
                Button { perform(.primary) } label: {
                    CommandBarSymbol(systemImage: systemImage, showsDot: narrowing != nil)
                }
                // The dot's meaning, which VoiceOver cannot see: "8 of 10 categories · ★ 3+".
                .accessibilityValue(narrowing ?? "")
            case .menu(let systemImage, _, let controls):
                Menu {
                    ListMenuEntries(controls: controls) { perform(.menu($0)) }
                } label: {
                    CommandBarSymbol(systemImage: systemImage, showsDot: false)
                }
                // Upward from the bar: the first control nearest the thumb, and what clears
                // a list at the far end.
                .menuOrder(.priority)
            }
        }
        .buttonStyle(.plain)
        .chromeShape(.trailing, in: .circle)
        .accessibilityLabel(title)
        .accessibilityShowsLargeContentViewer {
            Label(title, systemImage: systemImage)
        }
    }

    private var title: String {
        switch control {
        case .button(_, let title, _), .menu(_, let title, _): title
        }
    }

    private var systemImage: String {
        switch control {
        case .button(let systemImage, _, _), .menu(let systemImage, _, _): systemImage
        }
    }
}

private struct CommandBarSymbol: View {
    let systemImage: String
    let showsDot: Bool

    @Environment(\.look) private var look

    var body: some View {
        Image(systemName: systemImage)
            .font(.title3)
            .foregroundStyle(look.label)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: ActionDock.height, height: ActionDock.height)
            .overlay(alignment: .topTrailing) {
                if showsDot {
                    Circle()
                        .fill(.orange)
                        .frame(width: 9, height: 9)
                        .padding(11)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(.circle)
    }
}
