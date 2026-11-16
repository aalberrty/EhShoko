import EhModels
import Foundation

// Downloading, pausing, cancelling and deleting.

extension PageTranslationModelStore {
    /// What a batch of downloads needs before any of them starts.
    enum DownloadPlan: Sendable {
        case ready(ModelSourceConfiguration)
        case failed(ModelStoreFailure)
    }

    // MARK: Starting

    /// Downloads and installs the models of the current choices that are not installed.
    public func downloadRequiredModels() {
        download(requiredArtifacts)
    }

    /// Downloads and installs `artifacts`. Those that are installed or already under way
    /// are left alone; one that failed is tried again.
    public func download(_ artifacts: [ModelArtifactID]) {
        if isPaused {
            isPaused = false
            intent.isPaused = false
        }
        start(artifacts + intent.artifacts)
    }

    func start(_ ids: [ModelArtifactID]) {
        var seen: Set<ModelArtifactID> = []
        let artifacts = ids.filter { seen.insert($0).inserted }.compactMap(catalog.artifact)
            .filter { records[$0.id] == nil && !isBusy($0.id) }
        guard !artifacts.isEmpty else { return }
        for artifact in artifacts {
            uncheckedCopies.remove(artifact.id)
            states[artifact.id] = .waiting
            if !intent.artifacts.contains(artifact.id) { intent.artifacts.append(artifact.id) }
        }
        writeIntent()
        let plan = Task { await self.plan(for: artifacts) }
        for artifact in artifacts {
            run(for: artifact.id) { store in
                await store.process(artifact, plan: plan)
            }
        }
    }

    /// Reads the sources and checks the room, once for the whole batch.
    private func plan(for artifacts: [ModelArtifact]) async -> DownloadPlan {
        let address = privateStoreAddress
        let token = address == nil ? nil : await Self.readToken(environment.tokens)
        let configuration = ModelSourceConfiguration(
            privateStore: address, token: token, publicStore: environment.publicStore
        )
        let surveys = await installer.survey()
        let left = artifacts.reduce(Int64(0)) { total, artifact in
            total + max(0, artifact.downloadSize - (surveys[artifact.id]?.bytesOnDisk ?? 0))
        }
        // The one line a download leaves in the log when it starts: after the app was
        // closed, "still to fetch" is what shows that nothing is fetched twice.
        let total = artifacts.reduce(Int64(0)) { $0 + $1.downloadSize }
        let names = artifacts.map(\.id.rawValue).joined(separator: ", ")
        environment.log("Downloading \(names): \(left) of \(total) bytes still to fetch.")
        guard left > 0 else { return .ready(configuration) }
        let needed = ModelStoreEnvironment.spaceNeeded(forDownloading: left)
        let available = await Self.freeSpace(environment)
        return available < needed ? .failed(.noSpace(needed: needed, available: available)) : .ready(configuration)
    }

    @concurrent
    private nonisolated static func freeSpace(_ environment: ModelStoreEnvironment) async -> Int64 {
        environment.freeSpace(environment.layout.root)
    }

    /// One artifact from the first range to "installed".
    private func process(_ artifact: ModelArtifact, plan: Task<DownloadPlan, Never>) async {
        let id = artifact.id
        do {
            let configuration: ModelSourceConfiguration
            switch await plan.value {
            case .failed(let failure): throw failure
            case .ready(let ready): configuration = ready
            }
            try Task.checkCancellation()
            guard configuration.offers(artifact) else { throw ModelStoreFailure.noSource }

            let files = try await installer.filesToDownload(of: artifact)
            let total = artifact.downloadSize
            let inPlace = total - files.reduce(0) { $0 + $1.size }
            let progress = ModelDownloadProgress { [weak self] sequence, bytes in
                let progress = ModelTransferProgress(completedBytes: inPlace + bytes, totalBytes: total)
                Task { @MainActor in self?.note(progress, sequence, for: id) }
            }
            progressSequences[id] = 0
            states[id] = .downloading(ModelTransferProgress(
                completedBytes: min(max(inPlace, bytesOnDisk[id] ?? 0), total), totalBytes: total
            ))
            let downloader = downloader
            try await withThrowingTaskGroup(of: Void.self) { group in
                for file in files {
                    let job = ModelFileJob(
                        artifact: id, file: file, sources: configuration.sources(for: file, of: artifact)
                    )
                    group.addTask { try await downloader.download(job, progress: progress) }
                }
                // The first file that cannot be had ends the others.
                for try await _ in group {}
            }
            bytesOnDisk[id] = total
            try await install(artifact)
        } catch {
            if case .downloading(let progress) = state(of: id) { bytesOnDisk[id] = progress.completedBytes }
            settle(id, after: error)
        }
    }

    private func note(_ progress: ModelTransferProgress, _ sequence: Int, for id: ModelArtifactID) {
        // Reports cross to the main actor one by one and may overtake each other.
        guard case .downloading = state(of: id), sequence > (progressSequences[id] ?? 0) else { return }
        progressSequences[id] = sequence
        states[id] = .downloading(progress)
    }

    // MARK: Pausing and cancelling

    private var downloadsUnderWay: [ModelArtifactID] {
        catalog.artifacts.map(\.id).filter {
            switch state(of: $0) {
            case .waiting, .downloading: isBusy($0)
            default: false
            }
        }
    }

    /// Stops the downloads under way and keeps what has arrived. Ranges that were in flight
    /// are fetched again when the download goes on.
    public func pause() {
        let ids = downloadsUnderWay
        guard !ids.isEmpty else { return }
        isPaused = true
        intent.isPaused = true
        writeIntent()
        for id in ids { stop(id) }
    }

    /// Goes on with what was paused.
    public func resume() {
        guard isPaused else { return }
        download([])
    }

    /// Stops every download and deletes what they left. Installed models stay.
    public func cancelDownloads() {
        let ids = catalog.artifacts.map(\.id).filter {
            switch state(of: $0) {
            case .waiting, .downloading, .paused: true
            default: intent.artifacts.contains($0)
            }
        }
        isPaused = false
        intent = ModelDownloadIntent()
        writeIntent()
        for id in ids {
            stop(id)
            guard let artifact = catalog.artifact(id) else { continue }
            run(for: id) { store in
                guard store.records[id] == nil else { return }
                await store.installer.discardPartialDownloads(of: artifact)
                store.bytesOnDisk[id] = await store.installer.survey(artifact).bytesOnDisk
                store.states[id] = .missing
            }
        }
    }

    // MARK: Deleting

    /// Deletes models from the device. Whoever has one loaded is told first.
    public func delete(_ artifacts: [ModelArtifactID]) async {
        await unloadBeforeDeleting?(artifacts)
        for id in artifacts { stop(id) }
        for id in artifacts {
            while let task = tasks[id] { await task.value }
        }
        for id in artifacts {
            await installer.remove(id)
            records[id] = nil
            bytesOnDisk[id] = 0
            states[id] = .missing
            uncheckedCopies.remove(id)
            triedPreparing.remove(id)
            forget(id)
        }
        environment.log("Deleted \(artifacts.map(\.rawValue).joined(separator: ", ")).")
    }

    /// Deletes every model and everything a download left.
    public func deleteAll() async {
        await delete(catalog.artifacts.map(\.id))
    }

    // MARK: Woken in the background

    /// The system woke the app because transfers of a background session are done. Call
    /// it from the app delegate's `handleEventsForBackgroundURLSession`; `completion` is
    /// the system's handler.
    ///
    /// What arrived is collected, put together, checked and compiled within the time the
    /// system allows. The caller has to ask the system for that time: the wake-up itself
    /// ends as soon as the session has delivered its events (on iOS 18.2 the app is
    /// suspended half a second after this call otherwise). First loads are left for the
    /// foreground: they use the GPU and the Neural Engine, which a background app may not.
    public func handleBackgroundSessionEvents(identifier: String, completion: @escaping @MainActor () -> Void) {
        let (events, eventsDelivered) = AsyncStream<Void>.makeStream()
        let isOurs = environment.transport.handleBackgroundEvents(identifier: identifier) { eventsDelivered.finish() }
        guard isOurs else {
            completion()
            return
        }
        defersPreparing = true
        // Whichever comes first ends the wake-up: everything dealt with, or the time the
        // system allows running out. A stream that finishes is the signal for both.
        let (settled, settle) = AsyncStream<Void>.makeStream()
        Task {
            await self.reload()
            for await _ in events {}
            await self.waitUntilIdle()
            settle.finish()
        }
        Task {
            try? await Task.sleep(for: Self.backgroundAllowance)
            settle.finish()
        }
        Task {
            for await _ in settled {}
            eventsDelivered.finish()
            completion()
        }
    }

    /// How long a wake-up may last before the system's handler is called whatever the
    /// state. The app asks for background time when it is woken, and the system gives
    /// about half a minute; this ends a little before that.
    static let backgroundAllowance: Duration = .seconds(25)
}
