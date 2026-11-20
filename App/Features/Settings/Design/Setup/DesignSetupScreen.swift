import EhCore
import EhFeatures
import EhModels
import SwiftUI

private typealias Setup = L10n.Localizable.Settings.Design.Setup

/// Settings › Experience setup (`settings.md`, "The setup wizard"): start from a preset, one
/// step per page, then a summary whose "Apply" writes the draft once.
///
/// - Everything is chosen on the model's draft; nothing applies until "Apply". The direct
///   pickers (the tiles, the chips, the options screens) keep applying at once.
/// - The controls are the sheet's bottom toolbar (glass on iOS 26). Close replaces Back at
///   the top leading edge; it asks before discarding a changed draft, and the sheet cannot be
///   swiped away while the draft differs from the current choices.
/// - Each step is its own scroll view, so a step opens at its top; steps slide in the
///   direction of travel, or cross-fade under Reduce Motion.
struct DesignSetupScreen: View {
    @State private var model: DesignSetupModel
    @State private var direction = Direction.forward
    /// A move waiting for the step on screen to take the new direction (see `move(_:)`).
    @State private var pendingMove: Move?
    @State private var asksToDiscard = false
    @State private var choices = 0
    @State private var applied = 0
    /// The step's scroll view's height inside the bars: a page's step fits its cards to it.
    @State private var visibleHeight: CGFloat = 0

    /// The space under a step's last piece.
    static let bottomPadding = Tokens.Spacing.xLarge

    @Environment(\.dismiss) private var dismiss
    @Environment(\.look) private var look
    @Environment(\.lookTint) private var tint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameter startingPoint: a preset the draft starts as (the offer's choice); `nil`
    ///   starts from the current choices with "Keep what I have" selected.
    init(startingPoint: DesignStyle? = nil) {
        _model = State(initialValue: DesignSetupModel(startingPoint: startingPoint))
    }

    var body: some View {
        ZStack {
            step
                .id(model.step)
                .transition(reduceMotion ? .opacity : .push(from: direction == .forward ? .trailing : .leading))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(look.surface)
        .topBar {
            DesignSetupProgress(reached: model.stepNumber ?? DesignSetupModel.stepCount, total: DesignSetupModel.stepCount)
        }
        .screenSubtitle(
            model.stepNumber.map { Setup.step($0, DesignSetupModel.stepCount) } ?? Setup.summary,
            title: Setup.title
        )
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar { DesignSetupControls(model: model, tint: tint, close: close, move: move, finish: finish) }
        .interactiveDismissDisabled(model.hasChanges)
        .alert(Setup.Discard.title, isPresented: $asksToDiscard) {
            Button(Setup.Discard.confirm, role: .destructive) { dismiss() }
            Button(Setup.Discard.keep, role: .cancel) {}
        }
        .sensoryFeedback(.selection, trigger: choices)
        .sensoryFeedback(.success, trigger: applied)
        .onChange(of: direction) { performPendingMove() }
        // After the haptic has seen the change: back to the Settings page.
        .onChange(of: applied) { dismiss() }
        #if DEBUG || HARNESS
        .onAppear {
            DesignSetupProbe.shared.wizardAppeared(
                .init(model: model, move: move, cover: { asksToDiscard = $0 }, finish: finish)
            )
        }
        #endif
    }

    @ViewBuilder private var step: some View {
        ScrollView {
            Group {
                switch model.step {
                case .start:
                    DesignSetupStartStep(model: model, isCovered: asksToDiscard)
                case .part(let part):
                    DesignSetupPartStep(model: model, part: part, visibleHeight: visibleHeight) { choices += 1 }
                case .summary:
                    DesignSetupSummary(model: model) { move(.open($0)) }
                }
            }
            .padding(.horizontal, Tokens.Spacing.large)
            .padding(.bottom, Self.bottomPadding)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom
        } action: { _, height in
            visibleHeight = height
        }
    }

    // MARK: Moving

    enum Direction {
        case forward, backward
    }

    enum Move: Equatable {
        case next, skip, back
        /// A line of the summary.
        case open(DesignPart)

        var direction: Direction {
            switch self {
            case .next, .skip: .forward
            case .back, .open: .backward
            }
        }
    }

    /// Moves to another step, sliding the way it goes.
    ///
    /// The step that leaves takes its transition from its last update, so when the way
    /// changes, the direction changes first and the move follows from `onChange`, once the
    /// step on screen has taken it.
    private func move(_ move: Move) {
        guard move.direction == direction else {
            pendingMove = move
            direction = move.direction
            return
        }
        perform(move)
    }

    private func performPendingMove() {
        guard let move = pendingMove else { return }
        pendingMove = nil
        perform(move)
    }

    private func perform(_ move: Move) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.35)) {
            switch move {
            case .next: model.next()
            case .skip: model.skip()
            case .back: model.back()
            case .open(let part): model.jump(to: part)
            }
        }
    }

    // MARK: Leaving

    private func close() {
        if model.hasChanges {
            asksToDiscard = true
        } else {
            dismiss()
        }
    }

    /// "Apply" writes the draft once and leaves after the success haptic; "Done", with
    /// nothing changed, just leaves.
    private func finish() {
        if model.apply() {
            applied += 1
        } else {
            dismiss()
        }
    }
}

/// The wizard's controls: Close at the top leading edge; Back, Skip and the primary button
/// (Next, "Back to summary", Apply or Done) in the sheet's bottom toolbar.
private struct DesignSetupControls: ToolbarContent {
    let model: DesignSetupModel
    /// The tint, set on the primary button: a prominent glass button in a sheet can lose the
    /// inherited one (`spikes/S5.md`).
    let tint: Color
    let close: () -> Void
    let move: (DesignSetupScreen.Move) -> Void
    let finish: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            SheetCloseButton(action: close)
        }
        switch model.step {
        case .start:
            // Alone in the bar, so it may take the bar's width.
            ToolbarItem(placement: .bottomBar) {
                primary(model.returnsToSummary ? Setup.backToSummary : Setup.next, wide: true) { move(.next) }
            }
        case .part:
            ToolbarItem(placement: .bottomBar) { back }
            ToolbarItem(placement: .bottomBar) {
                Button(Setup.skip) { move(.skip) }
            }
            BottomToolbarSpacer()
            ToolbarItem(placement: .bottomBar) {
                primary(model.returnsToSummary ? Setup.backToSummary : Setup.next) { move(.next) }
            }
        case .summary:
            ToolbarItem(placement: .bottomBar) { back }
            BottomToolbarSpacer()
            ToolbarItem(placement: .bottomBar) {
                primary(model.hasChanges ? Setup.apply : L10n.Localizable.EhSettingView.ToolbarItem.Button.done) {
                    finish()
                }
            }
        }
    }

    private var back: some View {
        Button { move(.back) } label: {
            Image(systemName: "chevron.backward")
        }
        .accessibilityLabel(L10n.Localizable.Common.back)
    }

    /// The prominent, tinted button.
    private func primary(_ title: String, wide: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.semibold)
                .padding(.horizontal, Tokens.Spacing.small)
                .frame(maxWidth: wide ? .infinity : nil)
        }
        .glassProminentButtonStyle()
        .tint(tint)
    }
}
