#if DEBUG || HARNESS
import EhFeatures
import SwiftUI

/// A screen for exercising the reader engine by hand, with a synthetic gallery.
///
/// What to expect from the gallery: page 4 is a very long strip, page 5 an animated GIF, page 8
/// a wide panorama, every 9th page a large original (zooming in should sharpen it), every 6th a
/// landscape page. Every 7th page fails to resolve once and every 11th fails to load once, so
/// both retry paths can be tried. After the last page comes the slot of the closing page, with
/// a stand-in in it.
///
/// Launched with a check (`ReaderHarnessOptions`), it drives readers by itself and writes down
/// what it finds.
struct ReaderHarnessView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session = ReaderHarnessSession()

    var body: some View {
        ZStack {
            Color(uiColor: .readerBackground).ignoresSafeArea()
            if let model = session.model {
                ReaderHarnessReader(model: model) { dismiss() }
                    .id(session.readerID)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let status = session.status {
                Text(verbatim: status)
                    .font(.caption2)
                    .padding(6)
                    .background(.regularMaterial, in: .rect(cornerRadius: 8))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { session.viewSize = $0 }
        .task { await session.start() }
        .onDisappear { session.stop() }
    }
}

/// One reader: the engine, what it reports, and the panel that drives it by hand.
private struct ReaderHarnessReader: View {
    let model: ReaderHarnessModel
    let close: () -> Void

    var body: some View {
        ReaderEngineView(
            configuration: model.configuration, initialPage: model.setup.startPage, proxy: model.proxy,
            dataSource: model, delegate: model, probe: model.recorder.map { recorder in { recorder.add($0) } }
        )
        .ignoresSafeArea()
        .overlay(alignment: .top) { status }
        .overlay(alignment: .bottom) {
            if model.isPanelVisible {
                ReaderHarnessPanel(model: model, close: close)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.default, value: model.isPanelVisible)
        .statusBarHidden(!model.isPanelVisible)
        .onDisappear { model.stop() }
    }

    private var status: some View {
        VStack(spacing: 2) {
            // The closing page is not a page: on it the label says so instead of a number.
            Text(verbatim: model.isAtEnd ? "End" : "\(model.currentPage) / \(model.galleryPageCount)")
                .font(.headline.monospacedDigit())
            if model.isPanelVisible {
                ForEach(Array(model.events.enumerated()), id: \.offset) { _, event in
                    Text(verbatim: event).font(.caption2)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .padding(.top, 4)
        .allowsHitTesting(false)
    }
}

private struct ReaderHarnessPanel: View {
    @Bindable var model: ReaderHarnessModel
    let close: () -> Void

    @State private var sliderPage = 1.0
    @State private var isDraggingSlider = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                navigation
                Divider()
                layout
                Divider()
                zoomAndLoading
                Divider()
                actions
            }
            .padding(14)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: 520)
        .containerRelativeFrame(.vertical) { height, _ in min(max(height * 0.42, 230), height - 70) }
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
        .padding(.horizontal, 10)
        .font(.footnote)
        .onAppear { sliderPage = Double(model.currentPage) }
        .onChange(of: model.currentPage) { _, page in
            // The slider follows the reader, except while a finger is on it.
            if !isDraggingSlider {
                sliderPage = Double(page)
            }
        }
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: "Go to \(Int(sliderPage))")
                Slider(value: $sliderPage, in: 1...Double(max(model.galleryPageCount, 2)), step: 1) { editing in
                    isDraggingSlider = editing
                    if !editing {
                        model.proxy.scrollToPage(Int(sliderPage))
                    }
                }
            }
            HStack {
                Button("First") { model.proxy.scrollToPage(1) }
                Button("Back (animated)") { model.proxy.scrollToPage(model.currentPage - 1, animated: true) }
                Button("Next (animated)") { model.proxy.advance() }
                Button("Last") { model.proxy.scrollToPage(model.galleryPageCount) }
            }
            .buttonStyle(.bordered)
            Picker("Auto-advance", selection: $model.autoAdvanceInterval) {
                Text(verbatim: "Auto off").tag(0.0)
                ForEach([1.0, 2.0, 3.0], id: \.self) { seconds in
                    Text(verbatim: "\(Int(seconds)) s").tag(seconds)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var layout: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Direction", selection: $model.configuration.direction) {
                Text(verbatim: "Vertical").tag(ReaderDirection.vertical)
                Text(verbatim: "Left to right").tag(ReaderDirection.leftToRight)
                Text(verbatim: "Right to left").tag(ReaderDirection.rightToLeft)
            }
            .pickerStyle(.segmented)
            Toggle("Dual page (paged, landscape)", isOn: $model.configuration.allowsDualPage)
            Toggle("Except cover", isOn: $model.configuration.exceptCover)
            Stepper(value: $model.configuration.pageGap, in: 0...20, step: 5) {
                Text(verbatim: "Gap \(Int(model.configuration.pageGap)) pt (vertical)")
            }
            Picker("Pages", selection: Binding(get: { model.galleryPageCount }, set: { model.setPageCount($0) })) {
                ForEach([1, 2, 3, 60, 1_000], id: \.self) { count in
                    Text(verbatim: "\(count)").tag(count)
                }
            }
            .pickerStyle(.segmented)
            Toggle("Closing page slot", isOn: $model.showsClosingSlot)
        }
    }

    private var zoomAndLoading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Stepper(value: $model.configuration.maximumZoomScale, in: 1.5...10, step: 0.5) {
                Text(verbatim: "Maximum zoom \(model.configuration.maximumZoomScale.formatted())×")
            }
            Stepper(value: $model.configuration.doubleTapZoomScale, in: 1.5...5, step: 0.5) {
                Text(verbatim: "Double-tap zoom \(model.configuration.doubleTapZoomScale.formatted())×")
            }
            Stepper(value: $model.configuration.prefetchLimit, in: 6...18, step: 4) {
                Text(verbatim: "Preload limit \(model.configuration.prefetchLimit)")
            }
            Stepper(value: $model.latency, in: 0...4, step: 0.4) {
                Text(verbatim: "Latency \(model.latency.formatted()) s (resolve, then download)")
            }
            Toggle("Host knows aspect ratios", isOn: $model.knowsAspectRatios)
            Toggle(isOn: $model.configuration.isLiveTextEnabled) {
                Text(verbatim: ReaderLiveText.isSupported ? "Live Text" : "Live Text (not supported here)")
            }
        }
    }

    private var actions: some View {
        HStack {
            Button("Reload all") { model.resetPages() }
            Button("Clear image cache") { model.clearImageCache() }
            Spacer()
            Button("Close", role: .cancel, action: close)
        }
        .buttonStyle(.bordered)
    }
}

/// Opens the reader harness. It sits in Settings › Laboratory in debug builds, and launching
/// the app with `-ReaderHarness YES` opens the harness as soon as that screen appears.
struct ReaderHarnessLauncher: View {
    private static var hasOpenedAtLaunch = false

    @State private var isPresented = false

    var body: some View {
        Button("Reader harness") { isPresented = true }
            .fullScreenCover(isPresented: $isPresented) { ReaderHarnessView() }
            .onAppear {
                guard !Self.hasOpenedAtLaunch, UserDefaults.standard.bool(forKey: "ReaderHarness") else { return }
                Self.hasOpenedAtLaunch = true
                isPresented = true
            }
    }
}
#endif
