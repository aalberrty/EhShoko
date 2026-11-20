import EhCore
import EhModels
import SwiftUI

/// The moving preview of the three presets (`Design/designs/settings.md`, "The moving
/// preview"): a 150 × 240 pt stage that plays each preset's storyboard, the preset's name,
/// the caption of the beat, a mark for each beat, and the three presets as still tiles that choose.
/// The wizard's first step and the offer after install host it; it has no other home.
///
/// - At first it plays Shelf, Wall and Ledger in turn. A tap on a tile selects that preset
///   and plays it from its first beat, and the stage stays on it. Setting `selection` to
///   `nil` (the wizard's "Keep what I have") lets the presets take turns again; setting it to
///   a preset from outside stays on that preset too.
/// - It plays only while it is seen: not while less than half of it is on screen, while the
///   app is not active, while it is not on screen at all (a screen pushed over it) or while
///   the host says it is covered (an alert). After 72 s of playing without a touch it stops on
///   the first beat. In Low Power Mode it does not start by itself. The pause button, or a tap
///   on the stage, stops and starts it.
/// - Under Reduce Motion, or with animated images turned off, nothing plays: the stage shows
///   one still per beat and a tap or a swipe on it turns to the next.
/// - To VoiceOver the stage is one adjustable element: the preset's name, a sentence of what
///   its animation shows, and swiping up or down for the next or previous preset.
///
/// Each preset is drawn in its own look, as a preset tile is; the labels around it are in the
/// app's look.
struct PresetStage: View {
    static let size = CGSize(width: 150, height: 240)
    /// The stage's row: the stage centred, the pause button 11 pt beside it.
    static let rowWidth: CGFloat = 260

    @Binding private var selection: DesignStyle?
    private let isCovered: Bool

    @State private var playback: StagePlayback
    /// The preset the stage stays on because it was chosen.
    @State private var pinned: DesignStyle?
    @State private var isStopped: Bool
    @State private var isOnScreen = true
    @State private var isShown = false
    /// The still showing under Reduce Motion, counted in pages.
    @State private var page: Double = 0
    @State private var choices = 0

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityPlayAnimatedImages) private var playsAnimatedImages
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.look) private var look
    @Environment(\.lookTint) private var tint
    @Environment(SettingsStore.self) private var settings

    /// - Parameters:
    ///   - selection: the preset the tiles select; a tap on a tile sets it.
    ///   - staysOnInitialSelection: whether the stage starts on the preset already selected
    ///     (the wizard, coming back to its first step) rather than taking turns until a tile
    ///     is tapped (the offer, where Shelf is selected because it is the default).
    ///   - isCovered: set while something the stage cannot see covers it, such as an alert.
    init(selection: Binding<DesignStyle?>, staysOnInitialSelection: Bool = false, isCovered: Bool = false) {
        _selection = selection
        self.isCovered = isCovered
        let initial = staysOnInitialSelection ? selection.wrappedValue : nil
        _pinned = State(initialValue: initial)
        _playback = State(initialValue: StagePlayback(first: initial ?? .shelf, takesTurns: initial == nil))
        _isStopped = State(initialValue: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    private var isStill: Bool { reduceMotion || !playsAnimatedImages }

    private var shouldPlay: Bool {
        isShown && isOnScreen && scenePhase == .active && !isCovered && !isStopped && !isStill
    }

    var body: some View {
        let palettes = StagePalettes(accent: settings.accentColor, colorScheme: colorScheme, contrast: contrast)
        TimelineView(StageBeatSchedule(anchor: playback.isRunning ? playback.anchor : nil)) { timeline in
            let now = beat(at: timeline.date)
            VStack(spacing: 0) {
                // The stage centred in its row, the pause button beside it at the row's
                // bottom trailing corner.
                ZStack(alignment: .bottomTrailing) {
                    stage(now, palettes: palettes)
                        .frame(maxWidth: .infinity)
                    if !isStill {
                        pauseButton
                            .padding([.trailing, .bottom], 6)
                    }
                }
                .frame(width: Self.rowWidth)
                labels(now)
                    .padding(.top, 8)
                marks(now)
                    .padding(.top, 2)
                StageTiles(selection: selection, playing: now.style, choose: choose)
                    .equatable()
                    .padding(.top, 4)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: choices)
        .onAppear { isShown = true }
        .onDisappear { isShown = false }
        .onChange(of: shouldPlay, initial: true) { _, play in
            if play { playback.run(at: .now) } else { playback.stop(at: .now) }
        }
        .onChange(of: selection) { _, selection in selectionChanged(to: selection) }
        .task(id: playback) { await stopWhenIdle() }
    }

    private func beat(at date: Date) -> StageBeat {
        if isStill { return StagePager.beat(at: page, of: playback) }
        let (style, beat) = playback.beat(at: playback.time(at: date))
        return StageBeat(style: style, beat: beat)
    }

    // MARK: Pieces

    private func stage(_ now: StageBeat, palettes: StagePalettes) -> some View {
        ZStack {
            if isStill {
                StageStill(position: page, playback: playback, palettes: palettes)
            } else {
                StageHost(playback: playback, palettes: palettes)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .contentShape(.rect(cornerRadius: StageRenderer.cornerRadius))
        .onTapGesture(perform: tapStage)
        .simultaneousGesture(swipe, including: isStill ? .all : .subviews)
        .onScrollVisibilityChange(threshold: 0.5) { isOnScreen = $0 }
        .accessibilityElement()
        .accessibilityLabel(Text(now.style.localizedName))
        .accessibilityValue(Text(now.style.stageSummary(tabBarTucks: playback.tabBarTucks)))
        .accessibilityAddTraits(.isImage)
        .accessibilityAdjustableAction(adjust)
    }

    private var pauseButton: some View {
        Button(action: togglePause) {
            Image(systemName: isStopped ? "play.fill" : "pause.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(look.label)
                .frame(width: 38, height: 38)
                .glassSurface(in: Circle(), isInteractive: true)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(isStopped ? L10n.Localizable.Settings.Design.Stage.play
                                 : L10n.Localizable.Settings.Design.Stage.pause))
    }

    private func labels(_ now: StageBeat) -> some View {
        VStack(spacing: 3) {
            Text(now.style.localizedName)
                .font(.headline)
                .foregroundStyle(look.label)
            Text(now.caption)
                .font(.footnote)
                .foregroundStyle(look.secondaryLabel)
        }
        .multilineTextAlignment(.center)
        // Not animated: a content transition on the labels redrew their text with every frame
        // of the canvas, on the main thread, the whole time the stage played.
        // The stage reads the preset's name; captions are not announced as they change.
        .accessibilityHidden(true)
    }

    /// A mark for each beat the preset plays (four, or three where Shelf skips its first), the
    /// current one in the tint. Under Reduce Motion they are the pager's
    /// marks and a tap on one turns to that beat.
    private func marks(_ now: StageBeat) -> some View {
        HStack(spacing: 0) {
            ForEach(playback.storyboard(now.style).playedBeats, id: \.self) { beat in
                Capsule()
                    .fill(beat == now.beat ? tint : look.fill)
                    .frame(width: 16, height: 4)
                    .frame(width: 21, height: 20)
                    .contentShape(.rect)
                    .onTapGesture { turn(toBeat: beat, from: now) }
                    .allowsHitTesting(isStill)
            }
        }
        .accessibilityHidden(true)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24).onEnded { drag in
            let width = drag.translation.width
            guard abs(width) > abs(drag.translation.height) else { return }
            turn(by: width < 0 ? 1 : -1)
        }
    }
}

// MARK: - What touches do

extension PresetStage {
    private func tapStage() {
        if isStill {
            turn(by: 1)
        } else {
            togglePause()
        }
    }

    private func togglePause() {
        if isStopped {
            playback.touch(at: .now)
        }
        isStopped.toggle()
    }

    private func choose(_ style: DesignStyle) {
        choices += 1
        selection = style
        pin(style)
    }

    /// Plays `style` from its first beat and stays on it.
    private func pin(_ style: DesignStyle) {
        pinned = style
        playback.show(style, takesTurns: false, at: .now)
        page = 0
        isStopped = false
    }

    private func selectionChanged(to selection: DesignStyle?) {
        guard selection != pinned else { return }
        if let selection {
            pin(selection)
        } else {
            pinned = nil
            let showing = StagePager.beat(at: page, of: playback)
            playback.takeTurns(at: .now)
            page = Double(StagePager.page(of: showing, in: playback))
        }
    }

    /// VoiceOver's swipe up or down: the next or previous preset, from its first beat.
    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        let current = beat(at: .now).style
        let order = StagePlayback.order
        let index = order.firstIndex(of: current) ?? 0
        let step = direction == .increment ? 1 : order.count - 1
        playback.show(order[(index + step) % order.count], takesTurns: playback.takesTurns, at: .now)
        page = 0
    }

    private func turn(by pages: Int) {
        withAnimation(.easeInOut(duration: 0.3)) { page += Double(pages) }
    }

    private func turn(toBeat beat: Int, from now: StageBeat) {
        turn(by: beat - now.beat)
    }

    /// Stops on the first beat once the stage has played for the idle limit without a touch.
    private func stopWhenIdle() async {
        guard let deadline = playback.idleStop else { return }
        try? await Task.sleep(for: .seconds(max(deadline.timeIntervalSinceNow, 0)))
        guard !Task.isCancelled else { return }
        isStopped = true
        playback.rewind()
    }
}
