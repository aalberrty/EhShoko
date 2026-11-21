#if DEBUG || HARNESS
import CryptoKit
import EhCore
import Foundation

/// The runs that drive the service: pages through it, and pages cancelled in it.
extension TranslationHarnessRun {
    /// What a run that drives the service holds while it runs.
    struct Service {
        var session: PageTranslationSession
        var events: TranslationHarnessEvents
        var calls: TranslationHarnessCalls
        var loads: TranslationHarnessLoads
    }

    func openService() async throws -> Service {
        let store = try await waitForStore()
        let options = options
        let setup = try await MainActor.run { try TranslationHarnessEnvironment.setup(options, store: store) }
        result.setup = Self.record(of: setup, options: options)
        let cache = try await TranslationHarnessCache.open(keeping: options.keepsCache, droppingPatches: options.dropsPatches)
        let calls = TranslationHarnessCalls(recordsText: options.recordsText)
        let loads = TranslationHarnessLoads(start: start)
        let service = PageTranslationService(
            environment: TranslationHarnessEnvironment.make(
                setup: setup, options: options, calls: calls, loads: loads, cache: cache
            )
        )
        let session = service.client.openSession(TranslationHarnessEnvironment.gid)
        let events = TranslationHarnessEvents()
        await events.listen(to: session.events)
        return Service(session: session, events: events, calls: calls, loads: loads)
    }

    /// Closes the session, waits for the models to be let go, and notes the memory then.
    func close(_ service: Service) async {
        service.session.close()
        await service.events.stop()
        result.loads = service.loads.all
        try? await Task.sleep(for: .seconds(3))
        result.memory.afterClose = sampler.now()
    }

    // MARK: Pages

    func runPages() async throws {
        let files = try pageFiles()
        let count = options.pageCount > 0 ? options.pageCount : files.count
        let service = try await openService()
        defer { service.session.setWindow(.empty) }
        let pages = (0..<count).map { PageTranslationPage(index: $0, imageURL: files[$0 % files.count]) }
        var askedAt: [Int: Double] = [:]
        _ = sampler.takeWindow()
        _ = service.calls.take()

        for index in pages.indices {
            let asked = clock.now
            askedAt[index] = askedAt[index] ?? secondsSinceStart
            service.session.setWindow(window(around: index, of: pages))
            // In the reader's window the pages ahead are asked for now too.
            if options.window == .reader {
                for ahead in pages.indices.dropFirst(index + 1).prefix(3) where askedAt[ahead] == nil {
                    askedAt[ahead] = secondsSinceStart
                }
            }
            await say("page \(index + 1) of \(count) · \(ProcessInfo.processInfo.thermalState.harnessName)")
            guard let final = await service.events.waitForFinal(of: index, until: deadline) else {
                result.stoppedBecause = "time limit (\(options.maxMinutes) min) at page \(index + 1) of \(count)"
                break
            }
            await keep(final, page: pages[index], askedAtS: askedAt[index] ?? 0, service: service)
            await write()
            if let reason = reasonToStop(after: final, page: index, of: count) {
                result.stoppedBecause = reason
                break
            }
            if options.interval > 0 {
                let next = asked + .seconds(options.interval)
                if next > clock.now { try? await Task.sleep(until: next) }
            }
        }
        await close(service)
    }

    private func window(around index: Int, of pages: [PageTranslationPage]) -> PageTranslationWindow {
        switch options.window {
        case .single:
            return PageTranslationWindow(onScreen: [pages[index]])
        case .reader:
            return PageTranslationWindow(
                onScreen: [pages[index]],
                ahead: Array(pages.dropFirst(index + 1).prefix(3)),
                behind: index > 0 ? [pages[index - 1]] : []
            )
        }
    }

    private func keep(
        _ final: TranslationHarnessEvents.Final, page: PageTranslationPage, askedAtS: Double, service: Service
    ) async {
        let thermal = ProcessInfo.processInfo.thermalState
        let taken = service.calls.take()
        var record = TranslationHarnessResult.Page(
            index: page.index, file: page.imageURL.lastPathComponent, askedAtS: askedAtS,
            endedAtS: TranslationHarnessCalls.milliseconds(final.at - start) / 1_000, event: final.event,
            calls: taken.tallies, memory: sampler.takeWindow(), thermal: thermal.harnessName, recorded: taken.text
        )
        if case let .translated(overlay) = final.event.status {
            record.patchFileSHA256 = await Self.sha256(of: overlay.patchFile)
        }
        result.pages.append(record)
        if result.thermal.firstPage[thermal.harnessName] == nil {
            result.thermal.firstPage[thermal.harnessName] = page.index
        }
    }

    private func reasonToStop(after final: TranslationHarnessEvents.Final, page index: Int, of count: Int) -> String? {
        let thermal = ProcessInfo.processInfo.thermalState
        if thermal.rawValue >= options.stopAt.rawValue {
            return "thermal state \(thermal.harnessName) after page \(index + 1) of \(count)"
        }
        if options.stopsOnFailure, case let .failed(failure) = final.event.status {
            return "page \(index + 1) failed: \(failure)"
        }
        if isPastDeadline, index + 1 < count {
            return "time limit (\(options.maxMinutes) min) after page \(index + 1) of \(count)"
        }
        return nil
    }

    @concurrent
    static func sha256(of file: URL) async -> String? {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Cancels

    /// One page translated whole first, so the models are loaded; then each page is asked for
    /// and the window emptied `cancelAfter` seconds later. The time kept is from the cancel to
    /// the return of the model call that was under way (a Core ML call cannot be stopped; a
    /// language model stops between two tokens).
    func runCancels() async throws {
        let files = try pageFiles()
        let count = options.pageCount > 0 ? options.pageCount : 10
        let service = try await openService()
        defer { service.session.setWindow(.empty) }

        await say("loading the models with one page")
        let warmUp = PageTranslationPage(index: 100_000, imageURL: files[0])
        service.session.setWindow(PageTranslationWindow(onScreen: [warmUp]))
        guard let final = await service.events.waitForFinal(of: warmUp.index, until: deadline) else {
            result.stoppedBecause = "time limit before the models were loaded"
            await close(service)
            return
        }
        await keep(final, page: warmUp, askedAtS: 0, service: service)

        for index in 0..<count {
            guard !isPastDeadline else {
                result.stoppedBecause = "time limit after \(index) cancels"
                break
            }
            await say("cancel \(index + 1) of \(count)")
            let page = PageTranslationPage(index: index, imageURL: files[index % files.count])
            service.session.setWindow(PageTranslationWindow(onScreen: [page]))
            try? await Task.sleep(for: .seconds(options.cancelAfter))
            let cancelled = clock.now
            let underWay = service.calls.stagesUnderWay
            let finishedFirst = await service.events.final(of: index) != nil
            service.session.setWindow(.empty)
            let ms = await service.calls.idle(since: cancelled)
            result.cancels.append(
                TranslationHarnessResult.Cancel(
                    index: index, file: page.imageURL.lastPathComponent, cancelledAfterS: options.cancelAfter,
                    finishedFirst: finishedFirst, callsUnderWay: underWay.map(\.rawValue), msUntilIdle: ms
                )
            )
            _ = service.calls.take()
            await write()
            // Let the service settle before the next page, so pages do not queue.
            try? await Task.sleep(for: .milliseconds(300))
        }
        await close(service)
    }

    nonisolated static func record(
        of setup: PageTranslationSetup, options: TranslationHarnessOptions
    ) -> TranslationHarnessResult.Setup {
        let pipeline = setup.pipeline
        let set = setup.modelSet
        return TranslationHarnessResult.Setup(
            modelSetKey: set.key, detector: set.detector.rawValue, reader: set.reader.rawValue,
            translator: set.translator.rawValue, translatorFile: options.modelFile, repaint: setup.repaint.key,
            detectorUnits: pipeline?.detectorUnits?.harnessName ?? "preferred",
            readerUnits: pipeline?.readerUnits?.harnessName ?? "preferred",
            translatorUnits: pipeline?.translatorUnits?.harnessName ?? "preferred",
            repaintUnits: setup.repaintUnits.harnessName, contextLength: options.contextLength,
            contextLengthApplied: options.contextLength != nil && TranslationHarnessLanguageModel.appliesContextLength
        )
    }
}
#endif
