import EhFeatures
import EhModels
import SwiftUI

/// Settings › Translation › one kind of model (`README.md` section 9.2): a card for every
/// choice of the catalog with what was measured for it, and what the figures were measured
/// on. A tap applies an installed model at once; a missing one downloads and applies when it
/// is installed. A choice this user's sources cannot provide is listed and cannot be chosen.
struct PageTranslationChoicesScreen: View {
    let model: PageTranslationSettingsModel
    let role: ModelRole

    @State private var choices = 0

    var body: some View {
        List {
            Section {
                ForEach(model.cards(for: role)) { card in
                    PageTranslationChoiceCardView(card: card) {
                        choices += 1
                        Task { await model.choose(card.choice) }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                }
            } footer: {
                Text(L10n.Localizable.Settings.Translation.Measured.footer(
                    PageTranslationMeasurements.testPageCount, PageTranslationMeasurements.phoneName
                ))
                .settingsFootnote()
            }
        }
        .settingsFormStyle()
        .navigationTitle(role.title)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: choices)
        #if DEBUG
        .pageTranslationScriptedScroll()
        #endif
    }
}

/// The screens pushed from Settings › Translation, with its model.
struct PageTranslationChildScreen: View {
    let route: PageTranslationChildRoute

    var body: some View {
        switch route.destination {
        case .choices(let role): PageTranslationChoicesScreen(model: route.parent, role: role)
        case .licences: PageTranslationLicencesScreen(model: route.parent)
        }
    }
}
