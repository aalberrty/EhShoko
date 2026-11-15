import EhFeatures
import SwiftUI

/// "Search titles for “gla”" (Shelf's first suggestion row): submits the field as typed.
///
/// The one view that reads what is typed (`spikes/S6.md` section 9): nothing else in a
/// design's bar, list or body reads `model.text`, so a keystroke redraws this row alone. It
/// shows nothing while the text is empty.
struct SearchTitlesButton: View {
    let model: SearchSurfaceModel

    @Environment(\.searchFieldController) private var field

    var body: some View {
        let text = model.text.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty {
            Button {
                field.submit()
            } label: {
                Label(L10n.Localizable.Search.titlesFor(text), systemImage: "text.magnifyingglass")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
        }
    }
}
