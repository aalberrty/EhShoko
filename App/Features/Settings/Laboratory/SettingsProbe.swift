#if DEBUG
import EhFeatures
import SwiftUI
import UIKit

/// A scripted run over the Settings sheet, for measuring it: launched with
/// `-SettingsProbe <n>`, it does nothing otherwise.
///
/// Once the Settings page has been opened (by hand or with the device tools) it waits, then
/// scrolls the page and the Experience screen three times each with the list harness's
/// scroller (late frames counted from the display link), writes the per-design objects in
/// memory with the part harness's heap scan, closes the sheet, and opens and closes it `n`
/// times. For each opening it records the time from the request to the page's first
/// appearance and the late frames in the second after the request; around the openings it
/// records the memory footprint with the sheet closed. Everything goes to
/// `Documents/settings-probe.txt`.
@MainActor
final class SettingsProbe {
    static let shared = SettingsProbe()
    /// `-SettingsProbe <n>`: how many times the sheet is opened and closed; 0 is off.
    static let cycles = UserDefaults.standard.integer(forKey: "SettingsProbe")

    let scroller = ListHarnessScroller()
    private var hasStarted = false
    private var requestedAt: CFTimeInterval?
    private var openTimes: [Double] = []
    private var lines: [String] = []

    /// The Settings page appeared: closes the timing of an opening, and starts the run once.
    func pageAppeared(router: AppRouter) {
        if let requestedAt {
            openTimes.append((CACurrentMediaTime() - requestedAt) * 1_000)
            self.requestedAt = nil
        }
        guard Self.cycles > 0, !hasStarted else { return }
        hasStarted = true
        Task { await run(router: router) }
    }

    private func run(router: AppRouter) async {
        await rest(3)
        note("open, first time: \(footprint())")
        for round in 1...3 {
            await scroll("page \(round)")
        }
        router.settings.push(.settings(.design))
        await rest(2)
        for round in 1...3 {
            await scroll("experience \(round)")
        }
        note("heap with Experience open:\n" + PartHarnessHeap.report())
        router.settings.pop()
        await rest(1)
        router.dismissSettings()
        await rest(4)
        note("closed after the first opening: \(footprint())")
        var lateFrames: [String] = []
        for _ in 0..<Self.cycles {
            requestedAt = CACurrentMediaTime()
            let counter = LateFrameCounter()
            router.presentSettings()
            let late = await counter.count(for: 1)
            lateFrames.append(late)
            await rest(1.5)
            router.dismissSettings()
            await rest(2)
        }
        await rest(5)
        note("closed after \(Self.cycles) more openings: \(footprint())")
        note("opening, request to first appearance (ms): " + openTimes.map { String(format: "%.0f", $0) }.joined(separator: ", "))
        note("opening, late frames in the first second: " + lateFrames.joined(separator: ", "))
        write()
    }

    private func scroll(_ name: String) async {
        guard let result = await scroller.run(speed: 800) else {
            note("\(name): no scroll view")
            return
        }
        note(String(
            format: "%@: %.0f ms, %d frames, %d late (%.1f ms late in all, worst %.1f ms), %.1f ms/s",
            name, result.duration * 1_000, result.frames, result.hitches, result.hitchTime * 1_000,
            result.worstHitch * 1_000, result.hitchRatio
        ))
        await rest(0.5)
    }

    private func footprint() -> String {
        guard let footprint = MemoryFootprint.current() else { return "unknown" }
        return String(format: "%.2f MB", Double(footprint.current) / 1_048_576)
    }

    private func note(_ line: String) {
        lines.append(line)
    }

    private func write() {
        guard let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: folder.appending(path: "settings-probe.txt"), atomically: true, encoding: .utf8)
    }

    private func rest(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}

/// Counts display frames that arrived half a frame or more after they were due.
@MainActor
private final class LateFrameCounter: NSObject {
    private var link: CADisplayLink?
    private var previous: CFTimeInterval = 0
    private var duration: CFTimeInterval = 0
    private var late = 0
    private var lateTime: CFTimeInterval = 0
    private var worst: CFTimeInterval = 0

    /// Late frames over `seconds`, as "count (total ms, worst ms)".
    func count(for seconds: Double) async -> String {
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        try? await Task.sleep(for: .seconds(seconds))
        link.invalidate()
        self.link = nil
        return String(format: "%d (%.1f ms, worst %.1f ms)", late, lateTime * 1_000, worst * 1_000)
    }

    @objc private func tick(_ link: CADisplayLink) {
        if previous > 0, duration > 0 {
            let delay = (link.timestamp - previous) - duration
            if delay > duration * 0.5 {
                late += 1
                lateTime += delay
                worst = max(worst, delay)
            }
        }
        previous = link.timestamp
        duration = link.targetTimestamp - link.timestamp
    }
}

extension View {
    /// Marks a Settings screen for `SettingsProbe`: where its scroll view is, and, for the
    /// Settings page, when it appears. Nothing without `-SettingsProbe`.
    func settingsProbe(isPage: Bool = false) -> some View {
        modifier(SettingsProbeMarker(isPage: isPage))
    }
}

private struct SettingsProbeMarker: ViewModifier {
    let isPage: Bool
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        if SettingsProbe.cycles > 0 {
            content
                .background { ListHarnessAnchor(scroller: SettingsProbe.shared.scroller) }
                .onAppear {
                    if isPage { SettingsProbe.shared.pageAppeared(router: router) }
                }
        } else {
            content
        }
    }
}
#endif
