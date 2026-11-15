#if DEBUG || HARNESS
import EhCore
import EhModels
import SwiftUI
import UIKit

/// The moving preview, `PresetStage`, on a page of the preview harness's sheet
/// (`-HarnessPage stage`), as the wizard's first step and the offer will hold it: under a
/// few controls, above plain rows so the page scrolls it away and back.
///
/// | Argument | Meaning |
/// |---|---|
/// | `-HarnessStageScroll YES` | Four seconds after the page opens, scrolls it from the top to the end at `-HarnessSpeed` points a second (default 400), counting late frames, and writes the result to `Library/Caches/PreviewHarness/stage-scroll`. |
/// | `-HarnessStageExport YES` | Writes the twelve held frames (one per beat, the storyboards' stills) light and dark to `Library/Caches/PreviewHarness/stage-light.png` and `stage-dark.png`. |
/// | `-HarnessStageSelect shelf\|wall\|ledger` | Selects that preset after two seconds, as a tap on its tile does. |
/// | `-HarnessStageCovered YES` | Starts with the stage covered, so it holds: the control for the time and scroll measurements. |
/// | `-HarnessStageProbe YES` | Six seconds after the page opens, writes the process's memory (`stage-open`, beside the harness's round marks). |
/// | `-HarnessStageHeap YES` | Six seconds after the page opens, writes the in-process heap check of per-design types (`Documents/stage-heap.txt`). It demangles every class name, so leave it out of a time profile. |
///
/// Every opening of the page writes `stage-shown` with the time, for a script to wait on.
///
/// With `-HarnessCycle n` and `-HarnessPage stage` the sheet opens and closes on this page:
/// the memory marks then tell what the stage leaves behind.
struct PreviewHarnessStage: View {
    @State private var selection: DesignStyle?
    @State private var isCovered = UserDefaults.standard.bool(forKey: "HarnessStageCovered")
    @State private var scroller = ListHarnessScroller()
    @State private var status = ""
    @Environment(\.look) private var look
    @Environment(SettingsStore.self) private var store

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button {
                    selection = nil
                } label: {
                    Text(verbatim: "Keep what I have")
                }
                .buttonStyle(.bordered)
                Toggle(isOn: $isCovered) {
                    Text(verbatim: "Covered")
                }
                .fixedSize()
            }
            Text(verbatim: "Selected: \(selection?.localizedName ?? "none")\(status.isEmpty ? "" : " · \(status)")")
                .font(.caption.monospaced())
                .foregroundStyle(look.secondaryLabel)
            // Rows above and below, so a scripted scroll carries the stage up through the
            // screen and away.
            ForEach(0..<3, id: \.self, content: row)
            PresetStage(selection: $selection, isCovered: isCovered)
            ForEach(3..<40, id: \.self, content: row)
        }
        .padding(16)
        .background(ListHarnessAnchor(scroller: scroller))
        .task { await runScripted() }
        .task { await probe() }
    }

    private func row(_ row: Int) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(look.surface)
            .frame(height: 56)
            .overlay(alignment: .leading) {
                Text(verbatim: "Row \(row + 1)").foregroundStyle(look.secondaryLabel).padding(.leading, 14)
            }
    }

    private func probe() async {
        PreviewHarnessStageExport.writeLine("shown=\(Date.now.timeIntervalSince1970)", to: "stage-shown")
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "HarnessStageProbe") || defaults.bool(forKey: "HarnessStageHeap") else { return }
        try? await Task.sleep(for: .seconds(6))
        guard !Task.isCancelled else { return }
        if defaults.bool(forKey: "HarnessStageProbe") {
            PreviewHarnessExport.mark("stage-open")
        }
        if defaults.bool(forKey: "HarnessStageHeap") {
            PartHarnessHeap.writeReport(named: "stage-heap.txt")
        }
    }

    private func runScripted() async {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "HarnessStageExport") {
            status = PreviewHarnessStageExport.write(accent: store.accentColor)
        }
        if let name = defaults.string(forKey: "HarnessStageSelect"), let style = DesignStyle(rawValue: name) {
            try? await Task.sleep(for: .seconds(2))
            selection = style
        }
        guard defaults.bool(forKey: "HarnessStageScroll") else { return }
        try? await Task.sleep(for: .seconds(4))
        let speed = defaults.double(forKey: "HarnessSpeed")
        guard let result = await scroller.run(speed: speed > 0 ? speed : 400) else {
            status = "No scroll view"
            return
        }
        let line = String(
            format: "duration=%.2f frames=%d hitches=%d hitchTime=%.1fms worst=%.1fms ratio=%.2fms/s frame=%.1fms",
            result.duration, result.frames, result.hitches, result.hitchTime * 1_000, result.worstHitch * 1_000,
            result.hitchRatio, result.frameDuration * 1_000
        )
        status = line
        PreviewHarnessStageExport.writeLine(line, to: "stage-scroll")
    }
}

/// The held frames: the twelve beats' stills of the storyboards, laid out like the
/// generator's contact sheet (`tools/settings.py`, `contact`), so the two can be set side by
/// side.
enum PreviewHarnessStageExport {
    static let moments: [(DesignStyle, Int)] = StagePlayback.order.flatMap { style in
        (0..<Storyboard.beats).map { (style, $0) }
    }

    static func write(accent: RGBColor) -> String {
        var written = 0
        for scheme in [ColorScheme.light, .dark] {
            let palettes = StagePalettes(accent: accent, colorScheme: scheme, contrast: .standard)
            let renderer = ImageRenderer(content: StageHeldFrames(scheme: scheme, palettes: palettes))
            renderer.scale = 2
            let name = "stage-\(scheme == .dark ? "dark" : "light").png"
            if let data = renderer.uiImage?.pngData(), let url = folder?.appending(path: name),
               (try? data.write(to: url)) != nil {
                written += 1
            }
        }
        return "Wrote \(written) held-frame sheets"
    }

    static func writeLine(_ line: String, to name: String) {
        guard let url = folder?.appending(path: name) else { return }
        FileManager.default.createFile(atPath: url.path, contents: Data((line + "\n").utf8))
    }

    private static var folder: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let folder = caches.appending(path: "PreviewHarness", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

private struct StageHeldFrames: View {
    let scheme: ColorScheme
    let palettes: StagePalettes

    var body: some View {
        let rows = stride(from: 0, to: PreviewHarnessStageExport.moments.count, by: 6).map {
            Array(PreviewHarnessStageExport.moments[$0..<$0 + 6])
        }
        VStack(alignment: .leading, spacing: 18) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(alignment: .top, spacing: 14) {
                    ForEach(rows[row].indices, id: \.self) { item in
                        frame(rows[row][item].0, rows[row][item].1)
                    }
                }
            }
        }
        .padding(18)
        .foregroundStyle(scheme == .dark ? Color.white : Color.black)
        .background(scheme == .dark ? Color(white: 0.11) : Color(red: 0.95, green: 0.95, blue: 0.97))
    }

    private func frame(_ style: DesignStyle, _ beat: Int) -> some View {
        let time = Storyboard.of(style).stills[beat]
        let offset = Double(StagePlayback.order.firstIndex(of: style) ?? 0) * Storyboard.duration
        let scene = StageFrame(scenes: [StageScene(style: style, time: time, opacity: 1)])
        return VStack(spacing: 6) {
            Canvas { context, size in
                StageRenderer.render(scene, palettes: palettes, into: context, size: size)
            }
            .frame(width: PresetStage.size.width, height: PresetStage.size.height)
            Text(verbatim: "\(style.localizedName) · \(StageBeat(style: style, beat: beat).caption) · "
                 + String(format: "%.1f s", offset + time))
                .font(.system(size: 11))
                .frame(width: 170)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
    }
}
#endif
