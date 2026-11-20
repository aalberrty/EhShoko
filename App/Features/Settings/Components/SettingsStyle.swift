import SwiftUI

// Settings on the look's tokens: the look's surface as the ground, its raised colour for the
// cards, its separator and its secondary colour for headings. The sheet is the system's
// (`README.md` section 13): nothing here sets `presentationBackground`, and no row is glass.
//
// The ground, the rows and the headings are the shared sheets' form (`LookFormStyle.swift`),
// so Settings, Filters and quick searches look alike. Settings reaches it only through this
// file.

extension View {
    /// The form's ground: the look's surface in place of the system's grouped background.
    func settingsFormStyle() -> some View {
        lookFormStyle(sectionSpacing: .compact)
    }

    /// A section's heading: small, semibold, uppercase, in the look's secondary colour.
    func settingsSectionHeader() -> some View {
        lookFormHeader()
    }

    /// The rows of a card: the look's raised colour and separator. Unlike the Filters row it
    /// leaves the text colour to the control, so a button keeps its tint or its red; rows
    /// that draw their own text take it from the look (`SettingsRowLabel`).
    func settingsRow() -> some View {
        lookFormRow(.control)
    }

    /// A footnote under a card, in the look's secondary colour.
    func settingsFootnote() -> some View {
        modifier(SettingsFootnote())
    }
}

private struct SettingsFootnote: ViewModifier {
    @Environment(\.look) private var look

    func body(content: Content) -> some View {
        content
            .font(.footnote)
            .foregroundStyle(look.secondaryLabel)
    }
}

/// A row's label as the Settings page draws it, with Wall's icons and descriptions: a
/// monochrome line symbol without a tile, the title, and a description under it.
struct SettingsRowLabel: View {
    enum Role {
        /// The look's label colour.
        case standard
        /// The tint: an action that leads somewhere new (Sign in).
        case tinted
        /// Red: Sign out.
        case destructive
    }

    let symbol: String
    let title: String
    var description: String?
    var role = Role.standard

    @Environment(\.look) private var look

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxSmall) {
                Text(title)
                    .foregroundStyle(titleStyle)
                if let description {
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(look.secondaryLabel)
                }
            }
            .padding(.vertical, description == nil ? 0 : Tokens.Spacing.xxSmall)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(titleStyle)
                .accessibilityHidden(true)
        }
    }

    private var titleStyle: AnyShapeStyle {
        switch role {
        case .standard: AnyShapeStyle(look.label)
        case .tinted: AnyShapeStyle(.tint)
        case .destructive: AnyShapeStyle(.red)
        }
    }
}
