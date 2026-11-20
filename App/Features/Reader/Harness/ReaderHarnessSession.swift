#if DEBUG || HARNESS
import Observation
import UIKit

/// Owns the reader that is on screen in the harness. By hand that is one reader for as long
/// as the harness is open. A check (`ReaderHarnessOptions`) opens one after another, each with
/// a new model and a new engine, and writes what it finds to `ReaderHarnessFiles`.
@Observable
final class ReaderHarnessSession {
    private(set) var model: ReaderHarnessModel?
    /// A new value is a new reader: model, engine and closing page.
    private(set) var readerID = 0
    /// What a running check is doing, shown over the reader.
    var status: String?

    /// The harness's size on screen, which says which way the screen is turned.
    @ObservationIgnored var viewSize = CGSize.zero
    @ObservationIgnored let options = ReaderHarnessOptions.atLaunch
    @ObservationIgnored private var hasStarted = false

    init() {
        // A check or a pose opens its own readers.
        if options.check == nil, options.pose == nil {
            model = ReaderHarnessModel(setup: ReaderHarnessSetup().with { $0.look = options.look })
        }
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        // The harness turns with the screen, as the reader does where landscape is allowed.
        AppDelegate.setOrientationLock(.unlocked)
        if let check = options.check {
            await run(check)
        } else if let setup = options.poseSetup() {
            await pose(setup)
        }
    }

    func stop() {
        model?.stop()
        if UIDevice.current.userInterfaceIdiom != .pad {
            AppDelegate.setOrientationLock(.portrait)
        }
    }

    /// Takes the reader on screen down and opens one for `setup`, with its calls recorded.
    func open(_ setup: ReaderHarnessSetup) async -> ReaderHarnessRun {
        model?.stop()
        model = nil
        await turn(toLandscape: setup.isLandscape)
        // The last engine and the pages it decoded are gone before this one starts.
        ImagePipeline.cache.clearMemoryCache()
        try? await Task.sleep(for: .milliseconds(300))
        let model = ReaderHarnessModel(setup: setup.with { $0.look = $0.look ?? options.look })
        let run = ReaderHarnessRun(model: model)
        self.model = model
        readerID += 1
        await run.waitForEngine()
        return run
    }

    var isLandscape: Bool { viewSize.width > viewSize.height }

    /// Turns the screen and waits until the harness has its new size.
    func turn(toLandscape landscape: Bool) async {
        guard isLandscape != landscape else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let orientations: UIInterfaceOrientationMask = landscape ? .landscapeRight : .portrait
        for scene in scenes {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { error in
                ReaderHarnessFiles.log("! turning the screen failed: \(error.localizedDescription)")
            }
        }
        for _ in 0..<100 where isLandscape != landscape {
            try? await Task.sleep(for: .milliseconds(50))
        }
        // The turn's animation.
        try? await Task.sleep(for: .milliseconds(700))
    }

    /// Opens a short gallery on the closing page's slot and leaves it there, for a look or
    /// for touches.
    private func pose(_ setup: ReaderHarnessSetup) async {
        let run = await open(setup)
        if options.posesPageStatus {
            // The reader stays where it opened, its pages loading or failed: waiting for rest
            // would wait for the slow download.
            try? await Task.sleep(for: .seconds(2))
            ReaderHarnessFiles.log("\(setup.name): \(run.state), \(run.model.failedPageCount) pages failed")
            return
        }
        await run.settle()
        await run.jump(to: setup.pageCount)
        if !setup.isLandscape {
            await run.step(1, animated: false)
        }
        ReaderHarnessFiles.log("\(setup.name): \(run.state)")
    }
}
#endif
