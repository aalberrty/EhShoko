import EhFeatures
import SwiftUI

private typealias Strings = L10n.Localizable.Reader.Translate

/// Compare (`README` 7.4; `wall.md` and `ledger.md`, section 5): a vertical line over the
/// pages, with the original on its left and the translation on its right, and a handle that
/// drags it across. The 原文 and 译文 labels name the two sides, at the top, below Close.
///
/// `ReaderScreen` places it between the engine and the controls, so it stays while the
/// controls hide, and it is the same whichever design drives the display: Wall's pill and
/// Ledger's Compare only choose `.compare`. It is in the hierarchy only while the reader
/// compares, not on the closing page, which is not a page.
///
/// **What a drag costs.** The line's place is `@State` of the wipe alone, and the model's
/// `setCompareFraction(_:)` hands it straight to the engine, where each page view narrows its
/// overlay's bounds (`ReaderTranslationOverlayView.showOnly(fromX:)`). Nothing observable
/// changes, so a drag re-renders the wipe's few shapes and nothing else, and no bitmap is
/// made: the original is the page's own image, the translation its overlay.
struct ReaderTranslationWipe: View {
    let model: ReaderModel
    let viewport: ReaderViewport

    var body: some View {
        let translation = model.translation
        let isComparing = translation.isOn && translation.displayMode == .compare
            && !translation.isHoldingOriginal && !model.isAtEnd
        ZStack {
            if isComparing {
                ReaderTranslationWipeLayer(translation: translation, viewport: viewport)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.2), value: isComparing)
    }
}

/// The line, its handle and the two labels, over the engine's own frame.
private struct ReaderTranslationWipeLayer: View {
    let translation: ReaderTranslationModel
    let viewport: ReaderViewport

    /// The line's place across the engine's width, from 0 to 1; read from the model the first
    /// time, so the wipe comes back where it was left.
    @State private var fraction: CGFloat?
    /// The fraction when the finger came down on the handle.
    @State private var dragStart: CGFloat?
    /// The engine's frame and the safe area's, on the screen: in landscape the sensor housing
    /// lies between the two.
    @State private var frame: CGRect = .zero
    @State private var safeFrame: CGRect = .zero

    private var width: CGFloat { frame.width }

    var body: some View {
        let current = fraction ?? CGFloat(translation.compareFraction)
        GlassGroup {
            ZStack {
                ReaderTranslationWipeLabels(lineX: current * width, width: width)
                ZStack(alignment: .leading) {
                    Color.clear
                        .allowsHitTesting(false)
                    ReaderTranslationWipeColumn(handle: handle(current))
                        .offset(x: current * width - ReaderTranslationWipeMetrics.handleSize / 2)
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { newFrame in
                    frame = newFrame
                    keepHandleInside()
                }
                // The engine's own frame (`ReaderEngineFrame`), so the line's fraction is the
                // engine's. The covered bottom (Ledger's open sheet over the strip) only
                // moves the handle up into the part that shows.
                .padding(.bottom, viewport.coveredBottom)
                .padding(.bottom, viewport.bottomInset)
                .ignoresSafeArea()
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { newFrame in
                safeFrame = newFrame
                keepHandleInside()
            }
        }
    }

    private func handle(_ current: CGFloat) -> some View {
        ReaderTranslationWipeHandle(fraction: current) { newFraction in
            move(to: newFraction)
        }
        .gesture(drag)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = dragStart ?? fraction ?? CGFloat(translation.compareFraction)
                if dragStart == nil { dragStart = start }
                guard width > 0 else { return }
                move(to: start + value.translation.width / width)
            }
            .onEnded { _ in dragStart = nil }
    }

    /// Keeps the handle whole on the screen and clear of the sensor housing (8 pt inside the
    /// safe area's side), then tells the model, which tells the engine.
    private func move(to newFraction: CGFloat) {
        guard width > 0 else { return }
        let leadingInset = safeFrame.isEmpty ? 0 : max(safeFrame.minX - frame.minX, 0)
        let trailingInset = safeFrame.isEmpty ? 0 : max(frame.maxX - safeFrame.maxX, 0)
        let half = ReaderTranslationWipeMetrics.handleSize / 2 + Tokens.Spacing.small
        let lower = (leadingInset + half) / width
        let upper = 1 - (trailingInset + half) / width
        guard lower < upper else { return }
        let clamped = min(max(newFraction, lower), upper)
        guard clamped != fraction else { return }
        fraction = clamped
        translation.setCompareFraction(clamped)
    }

    /// After a turn or a resize, the line keeps its fraction unless the handle would leave the
    /// room `move(to:)` allows.
    private func keepHandleInside() {
        move(to: fraction ?? CGFloat(translation.compareFraction))
    }
}

enum ReaderTranslationWipeMetrics {
    /// The handle's diameter (the mockup's 45, on the 44 pt grid of the reader's controls).
    static let handleSize: CGFloat = 44
    /// The line's width.
    static let lineWidth: CGFloat = 3
    /// The labels' height.
    static let labelHeight: CGFloat = 26
}

/// The line from the top of the engine's frame to its bottom, interrupted by the handle in the
/// middle. The line is the page's divider, not a control: white with a dark hairline on both
/// sides, which shows on white paper and on black panels alike, and takes no touches.
private struct ReaderTranslationWipeColumn<Handle: View>: View {
    let handle: Handle

    var body: some View {
        VStack(spacing: 0) {
            segment
            handle
            segment
        }
        .frame(width: ReaderTranslationWipeMetrics.handleSize)
    }

    private var segment: some View {
        Rectangle()
            .fill(.white)
            .frame(width: ReaderTranslationWipeMetrics.lineWidth)
            .overlay {
                Rectangle().strokeBorder(.black.opacity(0.35), lineWidth: 0.5)
            }
            .frame(maxHeight: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The handle: a glass circle with a left-and-right arrow, which the finger drags. VoiceOver
/// reads it as an adjustable control: swiping up or down moves the line by a tenth.
private struct ReaderTranslationWipeHandle: View {
    let fraction: CGFloat
    let move: (CGFloat) -> Void

    @Environment(\.look) private var look

    var body: some View {
        Image(systemName: "arrow.left.and.right")
            .font(.body.weight(.semibold))
            .foregroundStyle(look.label)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .frame(width: ReaderTranslationWipeMetrics.handleSize, height: ReaderTranslationWipeMetrics.handleSize)
            .contentShape(.circle)
            .glassSurface(in: .circle, isInteractive: true)
            .accessibilityElement()
            .accessibilityLabel(Strings.A11y.wipe)
            .accessibilityValue(Double(fraction).formatted(.percent.precision(.fractionLength(0))))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: move(fraction + 0.1)
                case .decrement: move(fraction - 0.1)
                @unknown default: break
                }
            }
    }
}

/// 原文 at the leading edge and 译文 at the trailing edge, at the top below Close: the original
/// is left of the line and the translation right of it, as drawn (`recommended/02`), whatever
/// the reading direction. A label the line reaches fades, so it never names the wrong side.
/// The labels are in the same words in every language, as Wall's pill is.
private struct ReaderTranslationWipeLabels: View {
    let lineX: CGFloat
    let width: CGFloat

    /// The room a label needs beside the line: its width and the edge inset.
    private static let room: CGFloat = 76

    var body: some View {
        HStack {
            ReaderTranslationWipeLabel(text: Strings.Wipe.original)
                .opacity(lineX > Self.room ? 1 : 0)
            Spacer(minLength: 0)
            ReaderTranslationWipeLabel(text: Strings.Wipe.translated)
                .opacity(lineX < width - Self.room ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.15), value: lineX > Self.room)
        .animation(.easeOut(duration: 0.15), value: lineX < width - Self.room)
        .padding(.horizontal, ReaderMetrics.edgeInset)
        .padding(.top, ReaderMetrics.topInset + ReaderMetrics.closeSize + Tokens.Spacing.small)
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ReaderTranslationWipeLabel: View {
    let text: String

    @Environment(\.look) private var look

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(look.label)
            .lineLimit(1)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .padding(.horizontal, Tokens.Spacing.small + 2)
            .frame(height: ReaderTranslationWipeMetrics.labelHeight)
            .glassSurface(in: .capsule)
    }
}
