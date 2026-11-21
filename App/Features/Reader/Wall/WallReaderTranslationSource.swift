import EhCore
import EhFeatures

/// What Wall's translation controls read of the reader and do to it, one property at a time,
/// so that each control's view reads only what it draws: the circle the availability (a
/// download's progress re-renders the circle alone), the row whether Translate is on, the
/// pill the display mode, the toast the status. Nothing here reads the engine's state, so
/// none of it re-renders the engine.
///
/// In debug builds a pose (`WallReaderTranslationPose`, `-WallReaderTranslationPose <name>`)
/// can stand in for the reader's translation, for screenshots of states the simulator cannot
/// reach with real models.
struct WallReaderTranslationSource {
    let model: ReaderModel
    #if DEBUG
    var pose: WallReaderTranslationPose?
    #endif

    var availability: ReaderTranslationAvailability {
        #if DEBUG
        if let pose { return pose.availability }
        #endif
        return model.translationAvailability
    }

    var isOn: Bool {
        #if DEBUG
        if let pose { return pose.isOn }
        #endif
        return model.translation.isOn
    }

    var pagesTranslatedBefore: Int {
        #if DEBUG
        if let pose { return pose.pagesTranslatedBefore }
        #endif
        return model.translation.pagesTranslatedBefore
    }

    var displayMode: ReaderTranslationDisplayMode {
        #if DEBUG
        if let pose { return pose.displayMode }
        #endif
        return model.translation.displayMode
    }

    var status: ReaderTranslationStatus? {
        #if DEBUG
        if let pose { return pose.status }
        #endif
        return model.translation.status
    }

    /// Translate: on, off, or the download sheet when the models are not installed.
    func toggle() {
        #if DEBUG
        if let pose { return pose.toggle() }
        #endif
        model.toggleTranslation()
    }

    func setDisplayMode(_ mode: ReaderTranslationDisplayMode) {
        #if DEBUG
        if let pose { return pose.displayMode = mode }
        #endif
        model.translation.setDisplayMode(mode)
    }

    /// The toast's Retry: the current page is asked for again.
    func retry() {
        #if DEBUG
        if let pose { return pose.retry() }
        #endif
        model.retryTranslation()
    }
}
