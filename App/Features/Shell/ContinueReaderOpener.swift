import EhFeatures
import SwiftUI

/// Which control of Continue opened the reader, for the reader's zoom (`ReaderSourceID`).
nonisolated enum ContinueControl: Hashable, Sendable {
    /// The tab bar's accessory (`.continueBar`).
    case bar
    /// A first screen's card or banner (`.continueCard`).
    case card
}

/// Opens the reader at a Continue item, presented by the shell (`ShellPresentations`), and
/// says which control asked, so the reader zooms out of that one. Under `tabs` Shelf's Home
/// shows its cards beside the bar's accessory, so the bar alone cannot say.
///
/// A screen reads `\.openContinueReader` and calls it from the control's action. A control
/// that sets `AppRouter.reading` itself gets the bar's control under `tabs` and the card
/// under `command`.
nonisolated struct ContinueReaderOpener: Equatable {
    private weak var router: AppRouter?
    private weak var origin: ContinueReaderOrigin?

    /// `ShellPresentations` passes its router and the origin it keeps; `nil` is the opener
    /// that does nothing.
    init(router: AppRouter?, origin: ContinueReaderOrigin?) {
        self.router = router
        self.origin = origin
    }

    @MainActor
    func callAsFunction(_ item: ContinueItem, from control: ContinueControl) {
        origin?.record(control, for: item.gallery.gid)
        router?.reading = ReadingRequest(gallery: item.gallery, page: item.page)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.router === rhs.router && lhs.origin === rhs.origin
    }
}

/// The control that last opened the reader from Continue, kept by `ShellPresentations` until
/// that reader has gone. Not observed: the presenter reads it once, when the reader opens.
final class ContinueReaderOrigin {
    private var gid: String?
    private var control: ContinueControl?

    func record(_ control: ContinueControl, for gid: String) {
        self.gid = gid
        self.control = control
    }

    /// The control that opened the reader for `gid`, if one said.
    func control(for gid: String) -> ContinueControl? {
        self.gid == gid ? control : nil
    }

    func clear() {
        gid = nil
        control = nil
    }
}

extension EnvironmentValues {
    /// Set by the shell above both bars. Outside it, it does nothing.
    @Entry var openContinueReader = ContinueReaderOpener(router: nil, origin: nil)
}
