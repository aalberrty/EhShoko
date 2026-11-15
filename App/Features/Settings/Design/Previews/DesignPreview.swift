import EhCore
import EhModels
import os
import SwiftUI

/// A still picture of a design choice: a schematic of flat shapes drawn by one `Canvas` from a
/// look's tokens (`Design/designs/settings.md`, "Previews"). It never creates a part, holds
/// nothing after it leaves the screen, and draws again only when its subject, the look, the
/// appearance, the accent or its size changes; scrolling moves it without redrawing.
///
/// It draws on a 100 × 160 grid scaled to its width, at an aspect of 5:8; the caller gives it
/// a width (or a frame) in points that does not grow with the text size.
///
/// Which look it is drawn in: an option of Colours and type always in its own; otherwise the
/// look passed in; otherwise, for a set of choices, their look; otherwise the app's look.
struct DesignPreview: View {
    nonisolated enum Subject: Hashable, Sendable {
        /// One option of one page, alone.
        case option(DesignPart, DesignOption)
        /// The first screen with its list and its bar, as a set of choices puts them together.
        case firstScreen(DesignChoices)
        /// The gallery page of a set of choices.
        case gallery(DesignChoices)
        /// The reader of a set of choices.
        case reader(DesignChoices)
    }

    let subject: Subject
    /// The look to draw in; `nil` for the app's. Presets, look options and the wizard pass one.
    var look: DesignStyle?

    @Environment(\.look) private var appLook
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(SettingsStore.self) private var settings

    init(_ subject: Subject, look: DesignStyle? = nil) {
        self.subject = subject
        self.look = look
    }

    var body: some View {
        let drawnLook = subject.look(given: look, app: appLook)
        let tint = drawnLook.tint(for: settings.accentColor)
        let palette = SchematicPalette(
            look: drawnLook, accent: tint.tint, onAccent: tint.onTint, colorScheme: colorScheme, contrast: contrast
        )
        SchematicView(subject: subject, palette: palette)
            .equatable()
            .aspectRatio(5 / 8, contentMode: .fit)
            .accessibilityElement()
            .accessibilityLabel(Text(subject.accessibilityLabel))
            .accessibilityAddTraits(.isImage)
    }
}

nonisolated extension DesignPreview.Subject {
    /// The look this subject is drawn in (see `DesignPreview`).
    func look(given look: DesignStyle?, app: Look) -> Look {
        switch self {
        case .option(.look, .style(let style)): Look(style)
        case .option: look.map(Look.init) ?? app
        case .firstScreen(let choices), .gallery(let choices), .reader(let choices): Look(look ?? choices.look)
        }
    }
}

/// The canvas itself, compared by value so that a parent's update that changes none of its
/// inputs does not draw it again.
private struct SchematicView: View, Equatable {
    let subject: DesignPreview.Subject
    let palette: SchematicPalette

    private static let signposter = OSSignposter(
        subsystem: PerformanceSignposts.subsystem, category: PerformanceSignposts.category
    )

    var body: some View {
        Canvas { context, size in
            let interval = Self.signposter.beginInterval("SchematicDraw")
            SchematicRenderer.render(subject, palette: palette, into: context, size: size)
            Self.signposter.endInterval("SchematicDraw", interval)
        }
    }
}
