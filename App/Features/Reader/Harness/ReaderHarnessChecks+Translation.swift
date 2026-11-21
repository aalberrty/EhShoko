#if DEBUG || HARNESS
import EhCore
import EhFeatures
import QuartzCore
import UIKit

// The harness's check of the translation overlay, on its made-up translation
// (`ReaderHarnessTranslation`). Like the other checks it opens its own readers, takes no
// touch and writes a report whose last line is `##### done`. `-ReaderHarnessModes` picks
// parts of it: `off`, `place`, `switch`, `livetext`, `damaged`, `release`, `cost`, `paging`,
// `compare`.
extension ReaderHarnessSession {
    func checkTranslation() async {
        let report = ReaderHarnessExpectations(name: "translation-report.txt", title: "The translation overlay")
        let parts = options.modes
        let translation = ReaderHarnessTranslation()
        status = "translation: writing the patch files"
        let started = CACurrentMediaTime()
        await translation.make(pages: Array(1...60))
        report.note(String(format: "60 patch files written in %.1f s", CACurrentMediaTime() - started))

        let checks: [(String, () async -> Void)] = [
            ("off", { await self.checkNeverPressed(report) }),
            ("place", { await self.checkPlacement(report, translation) }),
            ("switch", { await self.checkSwitching(report, translation) }),
            ("livetext", { await self.checkLiveText(report, translation) }),
            ("damaged", { await self.checkDamagedFiles(report) }),
            ("release", { await self.checkRelease(report, translation) }),
            ("cost", { await self.checkCost(report, translation) }),
            ("paging", { await self.checkPaging(report, translation) }),
            ("compare", { await self.checkCompare(report, translation) })
        ]
        for (name, check) in checks where parts.isEmpty || parts.contains(name) {
            status = "translation: \(name)"
            await check()
        }
        await turn(toLandscape: false)
        report.finish()
    }

    /// Opens the translated gallery on page 2 and leaves it there, for a look.
    func poseTranslated(_ pose: String) async {
        let landscape = ["translated-dual", "translated-dual-rtl"].contains(pose)
        let direction: ReaderDirection = switch pose {
        case "translated-rtl", "translated-dual-rtl": .rightToLeft
        case "translated-vertical": .vertical
        default: .leftToRight
        }
        // With the cover alone, pages 2 and 3 share the screen.
        let setup = ReaderHarnessSetup.scripted(
            pose, direction: direction, pageCount: 12, isDualPage: landscape, exceptCover: true, isLandscape: landscape
        ).with { $0.startPage = 2 }
        let translation = ReaderHarnessTranslation()
        await translation.make(pages: Array(1...setup.pageCount))
        let run = await open(setup, translation: translation)
        await run.settle()
        await run.waitForTranslations()
        if pose == "translated-zoom" {
            // On the lower right corner of the page's first balloon.
            await run.zoom(onPage: 2, at: CGPoint(x: 700.0 / 1_280, y: 700.0 / 1_810))
        }
        if pose == "translated-turned" {
            await turn(toLandscape: true)
            await run.settle()
        }
        if UserDefaults.standard.string(forKey: "ReaderHarnessTranslation") == "original" {
            run.model.translationMode = .original
        }
        ReaderHarnessFiles.log("\(setup.name): \(run.state), on screen \(run.model.pagesOnScreen)")
    }

    // MARK: Before the press

    /// A reader in which Translate was never pressed asks for no overlay and makes nothing;
    /// a press in the middle of reading brings the translations in.
    private func checkNeverPressed(_ report: ReaderHarnessExpectations) async {
        report.section("Translate never pressed")
        let loads = ReaderTranslationOverlayLoader.loadCount
        let run = await open(.scripted("translation-off", direction: .leftToRight))
        await run.settle()
        for _ in 0..<4 {
            await run.step(1, animated: true)
        }
        let asked = run.recorder.lines.count { $0.hasPrefix("D translationOverlay") }
        report.expect("the engine asked for no overlay", asked == 0, "asked \(asked) times")
        report.expect(
            "no patch file was read", ReaderTranslationOverlayLoader.loadCount == loads,
            "\(ReaderTranslationOverlayLoader.loadCount - loads) read"
        )
        report.expect(
            "no page view has an overlay view", run.pageViews.allSatisfy { $0.translation.view == nil },
            "\(run.pageViews.count) page views"
        )
        report.expect(
            "the page on screen is reported", run.model.pagesOnScreen == [run.model.currentPage],
            "\(run.model.pagesOnScreen), page \(run.model.currentPage)"
        )

        report.section("Translate pressed while reading")
        run.model.translationMode = .translated
        let shown = await run.waitForTranslations()
        report.expect("the pages that have a view show their translation", shown, run.translationState)
        let askedNow = run.recorder.lines.count { $0.hasPrefix("D translationOverlay") }
        report.expect("the engine asked for their overlays", askedNow >= run.pageViews.count, "asked \(askedNow) times")
        await run.step(1, animated: true)
        report.expect("a page turned to shows its own", await run.waitForTranslations(), run.translationState)
    }

    // MARK: Place

    /// The overlay's patches are where their page's image has them, in every reading mode,
    /// zoomed in, and after the screen was turned.
    private func checkPlacement(_ report: ReaderHarnessExpectations, _ translation: ReaderHarnessTranslation) async {
        let cover: (inout ReaderHarnessSetup) -> Void = { $0.startPage = 2 }
        let modes: [(ReaderHarnessSetup, [Int])] = [
            (ReaderHarnessSetup.scripted("place-ltr", direction: .leftToRight).with(cover), [2]),
            (ReaderHarnessSetup.scripted("place-rtl", direction: .rightToLeft).with(cover), [2]),
            (ReaderHarnessSetup.scripted("place-vertical", direction: .vertical).with(cover), []),
            (
                ReaderHarnessSetup.scripted(
                    "place-dual", direction: .leftToRight, isDualPage: true, exceptCover: true, isLandscape: true
                ).with(cover), [2, 3]
            ),
            (
                ReaderHarnessSetup.scripted(
                    "place-dual-rtl", direction: .rightToLeft, isDualPage: true, exceptCover: true, isLandscape: true
                ).with(cover), [2, 3]
            ),
            // Page 9 is a large original: its patches are in the pixels of a smaller bitmap.
            (ReaderHarnessSetup.scripted("place-large", direction: .leftToRight).with { $0.startPage = 9 }, [9])
        ]
        for (setup, pagesOnScreen) in modes {
            status = "translation: \(setup.name)"
            report.section(setup.name)
            let run = await open(setup, translation: translation)
            await run.settle()
            report.expect("the translations are shown", await run.waitForTranslations(), run.translationState)
            if !pagesOnScreen.isEmpty {
                report.expect(
                    "the pages on screen are reported", run.model.pagesOnScreen == pagesOnScreen,
                    "\(run.model.pagesOnScreen)"
                )
            } else {
                report.note("       pages on screen, nearest first: \(run.model.pagesOnScreen)")
            }
            report.expectPlaced("at rest", run)
            await run.zoom(onPage: run.model.currentPage, at: CGPoint(x: 0.5, y: 0.35))
            report.expectPlaced("zoomed in", run)
            await turn(toLandscape: !setup.isLandscape)
            await run.settle()
            await run.waitForTranslations()
            report.expectPlaced("after a turn of the screen", run)
            await turn(toLandscape: setup.isLandscape)
            await run.settle()
            await run.waitForTranslations()
            report.expectPlaced("and turned back", run)
        }
    }

    // MARK: Switching

    /// Original and translation switch by hiding and showing: no file is read, no overlay is
    /// asked for, and a switch costs a fraction of a frame.
    private func checkSwitching(_ report: ReaderHarnessExpectations, _ translation: ReaderHarnessTranslation) async {
        report.section("Switching between the original and the translation")
        let run = await open(
            ReaderHarnessSetup.scripted("translation-switch", direction: .leftToRight).with { $0.startPage = 2 },
            translation: translation
        )
        await run.settle()
        await run.waitForTranslations()
        let loads = ReaderTranslationOverlayLoader.loadCount
        let asked = run.recorder.lines.count
        let meter = ReaderHarnessFrameMeter()
        var costs: [Double] = []
        meter.start()
        for index in 0..<120 {
            let started = CACurrentMediaTime()
            run.model.proxy.setTranslationDisplay(index.isMultiple(of: 2) ? .original : .translated)
            // With the commit, which is where a layer's content would be prepared.
            CATransaction.flush()
            costs.append((CACurrentMediaTime() - started) * 1_000)
            if index == 0 {
                let view = run.pageView(2)?.translation.view
                report.expect(
                    "the original: the overlay is hidden and kept", view?.isHidden == true && view?.hasPatches == true,
                    run.translationState
                )
            }
            try? await Task.sleep(for: .milliseconds(16))
        }
        let frames = meter.stop()
        report.expect("back on the translation", run.pageView(2)?.showsTranslation == true, run.translationState)
        report.expect(
            "no patch file was read", ReaderTranslationOverlayLoader.loadCount == loads,
            "\(ReaderTranslationOverlayLoader.loadCount - loads) read"
        )
        report.expect("the engine asked for nothing", run.recorder.lines.count == asked, "\(run.recorder.lines.count - asked) calls")
        report.note("       120 switches, main thread with the commit: \(Self.statistics(costs)) ms; \(frames.text)")

        // Pages turned to while the original shows have their overlays ready behind it.
        run.model.proxy.setTranslationDisplay(.original)
        await run.step(1, animated: true)
        await run.step(1, animated: true)
        try? await Task.sleep(for: .milliseconds(500))
        let before = ReaderTranslationOverlayLoader.loadCount
        run.model.proxy.setTranslationDisplay(.translated)
        let page = run.model.currentPage
        report.expect(
            "a page reached while the original showed switches at once",
            run.pageView(page)?.showsTranslation == true && ReaderTranslationOverlayLoader.loadCount == before,
            run.translationState
        )
    }

    // MARK: Live Text

    /// Text cannot be selected on a page that shows its translation, and can again the
    /// moment the original shows. Only where the device has Live Text; no simulator does.
    private func checkLiveText(_ report: ReaderHarnessExpectations, _ translation: ReaderHarnessTranslation) async {
        report.section("Live Text")
        guard ReaderLiveText.isSupported else {
            report.note("       not supported on this device: not checked")
            return
        }
        let run = await open(
            ReaderHarnessSetup.scripted("translation-livetext", direction: .leftToRight).with { $0.startPage = 2 },
            translation: translation
        )
        run.model.configuration.isLiveTextEnabled = true
        await run.settle()
        await run.waitForTranslations()
        // In the page's line "y 200  The quick brown fox", which no patch covers.
        let onText = { () -> Bool in
            guard let pageView = run.pageView(2) else { return false }
            let image = pageView.imageRect
            let point = CGPoint(x: image.minX + image.width * 150 / 1_280, y: image.minY + image.height * 221 / 1_810)
            return pageView.liveTextWantsTouch(at: point)
        }
        run.model.proxy.setTranslationDisplay(.original)
        for _ in 0..<150 where !onText() {
            try? await Task.sleep(for: .milliseconds(100))
        }
        report.expect("the original: the page's text takes touches", onText(), run.translationState)
        run.model.proxy.setTranslationDisplay(.translated)
        report.expect("the translation: it takes none", !onText(), run.translationState)
        run.model.proxy.setTranslationDisplay(.original)
        report.expect("the original again: at once, without a new analysis", onText(), run.translationState)
        run.model.proxy.setTranslationDisplay(.translated)
    }

    // MARK: Damaged files

    /// A patch file that cannot be read: the page shows the original, the host is told, and a
    /// file that is still damaged after it was written again is not asked for in a circle.
    private func checkDamagedFiles(_ report: ReaderHarnessExpectations) async {
        report.section("A patch file that cannot be read")
        let translation = ReaderHarnessTranslation()
        translation.damagedPages = [9]
        await translation.make(pages: Array(1...12))
        await translation.damageFile(of: 6)
        let run = await open(.scripted("translation-damaged", direction: .leftToRight, pageCount: 12), translation: translation)
        await run.settle()
        await run.jump(to: 6)
        var isShown = false
        for _ in 0..<100 where !isShown {
            try? await Task.sleep(for: .milliseconds(50))
            isShown = run.pageView(6)?.showsTranslation == true
        }
        report.expect("page 6 was drawn again and shows its translation", isShown, run.translationState)
        report.expect("the host was told once", translation.failures == [6], "\(translation.failures)")

        await run.jump(to: 9)
        try? await Task.sleep(for: .seconds(2))
        let loads = ReaderTranslationOverlayLoader.loadCount
        try? await Task.sleep(for: .seconds(1))
        // As the reader's model does: drawn again once, and when that cannot be shown either,
        // not again by itself.
        report.expect(
            "page 9, damaged again when written again: told twice, drawn again once",
            translation.failures == [6, 9, 9], "\(translation.failures)"
        )
        report.expect("page 9 shows the original", run.pageView(9)?.showsTranslation == false, run.translationState)
        report.expect(
            "and its file is not read in a circle", ReaderTranslationOverlayLoader.loadCount == loads,
            "\(ReaderTranslationOverlayLoader.loadCount - loads) more reads in a second"
        )
        report.expect("the page beside it is not affected", run.pageView(10)?.translation.view?.hasPatches == true, run.translationState)
    }

    // MARK: Release

    /// Overlays go with their page views, and everything goes with the reader.
    private func checkRelease(_ report: ReaderHarnessExpectations, _ translation: ReaderHarnessTranslation) async {
        report.section("What is released")
        await closeReader()
        let idle = Self.footprint()
        let setup = ReaderHarnessSetup.scripted("translation-release", direction: .leftToRight).with { $0.startPage = 2 }
        // The same reader without its translation first, for what the overlays add.
        await open(setup).settle()
        let plain = Self.footprint()
        await closeReader()
        let run = await open(setup, translation: translation)
        await run.settle()
        await run.waitForTranslations()
        let reading = Self.footprint()
        // Only weak references are kept here: the check must not be what holds them.
        let overlays = run.pageViews.compactMap(\.translation.view).map { WeakBox($0) }
        let layers = run.pageViews.flatMap { $0.translation.view?.layer.sublayers ?? [] }.map { WeakBox($0) }
        let engine = WeakBox(run.engine)
        report.expect(
            "three pages have a view and an overlay", overlays.count == 3 && !layers.isEmpty,
            "\(overlays.count) overlays, \(layers.count) layers"
        )
        let bytes = run.pageViews.map { ReaderHarnessPatches.patchBytes(ofPage: $0.page) }
        report.note("       patch bitmaps of the pages with a view: "
            + bytes.map { String(format: "%.2f MB", Double($0) / 1_048_576) }.joined(separator: ", "))

        await run.jump(to: 30)
        await run.waitForTranslations()
        try? await Task.sleep(for: .milliseconds(500))
        let leftLayers = layers.count { $0.object != nil }
        report.expect("a jump away: the old pages' patch layers are gone", leftLayers == 0, "\(leftLayers) of \(layers.count) left")

        await closeReader()
        try? await Task.sleep(for: .seconds(1))
        let closed = Self.footprint()
        let leftOverlays = overlays.count { $0.object != nil }
        report.expect("the reader closed: the engine is gone", engine.object == nil, "")
        report.expect("and every overlay view", leftOverlays == 0, "\(leftOverlays) of \(overlays.count) left")
        report.note(String(
            format: "       footprint: %.1f MB before the reader, %.1f MB reading the originals, %.1f MB reading"
                + " with three overlays, %.1f MB after it closed",
            idle, plain, reading, closed
        ))
        let largest = (1...60).map { ReaderHarnessPatches.patchBytes(ofPage: $0) }.max() ?? 0
        report.note(String(format: "       the largest page's patch bitmaps: %.2f MB", Double(largest) / 1_048_576))
    }
}
#endif
