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
            ShelfHomeHeading(title: GalleryListKind.frontpage.title, margins: margins)
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
                .accessibilityAddTraits(.isHeader)
        }
        .lineLimit(1)
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

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .lookSectionHeader()
                .lineLimit(1)
            Spacer(minLength: 0)
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
                    .padding(.leading, 8)
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
