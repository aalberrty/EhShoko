#if DEBUG || HARNESS
import Darwin
import EhFeatures
import EhModels
import Foundation
import UIKit

/// A timed record of the offer after install, for measuring it: launched with
/// `-OfferProbe YES` it does nothing otherwise (add `-settings.experienceOfferShown NO` so the
/// offer shows on every launch).
///
/// From the moment the sheet appears it notes when that was (since the process started), the
/// footprint and the per-design objects in memory (the part harness's heap scan); then, every
/// 3 s for `-OfferProbeSeconds` (default 96), the process's and the main thread's CPU time with
/// the app's state: long enough to send the app to the background and back by hand, and to
/// pass the stage's 72 s idle stop. Then it leaves the offer as `-OfferProbeWayOut` says
/// (`notnow`, the default, `use` or `setup`, with the selection `-OfferProbeSelect
/// shelf|wall|ledger`), measures once more without the sheet, lists the objects again and
/// writes everything to `Documents/offer-probe.txt`. Nothing else touches the app meanwhile:
/// the device tools' snapshots block its main thread.
@MainActor
final class ExperienceOfferProbe {
    static let shared = ExperienceOfferProbe()
    private static let defaults = UserDefaults.standard
    static let isOn = defaults.bool(forKey: "OfferProbe")
    private static let seconds = defaults.object(forKey: "OfferProbeSeconds") as? Int ?? 96
    private static let wayOut = defaults.string(forKey: "OfferProbeWayOut") ?? "notnow"
    private static let selection = defaults.string(forKey: "OfferProbeSelect").flatMap(DesignStyle.init)

    private var hasStarted = false
    private var lines: [String] = []

    func offerAppeared(_ model: ExperienceOfferModel) {
        guard Self.isOn, !hasStarted else { return }
        hasStarted = true
        note(String(format: "offer appeared %.0f ms after the process started", Self.sinceProcessStart() * 1_000))
        Task { await run(model) }
    }

    private func run(_ model: ExperienceOfferModel) async {
        await rest(4)
        note("footprint, offer up: \(footprint())")
        note("heap, offer up:\n" + PartHarnessHeap.report())
        for second in stride(from: 3, through: Self.seconds, by: 3) {
            let sample = await cpu(for: 3)
            note("t=\(second + 4)s \(Self.state()) \(sample)")
        }
        if let selection = Self.selection {
            model.selection = selection
        }
        switch Self.wayOut {
        case "use": model.use()
        case "setup": model.setUp()
        default: model.notNow()
        }
        note("left the offer: \(Self.wayOut) \(model.selection.rawValue)")
        await rest(3)
        note("offer gone: " + (await cpu(for: 3)))
        note("heap, offer gone:\n" + PartHarnessHeap.report())
        note("footprint at the end: \(footprint())")
        write()
    }

    // MARK: Measures

    /// The process's and the main thread's CPU time over `seconds`, in ms per second.
    private func cpu(for seconds: Double) async -> String {
        let process = Self.processSeconds()
        let main = Self.mainThreadSeconds()
        let start = Date.now
        await rest(seconds)
        // A suspended app's timer fires late: the rate is over the time that really passed.
        let elapsed = Date.now.timeIntervalSince(start)
        let processRate = (Self.processSeconds() - process) / elapsed * 1_000
        let mainRate = (Self.mainThreadSeconds() - main) / elapsed * 1_000
        return String(format: "over %.1f s: CPU %.1f ms/s (main thread %.1f ms/s)", elapsed, processRate, mainRate)
    }

    private static func state() -> String {
        switch UIApplication.shared.applicationState {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
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

    /// Seconds since the process was created, as the kernel recorded it.
    private static func sinceProcessStart() -> Double {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0 else { return 0 }
        let start = info.kp_proc.p_starttime
        let started = Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000
        return Date.now.timeIntervalSince1970 - started
    }

    private func footprint() -> String {
        guard let footprint = MemoryFootprint.current() else { return "unknown" }
        return String(format: "%.2f MB", Double(footprint.current) / 1_048_576)
    }

    private func note(_ line: String) {
        lines.append(line)
        write()
    }

    private func write() {
        guard let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: folder.appending(path: "offer-probe.txt"), atomically: true, encoding: .utf8)
    }

    private func rest(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}
#endif
