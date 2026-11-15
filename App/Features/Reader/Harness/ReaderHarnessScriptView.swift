#if DEBUG || HARNESS
import EhFeatures
import QuartzCore
import SwiftUI
import UIKit

/// The scripted run's screen: the engine of the run in progress, and what it is doing.
struct ReaderHarnessScriptView: View {
    @State private var script: ReaderHarnessScript

    init(pairs: [ReaderHarnessPair], pose: ReaderHarnessRun? = nil, checksRotation: Bool = false) {
        _script = State(initialValue: ReaderHarnessScript(pairs: pairs, pose: pose, checksRotation: checksRotation))
    }

    var body: some View {
        ZStack {
            Color(uiColor: .readerBackground)
                .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height } action: { script.isLandscape = $0 }
                .ignoresSafeArea()
            if let model = script.model {
                ReaderHarnessScriptEngine(model: model)
            }
        }
        .overlay(alignment: .top) { ReaderHarnessScriptLabel(script: script) }
        .statusBarHidden()
        .task { await script.start() }
    }
}

/// The run's engine, in a view of its own so that nothing the label shows re-renders it.
private struct ReaderHarnessScriptEngine: View {
    let model: ReaderHarnessModel
    /// Read once: the engine takes its first page when it is made.
    @State private var initialPage: Int

    init(model: ReaderHarnessModel) {
        self.model = model
        _initialPage = State(initialValue: model.currentPage)
    }

    var body: some View {
        ReaderEngineView(
            configuration: model.configuration, initialPage: initialPage,
            proxy: model.proxy, dataSource: model, delegate: model
        )
        .ignoresSafeArea()
    }
}

/// What the run is doing, and "End" on the closing page.
private struct ReaderHarnessScriptLabel: View {
    let script: ReaderHarnessScript

    var body: some View {
        Text(verbatim: label)
            .font(.footnote.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: .capsule)
            .padding(.top, 6)
            .allowsHitTesting(false)
    }

    private var label: String {
        guard let model = script.model else { return script.status }
        let page = model.isAtEnd ? "End" : "\(model.currentPage) / \(model.galleryPageCount)"
        return "\(script.status) · \(page)"
    }
}

/// Counts the frames the main thread delivered late while a step ran (from spike S4). It sees
/// main-thread stalls, not the render server.
final class ReaderHarnessFrameMeter: NSObject {
    private var link: CADisplayLink?
    private var previous: CFTimeInterval = 0
    private var nominal: CFTimeInterval = 1.0 / 60
    private var intervals: [CFTimeInterval] = []

    func start() {
        link?.invalidate()
        intervals = []
        previous = 0
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() -> String {
        link?.invalidate()
        link = nil
        guard !intervals.isEmpty, nominal > 0 else { return "no frames" }
        let late = intervals.filter { $0 > nominal * 1.5 }
        return String(format: "%d frames, %d late, worst %.0f ms", intervals.count, late.count, (intervals.max() ?? 0) * 1_000)
    }

    @objc private func tick(_ link: CADisplayLink) {
        nominal = link.duration
        if previous > 0 {
            intervals.append(link.timestamp - previous)
        }
        previous = link.timestamp
    }
}
#endif
