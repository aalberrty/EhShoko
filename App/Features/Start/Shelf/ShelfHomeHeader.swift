import EhFeatures
import EhModels
import SwiftUI

/// Everything above the Front Page's rows (`shelf.md` section 2): the date over "Home", the
/// Continue shelf, the Popular shelf and the Front Page's heading. It draws no background, so
/// it sits on whatever ground the list part gives its rows.
///
/// Each section reads only the model properties it renders, so a page turned in the reader
/// redraws the Continue shelf and nothing else.
struct ShelfHomeHeader: View {
    let popular: HomeModel
    let actions: ShelfHomeActions

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let margins = ShelfHomeMargins(sizeClass)
        VStack(alignment: .leading, spacing: 0) {
            ShelfHomeTitle()
                .padding(.horizontal, margins.leading)
                .padding(.bottom, 8)
            ShelfContinueSection(margins: margins, open: actions.openReader, openHistory: actions.openHistory)
            ShelfPopularSection(model: popular, margins: margins, open: actions.openGallery, showAll: actions.showPopular)
            ShelfFrontPageHeading(margins: margins)
                .padding(.top, ShelfHomeHeading.spaceAbove)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The header's side margins: 20 pt on a phone, 28 pt on regular width. Headings keep a little
/// less at the trailing edge, where their link's own padding sits.
struct ShelfHomeMargins: Equatable {
    let leading: CGFloat
    let trailing: CGFloat

    init(_ sizeClass: UserInterfaceSizeClass?) {
        leading = sizeClass == .regular ? 28 : 20
        trailing = sizeClass == .regular ? 28 : 16
    }
}

// MARK: Title

/// The date in small capitals over "Home". The date follows midnight while the screen is up.
struct ShelfHomeTitle: View {
    @Environment(\.look) private var look
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TimelineView(ShelfMidnightSchedule()) { context in
                Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.footnote.weight(.semibold))
                    .tracking(0.3)
                    .textCase(.uppercase)
                    .foregroundStyle(look.secondaryLabel)
            }
            Text(L10n.Localizable.HomeView.Title.home)
                .font(.largeTitle.bold())
                .foregroundStyle(look.label)
                // The navigation bar keeps "Home" as the screen's title (`hiddenBarTitle`) and
                // VoiceOver reads it there, as a heading: read here too, it came twice.
                .accessibilityHidden(true)
        }
        // At the accessibility sizes the date and "Home" wrap rather than end in "…".
        .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
        .minimumScaleFactor(0.8)
    }
}

/// Each midnight from the start: the only moments the date line changes.
private nonisolated struct ShelfMidnightSchedule: TimelineSchedule {
    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(upcoming: startDate)
    }

    struct Entries: Sequence, IteratorProtocol {
        var upcoming: Date?

        mutating func next() -> Date? {
            guard let current = upcoming else { return nil }
            upcoming = Calendar.current.nextDate(
                after: current, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime
            )
            return current
        }
    }
}

// MARK: Headings

/// "Front Page" with the filter summary pill trailing, where the bar does not hold the filter
/// (`shelf.md` section 2, item 4): the list's wrapper hands the header the list's control. It
/// opens Filters on the Front Page's set.
private struct ShelfFrontPageHeading: View {
    let margins: ShelfHomeMargins

    @Environment(\.listHeadingControl) private var control
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacks = typeSize.isAccessibilitySize
        let layout = ShelfHomeHeading.layout(stacks: stacks)
        layout {
            Text(GalleryListKind.frontpage.title)
                .lookSectionHeader()
                .lineLimit(stacks ? 2 : 1)
            if !stacks { Spacer(minLength: 0) }
            if let control, case .filter(let summary) = control.control {
                ShelfListFilterPill(summary: summary) { control.perform(.filters) }
                    .layoutPriority(1)
            }
        }
        .frame(minHeight: 44)
        .padding(.leading, margins.leading)
        .padding(.trailing, margins.trailing)
    }
}

/// A section's heading line: the title in the look's section style and, trailing, a link in
/// the tint ("History ›", "See all ›"). The line is 44 pt high, the link's target.
struct ShelfHomeHeading: View {
    let title: String
    var link: String?
    var action: () -> Void = {}
    let margins: ShelfHomeMargins

    /// The space above a heading that follows a shelf: the drawn 18 pt, less what the 44 pt
    /// line adds above a 30 pt one.
    static let spaceAbove: CGFloat = 11

    @Environment(\.dynamicTypeSize) private var typeSize

    /// A heading's line: the title and what trails it side by side or, at the accessibility
    /// sizes, where side by side would cut both to a word, the second under the first.
    static func layout(stacks: Bool) -> AnyLayout {
        stacks
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
    }

    var body: some View {
        let stacks = typeSize.isAccessibilitySize
        let layout = Self.layout(stacks: stacks)
        layout {
            Text(title)
                .lookSectionHeader()
                .lineLimit(stacks ? 2 : 1)
            if !stacks { Spacer(minLength: 0) }
            if let link {
                Button(action: action) {
                    HStack(spacing: 2) {
                        Text(link)
                        Image(systemName: "chevron.forward")
                            .imageScale(.small)
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .padding(.leading, stacks ? 0 : 8)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                // In a list row only this button takes the tap, not the whole row.
                .buttonStyle(.borderless)
            }
        }
        .frame(minHeight: 44)
        .padding(.leading, margins.leading)
        .padding(.trailing, margins.trailing)
    }
}
