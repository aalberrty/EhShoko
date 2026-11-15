import SwiftUI
import UIKit

/// The colours a schematic is drawn with: the look's tokens resolved for the appearance and
/// contrast the preview is shown in, the tint, and the stand-ins every look shares
/// (`Design/designs/tools/schematics.py`: `LOOKS`, `COV`, `CAT`, `FOLD`, `NS`, `PAPER`).
///
/// Every colour is a plain sRGB value, so a drawing of a hundred fills calls no dynamic
/// colour provider, and the palette is a value the canvas can compare and any thread can draw
/// with.
nonisolated struct SchematicPalette: Equatable, Sendable {
    // The look's tokens.
    let background: Color
    let surface: Color
    let raised: Color
    let label: Color
    let secondary: Color
    let tertiary: Color
    let fill: Color
    let separator: Color
    let accent: Color
    let onAccent: Color
    /// The reader's ground around a page.
    let reader: Color
    /// A floating bar or button: glass in the app, a flat near-opaque fill here.
    let chrome: Color
    /// What a floating shape's drop is drawn with; never a blur.
    let drop: Color
    let isDark: Bool
    /// The face of "Aa" in the Colours and type previews.
    let titleDesign: Font.Design

    /// The tokens are dynamic UIKit colours. `Color.resolve(in:)` builds a trait collection
    /// for each colour, which was most of a preview's drawing time; here one trait collection
    /// serves the whole palette. Building traits is main-actor work in UIKit, so the palette is
    /// made where the view's body runs and handed to the canvas.
    @MainActor
    init(look: Look, accent: Color, onAccent: Color, colorScheme: ColorScheme, contrast: ColorSchemeContrast) {
        let isDark = colorScheme == .dark
        let traits = UITraitCollection { traits in
            traits.userInterfaceStyle = isDark ? .dark : .light
            traits.accessibilityContrast = contrast == .increased ? .high : .normal
        }
        func resolved(_ color: Color) -> Color {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            _ = UIColor(color).resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
        }
        background = resolved(look.background)
        surface = resolved(look.surface)
        raised = resolved(look.raised)
        label = resolved(look.label)
        secondary = resolved(look.secondaryLabel)
        tertiary = resolved(look.tertiaryLabel)
        fill = resolved(look.fill)
        separator = resolved(look.separator)
        self.accent = resolved(accent)
        self.onAccent = resolved(onAccent)
        reader = isDark ? Color(hex: 0x000000) : Self.readerLight(look)
        chrome = Self.chrome(look, isDark: isDark)
        drop = Color(.sRGB, white: 0, opacity: isDark ? 0.5 : 0.16)
        self.isDark = isDark
        titleDesign = look.titleDesign
    }

    private static func readerLight(_ look: Look) -> Color {
        switch look {
        case .shelf: Color(hex: 0xE6E6EA)
        case .wall: Color(hex: 0xE4E4E8)
        case .ledger: Color(hex: 0xDEDBD3)
        }
    }

    private static func chrome(_ look: Look, isDark: Bool) -> Color {
        switch (look, isDark) {
        case (.ledger, false): Color(.sRGB, red: 255 / 255, green: 253 / 255, blue: 248 / 255, opacity: 0.97)
        case (.ledger, true): Color(.sRGB, red: 52 / 255, green: 49 / 255, blue: 46 / 255, opacity: 0.96)
        case (_, false): Color(.sRGB, red: 252 / 255, green: 252 / 255, blue: 253 / 255, opacity: 0.96)
        case (_, true): Color(.sRGB, red: 62 / 255, green: 62 / 255, blue: 66 / 255, opacity: 0.94)
        }
    }

    // MARK: Stand-ins shared by every look

    /// Nine cover colours.
    static let covers: [Color] = [
        0x4F9FD6, 0x8A63D2, 0xF09A3E, 0x5FB37A, 0xE86A8A, 0x2FA7A0, 0xB79A5B, 0xD8553B, 0x5560C8,
    ].map(Color.init(hex:))
    /// Category hues, for marks, bars and tinted capsules.
    static let categories: [Color] = [0x9E2720, 0xDB6C24, 0xD38F1D, 0x6A936D, 0x5FA9CF, 0x6A32A2].map(Color.init(hex:))
    /// Favourites folder hues.
    static let folders: [Color] = [0x8E8E93, 0xE5484D, 0xF2853B, 0xE5B93C, 0x58B368, 0x4C7CF0].map(Color.init(hex:))
    /// Tag namespace hues.
    static let namespaces: [Color] = [0xD9538F, 0x4F7FD6, 0xD9812F, 0x2FA79A].map(Color.init(hex:))
    static let star = Color(hex: 0xF0A000)
    static let white = Color(hex: 0xFFFFFF)
    /// A reader page, and the page thumbnails of strips.
    static let paper = Color(hex: 0xF4F1EA)
    /// The panels of a stand-in comic page, and their ink.
    static let panels: [Color] = [0xD9D5CC, 0xC4C0B7, 0xE3E0D8, 0xB9B5AD].map(Color.init(hex:))
    static let ink = Color(hex: 0x222222)
    /// The grey of Ledger's "More" swipe action.
    static let muted = Color(hex: 0x8A857C)

    static func cover(_ index: Int) -> Color { covers[index % covers.count] }
    static func category(_ index: Int) -> Color { categories[index % categories.count] }
    static func folder(_ index: Int) -> Color { folders[index % folders.count] }
    static func namespace(_ index: Int) -> Color { namespaces[index % namespaces.count] }
}

nonisolated extension Color {
    /// An opaque sRGB colour from `0xRRGGBB`.
    fileprivate init(hex: Int) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
