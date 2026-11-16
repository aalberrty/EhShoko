#if DEBUG || HARNESS
import EhCore
import EhFeatures
import SwiftUI

/// A list view under test with 500 synthetic galleries, and the scripted scroll that measures it.
///
/// Opened from Settings › Laboratory, or as the whole app with `-Harness list` (see
/// `ListHarnessOptions` for the arguments and `Scripts/measure.sh` for recording a
/// run with Instruments). The list sits in a navigation stack with an inline title, as list
/// screens do; the controls are in the toolbar and an opaque status line, so nothing translucent
/// is added over the list being measured.
struct ListHarnessView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ListHarnessModel
    /// Cells push galleries onto the stack in the environment; the harness has no destinations.
    @State private var stack = StackRouter()
    private let isClosable: Bool

    init(options: ListHarnessOptions, isClosable: Bool = false) {
        _model = State(initialValue: ListHarnessModel(options: options))
        self.isClosable = isClosable
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text(verbatim: "List harness"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ListHarnessStatus(phase: model.phase, options: model.options)
                }
        }
        .environment(stack)
        .task { await model.start() }
        .onDisappear { model.stop() }
    }

    @ViewBuilder
    private var content: some View {
        if model.phase == .preparing {
            ProgressView()
        } else {
            ListHarnessSlotView(slot: model.options.slot, galleries: model.galleries, settings: model.settings)
                .background { ListHarnessAnchor(scroller: model.scroller) }
                .overlay(alignment: .bottom) {
                    if model.options.showsDock {
                        ListHarnessDock()
                    } else if model.options.showsBar {
                        ListHarnessBar(settings: model.settings)
                    }
                }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if isClosable {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: { Text(verbatim: "Close") }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker(selection: $model.options.slot) {
                    ForEach(ListHarnessSlot.allCases) { slot in
                        Text(verbatim: slot.rawValue).tag(slot)
                    }
                } label: {
                    Text(verbatim: "List")
                }
                Toggle(isOn: $model.options.showsTags) { Text(verbatim: "Tags in rows") }
                Toggle(isOn: $model.options.showsDock) { Text(verbatim: "Dock over the list") }
                Toggle(isOn: $model.options.showsBar) { Text(verbatim: "Command bar over the list") }
                Picker(selection: $model.options.speed) {
                    ForEach([1_000.0, 2_000, 4_000], id: \.self) { speed in
                        Text(verbatim: "\(Int(speed)) pt/s").tag(speed)
                    }
                } label: {
                    Text(verbatim: "Speed")
                }
            } label: {
                Label { Text(verbatim: "Options") } icon: { Image(systemName: "slider.horizontal.3") }
            }
            .disabled(model.phase == .running)
        }
        ToolbarItem(placement: .confirmationAction) {
            if model.phase == .running {
                Button { model.stop() } label: { Text(verbatim: "Stop") }
            } else {
                Button { Task { await model.run() } } label: { Text(verbatim: "Run") }
                    .disabled(model.phase == .preparing)
            }
        }
    }
}

/// One opaque line under the list: what is under test, then the last run's numbers.
private struct ListHarnessStatus: View {
    let phase: ListHarnessModel.Phase
    let options: ListHarnessOptions

    var body: some View {
        Text(verbatim: text)
            .font(.caption.monospacedDigit())
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemBackground))
    }

    private var text: String {
        let chrome = options.showsDock ? " + dock" : options.showsBar ? " + bar" : ""
        let setup = "\(options.slot.rawValue)\(chrome) · \(options.galleryCount) galleries · \(Int(options.speed)) pt/s"
        switch phase {
        case .preparing: return "Preparing \(setup)"
        case .ready: return "\(setup) · Run scrolls to the end"
        case .running: return "Scrolling \(setup)"
        case .finished(let result): return result.summary
        case .failed(let message): return message
        }
    }
}

/// A gallery page's dock over the list, in its glass container, as the shell's bottom chrome
/// places it (an overlay; the list keeps its full height, so rows pass under the glass).
private struct ListHarnessDock: View {
    var body: some View {
        GlassGroup(spacing: ActionDock.spacing) {
            ActionDock(content: Self.content) { _ in }
                .frame(maxWidth: 560)
        }
        .padding(.horizontal, Tokens.Spacing.medium)
        .padding(.bottom, Tokens.Spacing.small)
    }

    private static let content = DockContent(
        leading: DockItem(title: L10n.Localizable.List.Action.favorite, systemImage: "heart", action: .favorite),
        primary: DockItem(
            title: L10n.Localizable.Gallery.continue, detail: L10n.Localizable.Gallery.Continue.page(23, 48),
            action: .read
        ),
        trailing: .button(DockItem(
            title: L10n.Localizable.CommentsView.Title.comments, systemImage: "bubble.left.and.bubble.right",
            action: .comments
        ))
    )
}

/// The command bar over the list, in its glass container, as the shell's bottom chrome places
/// it (an overlay; the list keeps its full height, so rows pass under the glass). It reads the
/// harness's settings, whose first screen is Wall's, so it names Front Page as its place.
private struct ListHarnessBar: View {
    let settings: SettingsStore
    @State private var router = AppRouter()
    @Namespace private var glass

    var body: some View {
        GlassGroup(spacing: ActionDock.spacing) {
            CommandBar(
                router: router,
                control: .button(systemImage: "line.3.horizontal.decrease", title: "Filters", narrowing: "8 of 10 categories"),
                perform: { _ in }, openSearch: { _ in }
            )
            .frame(maxWidth: 560)
            .frame(height: ActionDock.height)
        }
        // The shell's margins (`BottomChrome`).
        .padding(.horizontal, 12)
        .padding(.bottom, Tokens.Spacing.small)
        .environment(\.chromeNamespace, glass)
        .environment(settings)
        .environment(router)
    }
}

/// Opens the list harness from Settings › Laboratory.
struct ListHarnessLauncher: View {
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: { Text(verbatim: "List harness") }
            .fullScreenCover(isPresented: $isPresented) {
                ListHarnessView(options: .default, isClosable: true)
            }
    }
}
#endif
