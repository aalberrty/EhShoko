import EhCore
import EhFeatures
import EhModels
import SwiftUI

private typealias Offer = L10n.Localizable.Offer

/// The offer after install (`settings.md`, "The offer after install"): the wizard's first
/// step, lighter, offered once. A title and one sentence, then the stage playing the presets
/// in turn over its three tiles, Shelf selected because it is the default.
///
/// - Three ways out: "Use …" (the prominent button, named after the selected tile) and "Set
///   up step by step" in the sheet's bottom toolbar, "Not now" at the top trailing corner.
///   Swiping the sheet away is "Not now". The model decides what each does.
/// - It is built from `PresetStage` alone, which draws schematics: no part is created while
///   it shows. The stage has no glass around it (it brings its own pause button) and pauses
///   itself when it is not seen; the offer has no alert of its own that could cover it.
struct ExperienceOfferSheet: View {
    let model: ExperienceOfferModel

    @Environment(\.look) private var look
    @Environment(\.lookTint) private var tint

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Tokens.Spacing.large) {
                    heading
                    // Plays in turn until a tile is tapped: Shelf is selected because it is
                    // the default, not because it was chosen.
                    PresetStage(selection: selection, staysOnInitialSelection: false)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Tokens.Spacing.large)
                .padding(.bottom, Tokens.Spacing.xLarge)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(look.surface)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ExperienceOfferControls(model: model, tint: tint) }
        }
        .presentationDetents([.large])
        .onAppear {
            model.appeared()
            #if DEBUG || HARNESS
            ExperienceOfferProbe.shared.offerAppeared(model)
            #endif
        }
    }

    private var heading: some View {
        VStack(spacing: Tokens.Spacing.small) {
            Text(Offer.title)
                .font(.title.bold())
                .lookTitleDesign()
                .foregroundStyle(look.label)
                .accessibilityAddTraits(.isHeader)
            Text(Offer.body)
                .font(.subheadline)
                .foregroundStyle(look.secondaryLabel)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Tokens.Spacing.small)
        .padding(.top, Tokens.Spacing.small)
    }

    private var selection: Binding<DesignStyle?> {
        Binding(get: { model.selection }, set: { if let style = $0 { model.selection = style } })
    }
}

/// "Not now" at the top trailing corner; "Set up step by step" and the prominent "Use …" in
/// the sheet's bottom toolbar (glass on iOS 26, `README.md` section 13).
private struct ExperienceOfferControls: ToolbarContent {
    let model: ExperienceOfferModel
    /// Set on the prominent button: in a sheet it can lose the inherited tint (`spikes/S5.md`).
    let tint: Color

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(Offer.notNow) { model.notNow() }
        }
        ToolbarItem(placement: .bottomBar) {
            Button(L10n.Localizable.Settings.Design.setup) { model.setUp() }
        }
        BottomToolbarSpacer()
        ToolbarItem(placement: .bottomBar) {
            Button { model.use() } label: {
                Text(Offer.use(model.selection.localizedName))
                    .fontWeight(.semibold)
                    .padding(.horizontal, Tokens.Spacing.small)
            }
            .glassProminentButtonStyle()
            .tint(tint)
        }
    }
}
