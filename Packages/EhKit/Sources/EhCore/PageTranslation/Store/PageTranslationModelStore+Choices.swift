import EhModels
import Foundation

// Which models the current choices mean for this user, and where they stand together.

extension PageTranslationModelStore {
    /// Whether an artifact can be had: it is installed, or one of this user's sources
    /// offers it. A choice whose model cannot be had is listed in Settings and cannot be
    /// chosen.
    public func isAvailable(_ id: ModelArtifactID) -> Bool {
        guard let artifact = catalog.artifact(id) else { return false }
        return records[id] != nil || sources.offers(artifact)
    }

    /// The chosen detector, or the best one that can be had when the chosen one cannot:
    /// the first in the catalog's order. So "default" means KoharuLayout 2XL with a
    /// private store and ogkalu v4-s without one. `nil` when no detector can be had.
    public var resolvedDetector: TextDetectorChoice? {
        resolve(choices.modelSet().detector, among: TextDetectorChoice.allCases) { $0.artifact }
    }

    public var resolvedReader: TextReaderChoice? {
        resolve(choices.modelSet().reader, among: TextReaderChoice.allCases) { $0.artifact }
    }

    public var resolvedTranslator: TranslatorChoice? {
        resolve(choices.modelSet().translator, among: TranslatorChoice.allCases) { $0.artifact }
    }

    /// The chosen repaint model, another one when it cannot be had, or none.
    public var resolvedRepaint: RepaintChoice {
        let chosen = choices.repaint()
        guard let artifact = chosen.artifact, !isAvailable(artifact) else { return chosen }
        let models = RepaintChoice.allCases.filter { $0.artifact != nil }
        return resolve(chosen, among: models) { $0.artifact ?? artifact } ?? .off
    }

    /// The models a page is translated with, and the switch for sound effects, or `nil`
    /// while one of the three kinds has no model this user can have.
    public var resolvedModelSet: PageTranslationModelSet? {
        guard let detector = resolvedDetector, let reader = resolvedReader, let translator = resolvedTranslator
        else { return nil }
        return PageTranslationModelSet(
            detector: detector, reader: reader, translator: translator,
            translatesSoundEffects: choices.modelSet().translatesSoundEffects
        )
    }

    /// What the current choices need on the device: the set's three models and the
    /// repaint model.
    public var requiredArtifacts: [ModelArtifactID] {
        [resolvedDetector?.artifact, resolvedReader?.artifact, resolvedTranslator?.artifact, resolvedRepaint.artifact]
            .compactMap { $0 }
    }

    /// Whether one of the required models may only be used non-commercially, which the
    /// download sheet says.
    public var requiredModelsIncludeNonCommercial: Bool {
        requiredArtifacts.contains { catalog.artifact($0)?.credit.nonCommercial == true }
    }

    /// Where the required models stand together.
    public var requiredModelsState: ModelSetState {
        guard resolvedModelSet != nil else { return .unavailable }
        let ids = requiredArtifacts
        let states = ids.map(state(of:))
        if states.allSatisfy({ $0 == .installed }) { return .ready }

        var progress = ModelTransferProgress(completedBytes: 0, totalBytes: 0)
        for id in ids {
            let size = catalog.artifact(id)?.downloadSize ?? 0
            progress.totalBytes += size
            switch state(of: id) {
            case .installed, .installing, .preparing: progress.completedBytes += size
            case .downloading(let part), .paused(let part): progress.completedBytes += part.completedBytes
            case .missing, .waiting, .failed: progress.completedBytes += min(bytesOnDisk[id] ?? 0, size)
            }
        }
        let isDownloading = states.contains {
            switch $0 {
            case .waiting, .downloading: true
            default: false
            }
        }
        if isDownloading { return isConnected ? .downloading(progress) : .waitingForConnection(progress) }
        if states.contains(where: { $0 == .installing || $0 == .preparing }) { return .preparing }
        if states.contains(where: { if case .paused = $0 { true } else { false } }) { return .paused(progress) }
        for case .failed(let failure) in states { return .failed(failure) }
        return .missing(bytes: bytesToDownload(for: ids))
    }

    private func resolve<Choice: Equatable>(
        _ chosen: Choice, among all: [Choice], artifact: (Choice) -> ModelArtifactID
    ) -> Choice? {
        if isAvailable(artifact(chosen)) { return chosen }
        let order = catalog.artifacts.map(\.id)
        return all.filter { isAvailable(artifact($0)) }
            .min { (order.firstIndex(of: artifact($0)) ?? .max) < (order.firstIndex(of: artifact($1)) ?? .max) }
    }
}
