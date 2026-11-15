import Foundation
import SwiftUI

/// Settings › About: the project link, the version, thanks and the libraries in use, on the
/// look's colours.
/// Links open outside the app.
struct AboutScreen: View {
    @Environment(\.look) private var look

    var body: some View {
        Form {
            Section {
                AboutLinkRows(links: AboutLink.contacts)
            } header: {
                // iOS 18 has no large-title subtitle, so the credits head the first section.
                if #unavailable(iOS 26) {
                    credits.textCase(nil)
                }
            }
            .settingsRow()
            Section {
                AboutLinkRows(links: AboutLink.specialThanks)
            } header: {
                Text(L10n.Localizable.AboutView.Section.Title.specialThanks).settingsSectionHeader()
            }
            .settingsRow()
            Section {
                AboutLinkRows(links: AboutLink.acknowledgements)
            } header: {
                Text(L10n.Localizable.AboutView.Section.Title.acknowledgements).settingsSectionHeader()
            }
            .settingsRow()
        }
        .settingsFormStyle()
        .navigationTitle(L10n.Localizable.AboutView.Title.ehShoko)
        .toolbar {
            if #available(iOS 26, *) {
                ToolbarItem(placement: .largeSubtitle) {
                    credits
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Tokens.Spacing.xSmall)
                }
            }
        }
    }

    private var credits: some View {
        VStack(alignment: .leading) {
            Text(Self.version)
        }
        .font(.caption2.bold())
        .foregroundStyle(look.secondaryLabel)
        .accessibilityElement(children: .combine)
    }

    /// "Version 3.0.0 (42)".
    private static var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return [L10n.Localizable.AboutView.Title.version, version, "(\(build))"].joined(separator: " ")
    }
}

private struct AboutLinkRows: View {
    let links: [AboutLink]
    @Environment(\.look) private var look

    var body: some View {
        ForEach(links) { link in
            if let url = link.url {
                Link(destination: url) {
                    HStack {
                        Text(link.text).fontWeight(.medium)
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(look.tertiaryLabel)
                            .accessibilityHidden(true)
                    }
                    .contentShape(.rect)
                }
                .foregroundStyle(look.label)
            } else {
                // Credits without a profile link are listed as plain text, as in legacy.
                Text(link.text).fontWeight(.medium).foregroundStyle(look.label)
            }
        }
    }
}

#Preview {
    NavigationStack { AboutScreen() }
}
