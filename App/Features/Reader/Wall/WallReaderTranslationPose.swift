#if DEBUG
import EhCore
import EhFeatures
import Foundation
import Observation

/// Wall's translation controls over made-up state, for screenshots and the re-render check:
/// launch a debug build with `-WallReaderTranslationPose <name>`. On the simulator the real
/// models give wrong answers and no download can run, so the states past "needs models" are
/// posed. The controls behave as with the reader's model: a press turns the pose on or off,
/// the pill chooses, Retry starts the page again. Nothing reaches the engine.
///
/// | Name | The controls show |
/// |---|---|
/// | `off` | The circle |
/// | `mark` | The circle with the dot: 12 pages translated before |
/// | `downloading` | The circle with its ring, moving from 10% to 95% four times a second |
/// | `preparing` | The circle with a full ring |
/// | `on` | The circle in the tint, the pill on Translated, no toast (the page is done) |
/// | `original` | The same with the pill on Original |
/// | `gettingReady` | On, the toast "Getting translation ready…" |
/// | `translating` | On, the toast "Translating page 23…" |
/// | `failed` | On, the toast "Couldn't translate page 23" with Retry |
///
/// `-WallReaderTranslationControls YES` shows the controls at launch, and
/// `-WallReaderTranslationScrub YES` raises the filmstrip as a finger on the capsule would.
/// It belongs to the Wall controls' view that made it and goes with it.
@Observable
final class WallReaderTranslationPose {
    enum Name: String {
        case off, mark, downloading, preparing, on, original, gettingReady, translating, failed
    }

    var availability = ReaderTranslationAvailability.ready
    var isOn = false
    var displayMode = ReaderTranslationDisplayMode.translated
    var status: ReaderTranslationStatus?
    var pagesTranslatedBefore = 0
    @ObservationIgnored private let name: Name

    private static let nameAtLaunch = UserDefaults.standard.string(forKey: "WallReaderTranslationPose").flatMap(Name.init)
    private static let page = 23
    private static let downloadBytes: Int64 = 1_180_000_000

    /// The pose of the launch argument, or `nil` (the reader's model) without it.
    static func atLaunch() -> WallReaderTranslationPose? {
        nameAtLaunch.map(WallReaderTranslationPose.init)
    }

    static var showsControls: Bool { UserDefaults.standard.bool(forKey: "WallReaderTranslationControls") }
    static var raisesFilmstrip: Bool { UserDefaults.standard.bool(forKey: "WallReaderTranslationScrub") }

    private init(_ name: Name) {
        self.name = name
        switch name {
        case .off: break
        case .mark: pagesTranslatedBefore = 12
        case .downloading: availability = .installing(Self.progress(0.1))
        case .preparing: availability = .installing(nil)
        case .on: isOn = true; status = .translated
        case .original: isOn = true; status = .translated; displayMode = .original
        case .gettingReady: isOn = true; status = .gettingReady
        case .translating: isOn = true; status = .translating(page: Self.page)
        case .failed: isOn = true; status = .failed(page: Self.page)
        }
    }

    /// The download's progress, four reports a second as the store makes them; ends with the
    /// view that runs it.
    func run() async {
        guard name == .downloading else { return }
        var fraction = 0.1
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            fraction = fraction >= 0.95 ? 0.1 : fraction + 0.01
            availability = .installing(Self.progress(fraction))
        }
    }

    func toggle() {
        isOn.toggle()
        status = isOn ? .translating(page: Self.page) : nil
    }

    func retry() {
        status = .translating(page: Self.page)
    }

    private static func progress(_ fraction: Double) -> ModelTransferProgress {
        ModelTransferProgress(completedBytes: Int64(Double(downloadBytes) * fraction), totalBytes: downloadBytes)
    }
}
#endif
