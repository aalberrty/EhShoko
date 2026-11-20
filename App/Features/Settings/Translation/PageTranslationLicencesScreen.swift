import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// Settings › Translation › Models and licences (`README.md` section 15.4): for every model of
/// the catalog its name, author, source, licence (opening its full text), what this project
/// changed and whether it is for non-commercial use only; then the notices of llama.cpp and of
/// the three fonts translated pages are lettered in, which their licences ask to go with every
/// copy. Names, authors and legal texts are data and are not translated; the labels are.
struct PageTranslationLicencesScreen: View {
    @Bindable var model: PageTranslationSettingsModel

    var body: some View {
        List {
            ForEach(model.credits) { credit in
                CreditSection(credit: credit) {
                    Task { await model.showLicence(of: credit.id) }
                }
            }
            ForEach(model.notices) { notice in
                NoticeSection(notice: notice)
            }
        }
        .settingsFormStyle()
        .navigationTitle(L10n.Localizable.Settings.Translation.licences)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $model.licence) { licence in
            LicenceSheet(licence: licence)
        }
        .task { await model.loadNotices() }
    }
}

/// One model's credits. Long texts wrap: a licence can be a sentence, an author ten names.
private struct CreditSection: View {
    let credit: PageTranslationModelCredit
    let showLicenceFile: () -> Void

    @Environment(\.look) private var look

    private typealias Credit = L10n.Localizable.Settings.Translation.Credit

    var body: some View {
        let details = credit.credit
        Section {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxSmall) {
                Text(verbatim: details.name)
                    .font(.headline)
                    .foregroundStyle(look.label)
                if let role = credit.choice?.role {
                    Text(role.title)
                        .font(.footnote)
                        .foregroundStyle(look.secondaryLabel)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            CreditLine(label: Credit.author, value: details.author)
            Link(destination: details.source) {
                CreditLine(label: Credit.source, value: details.source.absoluteString, isLink: true)
            }
            licenceRow(details)
            if let changes = details.changes {
                CreditLine(label: Credit.changes, value: changes)
            }
            if details.nonCommercial {
                Label(Credit.nc, systemImage: "exclamationmark.circle")
                    .foregroundStyle(look.label)
            }
        }
        .settingsRow()
    }

    /// The licence's name, opening its full text: the file that came with the model when it
    /// is installed, else the licence's own page.
    @ViewBuilder
    private func licenceRow(_ details: ArtifactCredit) -> some View {
        if credit.hasLicenceFile {
            Button(action: showLicenceFile) {
                CreditLine(label: Credit.licence, value: details.licence, isLink: true)
            }
        } else {
            Link(destination: details.licenceText) {
                CreditLine(label: Credit.licence, value: details.licence, isLink: true)
            }
        }
    }
}

/// A label over a value that wraps.
private struct CreditLine: View {
    let label: String
    let value: String
    var isLink = false

    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxSmall) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(look.secondaryLabel)
            Text(verbatim: value)
                .foregroundStyle(isLink ? AnyShapeStyle(.tint) : AnyShapeStyle(look.label))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A library's or a font's notice, which its licence asks to go with every copy of the app.
private struct NoticeSection: View {
    let notice: PageTranslationNotice

    @Environment(\.look) private var look

    var body: some View {
        Section {
            Text(verbatim: notice.name)
                .font(.headline)
                .foregroundStyle(look.label)
                .accessibilityAddTraits(.isHeader)
            if let copyright = notice.copyright {
                Text(verbatim: copyright)
                    .font(.footnote)
                    .foregroundStyle(look.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let source = notice.source {
                Link(destination: source) {
                    CreditLine(
                        label: L10n.Localizable.Settings.Translation.Credit.source, value: source.absoluteString,
                        isLink: true
                    )
                }
            }
            Text(verbatim: notice.text)
                .font(.caption.monospaced())
                .foregroundStyle(look.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .settingsRow()
    }
}

/// A licence's full text, from the file beside its model.
private struct LicenceSheet: View {
    let licence: LicenceText

    @Environment(\.dismiss) private var dismiss
    @Environment(\.look) private var look

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(verbatim: licence.text)
                    .font(.footnote.monospaced())
                    .foregroundStyle(look.label)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(look.surface)
            .navigationTitle(Text(verbatim: licence.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    SheetConfirmButton { dismiss() }
                }
            }
        }
    }
}
