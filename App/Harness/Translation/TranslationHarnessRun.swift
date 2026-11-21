#if DEBUG || HARNESS
import EhCore
import EhModels
import Foundation

/// One launch's run of the translation harness, off the main actor. It says what it is
/// doing through `report` (the screen's one line) and writes its result as it goes.
actor TranslationHarnessRun {
    let options: TranslationHarnessOptions
    let report: @MainActor @Sendable (String) -> Void
    let clock = ContinuousClock()
    let start: ContinuousClock.Instant
    let deadline: ContinuousClock.Instant
    let sampler = TranslationHarnessSampler()
    let outputURL: URL
    var result: TranslationHarnessResult
    private var ballast: TranslationHarnessBallast?

    init(options: TranslationHarnessOptions, report: @escaping @MainActor @Sendable (String) -> Void) {
        self.options = options
        self.report = report
        start = ContinuousClock.now
        deadline = start + .seconds(options.maxMinutes * 60)
        let startedAt = Date.now
        outputURL = TranslationHarnessOutput.url(label: options.label, startedAt: startedAt)
        result = TranslationHarnessResult(
            label: options.label, run: options.run.rawValue, startedAt: startedAt, device: .current,
            arguments: Array(ProcessInfo.processInfo.arguments.dropFirst())
        )
    }

    /// Runs to the end and returns the screen's last line.
    func run() async -> String {
        if options.run == .clean { return await clean() }
        result.thermal.atStart = ProcessInfo.processInfo.thermalState.harnessName
        if ProcessInfo.processInfo.thermalState != .nominal, !options.startsWhenWarm {
            return await finish(because: "not started: the thermal state is \(result.thermal.atStart ?? "?"), not nominal")
        }
        if options.ballastMB > 0 {
            await say("holding \(options.ballastMB) MB")
            ballast = TranslationHarnessBallast(megabytes: options.ballastMB)
            result.memory.ballast = options.ballastMB
        }
        sampler.start()
        result.memory.baseline = sampler.now()
        do {
            switch options.run {
            case .pages: try await runPages()
            case .cancel: try await runCancels()
            case .load: try await runLoads()
            case .lines: try await runLines()
            case .clean: break
            }
            return await finish(because: result.stoppedBecause ?? "done")
        } catch {
            return await finish(because: "error: \(error)")
        }
    }

    // MARK: Shared steps

    func say(_ line: String) async {
        await report("\(options.label) · \(line)")
    }

    var secondsSinceStart: Double { TranslationHarnessCalls.milliseconds(clock.now - start) / 1_000 }

    var isPastDeadline: Bool { clock.now >= deadline }

    /// Waits until the store has looked at its folder and every model the run needs is
    /// installed: copied files are checked and compiled, and their first loads done.
    func waitForStore() async throws -> PageTranslationModelStore {
        await say("looking at the models")
        let needed = neededArtifacts
        let record = try await Self.waitForStore(needed: needed, start: start, until: deadline) { [weak self] line in
            await self?.say(line)
        }
        result.store = record.record
        result.memory.afterStoreReady = sampler.now()
        return record.store
    }

    var neededArtifacts: [ModelArtifactID] {
        var set = options.modelSet
        if options.modelFile != nil { set.translator = .jmtFast1 }
        return set.artifacts + [options.repaint.artifact].compactMap { $0 }
    }

    @MainActor
    private static func waitForStore(
        needed: [ModelArtifactID], start: ContinuousClock.Instant, until deadline: ContinuousClock.Instant,
        say: @escaping @Sendable (String) async -> Void
    ) async throws -> (store: PageTranslationModelStore, record: TranslationHarnessResult.Store) {
        let store = PageTranslationModelStore.liveValue
        let atStart = Set(needed.filter { store.state(of: $0) == .installed })
        await store.refresh()
        var installedAt: [ModelArtifactID: Double] = [:]
        while true {
            var waiting: [String] = []
            for id in needed {
                switch store.state(of: id) {
                case .installed:
                    if installedAt[id] == nil { installedAt[id] = TranslationHarnessCalls.milliseconds(.now - start) / 1_000 }
                case .missing:
                    throw TranslationHarnessEnvironment.SetupError.notInstalled([id])
                case let .failed(failure):
                    throw TranslationHarnessError("\(id.rawValue) failed in the store: \(failure)")
                case let state:
                    waiting.append("\(id.rawValue) \(Self.name(of: state))")
                }
            }
            if waiting.isEmpty { break }
            guard ContinuousClock.now < deadline else { throw TranslationHarnessError("the store was not ready: \(waiting.joined(separator: ", "))") }
            await say(waiting.joined(separator: ", "))
            try await Task.sleep(for: .milliseconds(500))
        }
        let record = TranslationHarnessResult.Store(
            readyAfterS: TranslationHarnessCalls.milliseconds(.now - start) / 1_000,
            artifacts: needed.map { id in
                TranslationHarnessResult.Store.Artifact(
                    id: id.rawValue, state: Self.name(of: store.state(of: id)),
                    installedAtS: atStart.contains(id) ? nil : installedAt[id], wasInstalledAtStart: atStart.contains(id)
                )
            }
        )
        return (store, record)
    }

    private nonisolated static func name(of state: ModelArtifactState) -> String {
        switch state {
        case .missing: "missing"
        case .waiting: "waiting"
        case .downloading: "downloading"
        case .paused: "paused"
        case .installing: "installing"
        case .preparing: "preparing"
        case .installed: "installed"
        case .failed: "failed"
        }
    }

    /// The pages of the folder, in the order of their names.
    func pageFiles() throws -> [URL] {
        let folder = TranslationHarnessOptions.containerURL(options.pagesFolder)
        let images: Set<String> = ["png", "jpg", "jpeg", "webp", "gif", "heic"]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let pages = files.filter { images.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard !pages.isEmpty else { throw TranslationHarnessError("no pages in \(options.pagesFolder)") }
        return pages
    }

    func write() async {
        do {
            try await TranslationHarnessOutput.write(result, to: outputURL)
        } catch {
            await say("the result could not be written: \(error)")
        }
    }

    private func finish(because reason: String) async -> String {
        sampler.stop()
        result.stoppedBecause = reason
        result.endedAt = .now
        result.thermal.atEnd = ProcessInfo.processInfo.thermalState.harnessName
        result.memory.run = sampler.run
        result.memory.lifetimeFootprintPeak = TranslationHarnessSampler.lifetimePeak
        result.summary = TranslationHarnessSummary(result)
        await write()
        ballast = nil
        return "\(options.label) · \(reason) · \(outputURL.lastPathComponent)"
    }

    private func clean() async -> String {
        try? FileManager.default.removeItem(at: TranslationHarnessOptions.folder)
        await TranslationHarnessCache.remove()
        return "\(options.label) · the harness's pages, results and cache are deleted"
    }
}

nonisolated struct TranslationHarnessError: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}
#endif
