import EhModels
import Foundation
import Observation

/// Which page translation models are on the device, and getting the missing ones.
///
/// A download belongs to the store, not to a screen: leaving the reader or Settings does
/// not stop it, and it goes on after the app was suspended or closed (the transport hands
/// every range to the system at once; the part files are the state). Everything that
/// touches a file runs off the main actor, in the installer or the downloader; this class
/// only holds what the screens show.
@MainActor @Observable
public final class PageTranslationModelStore {
    /// Where each artifact of the catalog stands. Read through `state(of:)`.
    public internal(set) var states: [ModelArtifactID: ModelArtifactState] = [:]
    /// The installed artifacts.
    public internal(set) var records: [ModelArtifactID: InstalledArtifact] = [:]
    /// The folder has been read at least once.
    public internal(set) var isLoaded = false
    /// A token for the private store is in the Keychain. The token itself is never shown.
    public internal(set) var hasSourceToken = false
    public internal(set) var isConnected = true
    public internal(set) var isPaused = false
    /// Artifacts whose files were all found in place but are not the files the catalog
    /// lists. They are not used.
    public internal(set) var uncheckedCopies: Set<ModelArtifactID> = []
    /// For each artifact that is not installed, the bytes of its download that are on disk.
    var bytesOnDisk: [ModelArtifactID: Int64] = [:]

    /// Called before models are deleted, so that whoever has them loaded lets go first.
    @ObservationIgnored public var unloadBeforeDeleting: (@MainActor ([ModelArtifactID]) async -> Void)?

    @ObservationIgnored let environment: ModelStoreEnvironment
    @ObservationIgnored let choices: ModelStoreChoices
    @ObservationIgnored let installer: ModelInstaller
    @ObservationIgnored let downloader: ModelDownloader
    /// The work under way for an artifact: a download, an install, a first load.
    @ObservationIgnored var tasks: [ModelArtifactID: Task<Void, Never>] = [:]
    @ObservationIgnored var generations: [ModelArtifactID: Int] = [:]
    /// Artifacts whose work was told to stop and has not ended yet. New work may be queued
    /// behind it.
    @ObservationIgnored var stopping: Set<ModelArtifactID> = []
    @ObservationIgnored var progressSequences: [ModelArtifactID: Int] = [:]
    @ObservationIgnored var intent = ModelDownloadIntent()
    @ObservationIgnored var intentWrite: Task<Void, Never>?
    @ObservationIgnored var reloading: Task<Void, Never>?
    @ObservationIgnored var watchingConnectivity: Task<Void, Never>?
    /// Set while the app was woken in the background: first loads wait for the foreground.
    @ObservationIgnored var defersPreparing = false
    @ObservationIgnored var triedPreparing: Set<ModelArtifactID> = []

    public nonisolated init(environment: ModelStoreEnvironment, choices: ModelStoreChoices) {
        self.environment = environment
        self.choices = choices
        let downloader = ModelDownloader(
            transport: environment.transport, layout: environment.layout, chunkSize: environment.chunkSize,
            slots: ModelWorkSlots(environment.chunksInFlight), sleep: environment.sleep
        )
        self.downloader = downloader
        installer = ModelInstaller(
            layout: environment.layout, catalog: environment.catalog, compiler: environment.compiler,
            downloader: downloader
        )
    }

    public nonisolated var catalog: ModelCatalog { environment.catalog }

    // MARK: Reading

    public func state(of artifact: ModelArtifactID) -> ModelArtifactState {
        states[artifact] ?? .missing
    }

    /// Where an installed artifact's files are, or `nil` when it is not installed.
    public func installedFiles(of id: ModelArtifactID) -> InstalledModelFiles? {
        guard let record = records[id], let artifact = catalog.artifact(id) else { return nil }
        return InstalledModelFiles(
            artifact: artifact, folder: environment.layout.folder(of: id), isPrepared: record.isPrepared
        )
    }

    /// What an installed artifact takes on disk; 0 when it is not installed.
    public func installedBytes(of artifact: ModelArtifactID) -> Int64 {
        records[artifact]?.bytes ?? 0
    }

    /// What every installed model takes together.
    public var installedBytes: Int64 {
        records.values.reduce(0) { $0 + $1.bytes }
    }

    /// What is left to fetch for `artifacts`: their sizes in the catalog less what is on
    /// disk already.
    public func bytesToDownload(for artifacts: [ModelArtifactID]) -> Int64 {
        artifacts.reduce(0) { total, id in
            guard records[id] == nil, let artifact = catalog.artifact(id) else { return total }
            return total + max(0, artifact.downloadSize - (bytesOnDisk[id] ?? 0))
        }
    }

    /// The private store's address, when what the user typed is one.
    public var privateStoreAddress: URL? {
        ModelSourceConfiguration.address(from: choices.sourceAddress())
    }

    /// The stores in use, without the token: enough to tell what they offer.
    var sources: ModelSourceConfiguration {
        ModelSourceConfiguration(privateStore: privateStoreAddress, token: nil, publicStore: environment.publicStore)
    }

    // MARK: Looking at the folder

    /// Reads what is on disk: what is installed, what a download left behind, what was
    /// copied in. Files found in place are checked against the catalog and adopted; a
    /// download that was under way goes on. Call it when a screen that shows the models
    /// appears; it is not part of launch.
    public func refresh() async {
        defersPreparing = false
        await reload()
    }

    func reload() async {
        if let reloading { return await reloading.value }
        let task = Task { await self.readFolder() }
        reloading = task
        await task.value
        reloading = nil
    }

    private func readFolder() async {
        watchConnectivity()
        // What an earlier run's transfers left must be in place before anything is judged.
        await environment.transport.collectEarlierTransfers()
        let surveys = await installer.survey()
        hasSourceToken = await Self.readToken(environment.tokens)?.isEmpty == false
        if !isLoaded {
            intent = await installer.intent()
            isPaused = intent.isPaused
        }
        var complete: [ModelArtifact] = []
        for artifact in catalog.artifacts where !isBusy(artifact.id) {
            let survey = surveys[artifact.id] ?? ModelArtifactSurvey()
            records[artifact.id] = survey.record
            bytesOnDisk[artifact.id] = survey.bytesOnDisk
            if survey.record != nil {
                states[artifact.id] = .installed
            } else {
                if case .failed = state(of: artifact.id) {} else { states[artifact.id] = .missing }
                if survey.isComplete { complete.append(artifact) }
            }
        }
        isLoaded = true
        continueDownloads()
        for artifact in complete where !isBusy(artifact.id) && !uncheckedCopies.contains(artifact.id) {
            adopt(artifact)
        }
        prepareInstalledModels()
    }

    /// Goes on with what was asked for before the app was closed.
    private func continueDownloads() {
        let wanted = intent.artifacts.filter { records[$0] == nil && !isBusy($0) && catalog.artifact($0) != nil }
        if wanted.count != intent.artifacts.count {
            intent.artifacts = wanted
            writeIntent()
        }
        guard !wanted.isEmpty else { return }
        if isPaused {
            for id in wanted { states[id] = .paused(progress(of: id)) }
        } else {
            start(wanted)
        }
    }

    /// Takes files that are already in place, such as models copied in from a Mac: each is
    /// checked against the catalog, and only if all match is the artifact installed.
    private func adopt(_ artifact: ModelArtifact) {
        let id = artifact.id
        states[id] = .installing
        run(for: id) { store in
            do {
                guard try await store.installer.uncheckedFiles(of: artifact).isEmpty else {
                    store.uncheckedCopies.insert(id)
                    store.states[id] = .missing
                    store.environment.log("Files found for \(id) are not the files of the catalog; they are not used.")
                    return
                }
                try await store.install(artifact)
            } catch {
                store.settle(id, after: error)
            }
        }
    }

    /// The first load of models that were installed while the app was in the background.
    private func prepareInstalledModels() {
        guard !defersPreparing else { return }
        for artifact in catalog.artifacts {
            let id = artifact.id
            guard let record = records[id], !record.isPrepared, !isBusy(id), triedPreparing.insert(id).inserted
            else { continue }
            states[id] = .preparing
            run(for: id) { store in
                store.records[id] = await store.prepared(artifact, record)
                store.states[id] = .installed
            }
        }
    }

    // MARK: Work for one artifact

    /// Runs `work` for an artifact after whatever was running for it has ended, so two
    /// pieces of work never touch the same files.
    func run(for id: ModelArtifactID, _ work: @escaping @MainActor (PageTranslationModelStore) async -> Void) {
        let generation = (generations[id] ?? 0) + 1
        generations[id] = generation
        let previous = tasks[id]
        stopping.remove(id)
        tasks[id] = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await work(self)
            guard self.generations[id] == generation else { return }
            self.tasks[id] = nil
            self.stopping.remove(id)
        }
    }

    /// Tells the work under way for an artifact to stop. It ends on its own time; `run`
    /// queues behind it.
    func stop(_ id: ModelArtifactID) {
        guard let task = tasks[id] else { return }
        task.cancel()
        stopping.insert(id)
    }

    /// Whether work is under way for an artifact that has not been told to stop.
    func isBusy(_ id: ModelArtifactID) -> Bool {
        tasks[id] != nil && !stopping.contains(id)
    }

    /// Compiles, records and loads once. The artifact's files are all in place and checked.
    func install(_ artifact: ModelArtifact) async throws {
        let id = artifact.id
        states[id] = .installing
        var record = try await installer.install(artifact)
        records[id] = record
        if !record.isPrepared, !defersPreparing {
            states[id] = .preparing
            triedPreparing.insert(id)
            record = await prepared(artifact, record)
            records[id] = record
        }
        states[id] = .installed
        forget(id)
        environment.log("Installed \(id): \(record.bytes) bytes on disk.")
    }

    /// A first load that fails is not an install that failed: the model loads when it is used.
    private func prepared(_ artifact: ModelArtifact, _ record: InstalledArtifact) async -> InstalledArtifact {
        do {
            return try await installer.prepare(artifact, record: record)
        } catch {
            environment.log("The first load of \(artifact.id) did not finish: \(error)")
            return record
        }
    }

    /// Records how work for an artifact ended when it did not end well.
    func settle(_ id: ModelArtifactID, after error: any Error) {
        if error is CancellationError {
            states[id] = isPaused && intent.artifacts.contains(id) ? .paused(progress(of: id)) : .missing
            return
        }
        let failure = Self.failure(from: error)
        states[id] = .failed(failure)
        forget(id)
        environment.log("\(id) stopped: \(failure) (\(error))")
    }

    static func failure(from error: any Error) -> ModelStoreFailure {
        if let failure = error as? ModelStoreFailure { return failure }
        let cocoa = error as NSError
        let outOfSpace = (cocoa.domain == NSCocoaErrorDomain && cocoa.code == NSFileWriteOutOfSpaceError)
            || (cocoa.domain == NSPOSIXErrorDomain && cocoa.code == Int(ENOSPC))
        return outOfSpace ? .noSpace(needed: 0, available: 0) : .installFailed
    }

    /// How far an artifact that is not installed has come.
    func progress(of id: ModelArtifactID) -> ModelTransferProgress {
        switch state(of: id) {
        case .downloading(let progress), .paused(let progress): return progress
        default: break
        }
        let total = catalog.artifact(id)?.downloadSize ?? 0
        return ModelTransferProgress(completedBytes: min(bytesOnDisk[id] ?? 0, total), totalBytes: total)
    }

    // MARK: What was asked for

    /// An artifact is no longer waited for: it is installed, failed or cancelled.
    func forget(_ id: ModelArtifactID) {
        guard intent.artifacts.contains(id) else { return }
        intent.artifacts.removeAll { $0 == id }
        if intent.artifacts.isEmpty {
            intent.isPaused = false
            isPaused = false
        }
        writeIntent()
    }

    /// Writes the intent after the write before it, so the newest is the one that stays.
    func writeIntent() {
        let snapshot = intent
        intentWrite = Task { [installer, previous = intentWrite] in
            await previous?.value
            await installer.write(snapshot)
        }
    }

    // MARK: The token and the network

    /// Keeps the private store's token in the Keychain; `nil` or an empty text removes it.
    public func setSourceToken(_ token: String?) async throws {
        try await Self.write(token, to: environment.tokens)
        hasSourceToken = token?.isEmpty == false
    }

    @concurrent
    nonisolated static func readToken(_ tokens: ModelSourceTokenStore) async -> String? {
        tokens.read()
    }

    @concurrent
    private nonisolated static func write(_ token: String?, to tokens: ModelSourceTokenStore) async throws {
        try tokens.write(token)
    }

    private func watchConnectivity() {
        guard watchingConnectivity == nil else { return }
        let connectivity = environment.connectivity
        watchingConnectivity = Task { [weak self] in
            for await connected in connectivity() {
                guard let self else { return }
                if self.isConnected != connected { self.isConnected = connected }
            }
        }
    }

    /// Ends when nothing is running for any artifact and the intent is on disk. Tests wait
    /// on it; the background wake-up uses it to know when it may hand back.
    func waitUntilIdle() async {
        while let task = tasks.values.first {
            await task.value
        }
        await intentWrite?.value
    }
}
