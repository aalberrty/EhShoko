#if DEBUG
import EhCore
import EhModels
import SwiftUI
import UIKit

/// Writes one contact sheet per look and appearance, laid out like the generator's reference
/// sheets (`tools/schematics.py` rendered row by row), so the two can be set side by side.
enum PreviewHarnessExport {
    /// Renders the six sheets at 2× and writes them as PNG files; returns a line for the
    /// harness's status.
    static func writeContactSheets(store: SettingsStore) -> String {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return "No caches folder"
        }
        let folder = caches.appending(path: "PreviewHarness", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var written = 0
        for look in Look.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let sheet = PreviewHarnessContactSheet(look: look, scheme: scheme)
                    .lookEnvironment(look, accent: store.accentColor)
                    .environment(store)
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: sheet)
                renderer.scale = 2
                let name = "\(String(describing: look))-\(scheme == .dark ? "dark" : "light").png"
                if let data = renderer.uiImage?.pngData(), (try? data.write(to: folder.appending(path: name))) != nil {
                    written += 1
                }
            }
        }
        return "Wrote \(written) sheets to \(folder.path)"
    }
}

/// Every option of every part in rows, the presets and a mix, at the reference's size (the
/// generator's sheet draws a grid unit as 1.6 px; here a unit is 1.6 pt).
private struct PreviewHarnessContactSheet: View {
    let look: Look
    let scheme: ColorScheme

    private static let size = CGSize(width: 160, height: 256)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: "app · options in \(String(describing: look)) look · \(scheme == .dark ? "dark" : "light")")
                .font(.system(size: 11))
            ForEach(DesignPart.allCases, id: \.self) { part in
                HStack(alignment: .top, spacing: 10) {
                    ForEach(part.options, id: \.self) { option in
                        item("\(part.rawValue)/\(option.localizedName.lowercased())") {
                            DesignPreview(.option(part, option))
                        }
                    }
                }
            }
            HStack(alignment: .top, spacing: 10) {
                ForEach(DesignStyle.allCases, id: \.self) { style in
                    item("preset \(style.rawValue)") {
                        DesignPreview(.firstScreen(DesignChoices(preset: style)), look: style)
                    }
                }
                item("mix (list ledger)") {
                    DesignPreview(.firstScreen(PreviewHarnessGallery.mix(look)))
                }
            }
        }
        .padding(12)
        .foregroundStyle(scheme == .dark ? Color.white : Color.black)
        .background(scheme == .dark ? Color(white: 0.11) : Color(red: 0.95, green: 0.95, blue: 0.97))
    }

    private func item(_ caption: String, @ViewBuilder preview: () -> some View) -> some View {
        VStack(spacing: 3) {
            preview().frame(width: Self.size.width, height: Self.size.height)
            Text(verbatim: caption).font(.system(size: 11))
        }
    }
}
#endif
