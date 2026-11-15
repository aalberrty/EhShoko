#if DEBUG || HARNESS
import Darwin
import Dependencies
import EhCore
import EhFeatures
import EhModels
import QuartzCore
import SwiftUI

/// A scripted walk through the setup wizard, for measuring it: launched with
/// `-SetupProbe YES`, it does nothing otherwise.
///
/// Once the wizard has been opened (by hand or with the device tools) it waits, then records
/// the process's CPU time while the stage plays, while an alert covers it and after it plays
/// again, and on step 2, without the stage, alone and under the same alert. It moves through
/// every step to the summary and back two steps, counting late frames in the second after
/// each move and listing the per-design objects in memory (the part harness's heap scan) at
/// each step. With `-SetupProbeApply shelf|wall|ledger` it then goes back to the start,
/// chooses that preset, walks to the summary and applies, lists the objects in memory again,
/// and for comparison makes the same change directly, as a preset tile does (back to the
/// original choices, then the preset). Everything goes to `Documents/setup-probe.txt`.
@MainActor
final class DesignSetupProbe {
    /// What the probe may do with the wizard on screen.
    struct Hooks {
        let model: DesignSetupModel
        let move: (DesignSetupScreen.Move) -> Void
        /// Shows or hides the discard alert, which covers the stage.
        let cover: (Bool) -> Void
        let finish: () -> Void
    }

    static let shared = DesignSetupProbe()
    static let isOn = UserDefaults.standard.bool(forKey: "SetupProbe")
    private static let applies = UserDefaults.standard.string(forKey: "SetupProbeApply").flatMap(DesignStyle.init)

    private var hasStarted = false
    private var lines: [String] = []

    func wizardAppeared(_ hooks: Hooks) {
        guard Self.isOn, !hasStarted else { return }
        hasStarted = true
        Task { await run(hooks) }
    }

    private func run(_ hooks: Hooks) async {
        await rest(4)
        note("footprint, wizard open: \(footprint())")
        note("heap, step 1:\n" + PartHarnessHeap.report())
        note("step 1, stage playing: " + (await cpu(for: 3)))
        hooks.cover(true)
        await rest(3)
        note("step 1, alert over the stage: " + (await cpu(for: 3)))
        hooks.cover(false)
        await rest(3)
        note("step 1, alert closed: " + (await cpu(for: 3)))

        while hooks.model.step != .summary {
            let from = hooks.model.stepNumber ?? 0
            let late = await lateFrames(during: { hooks.move(.next) })
            note("move \(from) → \(hooks.model.stepNumber.map(String.init) ?? "summary"): \(late)")
            await rest(0.5)
            note("heap at \(hooks.model.stepNumber.map { "step \($0)" } ?? "the summary"):\n" + PartHarnessHeap.report())
            if hooks.model.stepNumber == 2 {
                note("step 2, the stage gone: " + (await cpu(for: 3)))
                // The alert's own cost, with no stage under it.
                hooks.cover(true)
                await rest(3)
                note("step 2, the same alert: " + (await cpu(for: 3)))
                hooks.cover(false)
                await rest(3)
            }
        }
        for _ in 0..<2 {
            let late = await lateFrames(during: { hooks.move(.back) })
            note("back to \(hooks.model.stepNumber.map(String.init) ?? "summary"): \(late)")
            await rest(0.5)
        }
        if let preset = Self.applies {
            await apply(preset, hooks)
        }
        note("footprint at the end: \(footprint())")
        write()
    }

    private func apply(_ preset: DesignStyle, _ hooks: Hooks) async {
        let original = hooks.model.current
        while hooks.model.step != .start {
            hooks.move(.back)
            await rest(0.6)
        }
        hooks.model.selectStartingPoint(preset)
        while hooks.model.step != .summary {
            hooks.move(.next)
            await rest(0.6)
        }
        await rest(1)
        note("apply \(preset.rawValue) in the wizard: " + (await timed(hooks.finish)))
        await rest(3)
        note("heap after apply:\n" + PartHarnessHeap.report())
        // The same change made directly, as a preset tile makes it, for comparison: back to
        // the original choices, then the preset again.
        @Dependency(\.settings) var settings
        await rest(5)
        note("directly back to the original: " + (await timed { settings.designChoices = original }))
        await rest(5)
        note("\(preset.rawValue) directly: " + (await timed { settings.applyDesignPreset(preset) }))
    }

    /// Late frames in the second after `action`, and how long that second took to end: a
    /// main thread held up by the change makes it longer.
    private func timed(_ action: () -> Void) async -> String {
        let start = CACurrentMediaTime()
        let late = await lateFrames(during: action)
        return String(format: "%@ (%.0f ms to the end of the count)", late, (CACurrentMediaTime() - start) * 1_000)
    }

    // MARK: Measures

    /// The process's and the main thread's CPU time over `seconds`, in ms per second.
    private func cpu(for seconds: Double) async -> String {
        let process = Self.processSeconds()
        let main = Self.mainThreadSeconds()
        await rest(seconds)
        let processRate = (Self.processSeconds() - process) / seconds * 1_000
        let mainRate = (Self.mainThreadSeconds() - main) / seconds * 1_000
        return String(format: "CPU %.1f ms/s (main thread %.1f ms/s)", processRate, mainRate)
    }

    private func lateFrames(during action: () -> Void) async -> String {
        let counter = DesignSetupLateFrames()
        counter.start()
        action()
        await rest(1)
        return counter.stop()
    }

    private static func processSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    private static func seconds(_ value: timeval) -> Double {
        Double(value.tv_sec) + Double(value.tv_usec) / 1_000_000
    }

    /// The calling thread's CPU time; called on the main actor, so the main thread's.
    private static func mainThreadSeconds() -> Double {
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let thread = pthread_mach_thread_np(pthread_self())
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return 0 }
        let user = Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1_000_000
        let system = Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1_000_000
        return user + system
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
        try? text.write(to: folder.appending(path: "setup-probe.txt"), atomically: true, encoding: .utf8)
    }

    private func rest(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}

/// Counts display frames that arrived half a frame or more after they were due.
@MainActor
private final class DesignSetupLateFrames: NSObject {
    private var link: CADisplayLink?
    private var previous: CFTimeInterval = 0
    private var duration: CFTimeInterval = 0
    private var frames = 0
    private var late = 0
    private var lateTime: CFTimeInterval = 0
    private var worst: CFTimeInterval = 0

    func start() {
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// "frames, late (total ms, worst ms)".
    func stop() -> String {
        link?.invalidate()
        link = nil
        return String(format: "%d frames, %d late (%.1f ms, worst %.1f ms)", frames, late, lateTime * 1_000, worst * 1_000)
    }

    @objc private func tick(_ link: CADisplayLink) {
        frames += 1
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
#endif
