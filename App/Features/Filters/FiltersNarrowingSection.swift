import EhFeatures
import EhModels
import SwiftUI

/// The card under the categories, headed "Narrow down": the advanced switch, the minimum
/// rating as stars, the page range in two boxes, and a row that pushes the other advanced
/// options with how many differ from their defaults. The footer says each range keeps its own
/// filter and that changes apply at once.
///
/// The site applies all of these only while advanced settings are on, so each row below the
/// switch is disabled while it is off, and the rating and the range each keep their own switch
/// (`Filter.minRatingActivated`, `pageRangeActivated`), as on the site's form.
struct FiltersNarrowingSection: View {
    @Bindable var model: FiltersModel
    var focusedBound: FocusState<FiltersModel.Bound?>.Binding

    var body: some View {
        Section {
            Toggle(L10n.Localizable.FiltersView.Title.advancedSettings, isOn: $model.filter.advanced)
                .lookFormRow()
            Group {
                Toggle(L10n.Localizable.FiltersView.Title.setMinimumRating, isOn: $model.filter.minRatingActivated)
                    .lookFormRow()
                FiltersRatingRow(rating: $model.filter.minRating)
                    .lookFormRow()
                    .disabled(!model.filter.minRatingActivated)
                Toggle(L10n.Localizable.FiltersView.Title.setPagesRange, isOn: $model.filter.pageRangeActivated)
                    .lookFormRow()
                    .disabled(model.isPageRangeToggleDisabled)
                FiltersPagesRow(model: model, focusedBound: focusedBound)
                    .lookFormRow()
                    .disabled(!model.filter.pageRangeActivated)
                NavigationLink {
                    FiltersAdvancedScreen(model: model)
                } label: {
                    FiltersAdvancedLabel(changed: FilterSummary(model.filter).advancedOptionCount)
                }
                .lookFormRow(.labelDimmedBySystem)
            }
            .disabled(!model.filter.advanced)
        } header: {
            Text(L10n.Localizable.FiltersView.Section.Title.narrowDown)
        } footer: {
            Text(L10n.Localizable.FiltersView.Section.Footer.separateFilters)
        }
    }
}

/// "Minimum rating" and five stars; the site takes two to five.
private struct FiltersRatingRow: View {
    @Binding var rating: Int

    var body: some View {
        LabeledContent {
            FiltersStarPicker(rating: $rating)
        } label: {
            Text(L10n.Localizable.FiltersView.Title.minimumRating)
        }
    }
}

/// Five stars in the look's rating colour; a tap on a star sets the minimum to it. The first
/// star is part of every choice, because the site's lowest minimum is two. VoiceOver reads one
/// adjustable control.
private struct FiltersStarPicker: View {
    @Binding var rating: Int

    @Environment(\.look) private var look
    @Environment(\.isEnabled) private var isEnabled

    private static let choices = 2...5

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    rating = max(star, Self.choices.lowerBound)
                } label: {
                    Image(systemName: "star.fill")
                        .foregroundStyle(star <= rating ? look.rating : look.fill)
                }
                .buttonStyle(.borderless)
            }
        }
        .font(.title2)
        .opacity(isEnabled ? 1 : 0.4)
        .sensoryFeedback(.selection, trigger: rating)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.Localizable.FiltersView.Title.minimumRating)
        .accessibilityValue(L10n.Localizable.Common.Value.stars("\(rating)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: rating = min(rating + 1, Self.choices.upperBound)
            case .decrement: rating = max(rating - 1, Self.choices.lowerBound)
            @unknown default: break
            }
        }
    }
}

/// "Pages" and the two bounds, "20 to Any". Return in the first moves to the second.
private struct FiltersPagesRow: View {
    @Bindable var model: FiltersModel
    var focusedBound: FocusState<FiltersModel.Bound?>.Binding

    @Environment(\.look) private var look

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                FiltersBoundField(text: $model.filter.pageLowerBound)
                    .focused(focusedBound, equals: .lower)
                    .submitLabel(.next)
                Text(L10n.Localizable.FiltersView.Title.pagesSeparator)
                    .foregroundStyle(look.secondaryLabel)
                FiltersBoundField(text: $model.filter.pageUpperBound)
                    .focused(focusedBound, equals: .upper)
                    .submitLabel(.done)
            }
        } label: {
            // "Pages", as drawn; the switch above says what the boxes limit.
            Text(L10n.Localizable.Gallery.Figure.pages)
        }
        .onSubmit { model.submitBound() }
    }
}

/// A page bound in a box on the look's fill; an empty bound reads "Any".
private struct FiltersBoundField: View {
    @Binding var text: String

    @Environment(\.look) private var look
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .callout) private var width: CGFloat = 64
    @ScaledMetric(relativeTo: .callout) private var height: CGFloat = 34

    var body: some View {
        TextField(text: $text) {
            Text(L10n.Localizable.FiltersView.Title.any)
        }
        .font(.callout.weight(.semibold).monospacedDigit())
        .foregroundStyle(isEnabled ? look.label : look.tertiaryLabel)
        .keyboardType(.numbersAndPunctuation)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .multilineTextAlignment(.center)
        .frame(width: width, height: height)
        .background(look.fill3, in: .rect(cornerRadius: 10, style: .continuous))
    }
}

/// "Advanced", with "3 on" for the options that differ from their defaults when there are any.
private struct FiltersAdvancedLabel: View {
    let changed: Int

    @Environment(\.look) private var look

    var body: some View {
        LabeledContent {
            if changed > 0 {
                Text(L10n.Localizable.FiltersView.Title.optionsOn(changed))
                    .foregroundStyle(look.secondaryLabel)
            }
        } label: {
            Text(L10n.Localizable.FiltersView.Section.Title.advanced)
        }
    }
}
