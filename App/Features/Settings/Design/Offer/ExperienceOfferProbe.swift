#if DEBUG || HARNESS
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
        note(String(format: "offer appeared %.0f ms after the process started", HarnessCPU.sinceProcessStart() * 1_000))
        Task { await run(model) }
    }

    private func run(_ model: ExperienceOfferModel) async {
        await rest(4)
        note("footprint, offer up: \(HarnessCPU.footprint())")
        note("heap, offer up:\n" + PartHarnessHeap.report())
        for second in stride(from: 3, through: Self.seconds, by: 3) {
            let sample = await HarnessCPU.sample(for: 3)
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
        note("offer gone: " + (await HarnessCPU.sample(for: 3)))
        note("heap, offer gone:\n" + PartHarnessHeap.report())
        note("footprint at the end: \(HarnessCPU.footprint())")
        write()
    }

    // MARK: Measures

    private static func state() -> String {
        switch UIApplication.shared.applicationState {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
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
