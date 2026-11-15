import EhFeatures
import SwiftUI

/// What Shelf's list puts around its rows (`shelf.md` section 3, `Design/designs/README.md`
/// section 5.3): the title, unless a first screen draws it; the More menu with every list
/// control, always, in the top bar; Toplists' "Page 1" menu beside it and its period control
/// pinned under the title; and the find field when "Find in this list" is on.
///
/// The bars and their controls are the system's (`README.md` section 13): toolbar items, a
/// segmented control in a top bar. The list draws no bottom bar.
struct ShelfListChrome: ViewModifier {
    let input: ListDesignInput
    /// The list's width, for the period control's form.
    let width: CGFloat

    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        let menu = input.controls.menu
        content
            .listFindBar(isPresented: isFinding, text: findText)
            // Above the find field: the period control belongs to the title.
            .topBar(isPresented: menu.period != nil, spacing: 0) {
                if let period = menu.period {
                    ShelfListPeriodBar(period: period, usesChips: usesChips, perform: input.perform)
                }
            }
            .toolbar {
                if let page = menu.page {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShelfListPageMenu(page: page, perform: input.perform)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ListMoreMenu(controls: menu, perform: input.perform)
                }
            }
            .modifier(ShelfListTitle(context: input.context))
    }

    /// At accessibility sizes or under 380 pt, five segments do not fit: a row of chips.
    private var usesChips: Bool {
        typeSize.isAccessibilitySize || (width > 0 && width < 380)
    }

    private var isFinding: Binding<Bool> {
        Binding(
            get: { input.controls.isFinding },
            set: { isFinding in
                // The list toggles it, and clears the text when it closes.
                if isFinding != input.controls.isFinding { input.perform(.find) }
            }
        )
    }

    private var findText: Binding<String> {
        Binding(get: { input.feed.findText }, set: { input.feed.findText = $0 })
    }
}

/// The list's own title, unless it is embedded in a first screen or the library, which draw
/// theirs. Large and leading in the bar's own row, as the Library tab's: a large title below
/// the bar would sit under the period control's or the find field's scroll edge effect on
/// iOS 26 and be blurred by it.
private struct ShelfListTitle: ViewModifier {
    let context: ListContext

    func body(content: Content) -> some View {
        if context.embedsInStart {
            content
        } else {
            content
                .navigationTitle(context.title)
                .toolbarTitleDisplayMode(.inlineLarge)
        }
    }
}

/// Toplists' period: Popular and the four periods as a segmented control, or a scrolling row
/// of chips where the segments do not fit their names (at accessibility sizes, under about
/// 380 pt, and in languages with long period names).
struct ShelfListPeriodBar: View {
    let period: ListMenuPicker
    let usesChips: Bool
    let perform: (ListMenuAction) -> Void

    @Environment(\.look) private var look
    @Environment(\.onTint) private var onTint

    var body: some View {
        Group {
            if usesChips {
                chips
            } else {
                // The segments' ideal width is what their names need: when that does not fit,
                // the chips.
                ViewThatFits(in: .horizontal) {
                    segments
                        .frame(maxWidth: 560)
                        .padding(.horizontal, 16)
                    chips
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private var segments: some View {
        Picker(period.title, selection: selection) {
            ForEach(period.options) { option in
                Text(option.title).tag(option.id)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var selection: Binding<Int> {
        Binding(get: { period.selection ?? -1 }, set: { perform(.period($0)) })
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(period.options) { option in
                    let isSelected = option.id == period.selection
                    Button { perform(.period(option.id)) } label: {
                        Text(option.title)
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? onTint : look.label)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 34)
                            .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(look.fill3), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
    }
}

/// "Page 1 ⌄": where a paged list is, with Next, Previous and Jump to page (`shelf.md`
/// section 3). The same entries are in the More menu.
struct ShelfListPageMenu: View {
    let page: ListMenuPage
    let perform: (ListMenuAction) -> Void

    var body: some View {
        Menu {
            Section(L10n.Localizable.List.Page.menu(page.title, page.current, page.maximum)) {
                Button(L10n.Localizable.List.Page.next, systemImage: "chevron.forward") { perform(.nextPage) }
                    .disabled(page.current >= page.maximum)
                Button(L10n.Localizable.List.Page.previous, systemImage: "chevron.backward") { perform(.previousPage) }
                    .disabled(page.current <= 1)
                Button(L10n.Localizable.List.Page.jump, systemImage: "arrowshape.bounce.forward") { perform(.jumpToPage) }
                    .disabled(page.maximum <= 1)
            }
        } label: {
            HStack(spacing: 4) {
                Text(L10n.Localizable.List.Page.divider(page.current))
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
            }
            .fixedSize()
        }
        .accessibilityLabel(L10n.Localizable.List.Page.menu(page.title, page.current, page.maximum))
    }
}
