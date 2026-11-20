import EhFeatures
import SwiftUI
import UIKit

/// The page slider with the first and last page numbers at its ends, as Shelf's panel and
/// Ledger's sheet draw it. It follows the reading direction: right to left puts page 1 on the
/// right. It drives the model's slider: while it is held the reader stays and the thumbnail
/// strip follows it; letting go jumps to the chosen page.
struct ReaderSliderRow: View {
    let model: ReaderModel
    let isReversed: Bool

    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: Tokens.Spacing.medium) {
            endLabel(isReversed ? model.pageCount : 1)
            ReaderSliderTrack(model: model, isReversed: isReversed)
            endLabel(isReversed ? 1 : model.pageCount)
        }
    }

    private func endLabel(_ page: Int) -> some View {
        Text(verbatim: "\(page)")
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(look.secondaryLabel)
            .fixedSize()
            // The slider's value says "of 48".
            .accessibilityHidden(true)
    }
}

/// The bare slider, for a design that draws its own ends.
struct ReaderSliderTrack: View {
    let model: ReaderModel
    let isReversed: Bool

    var body: some View {
        ReaderUISlider(
            page: model.sliderPage, pageCount: model.pageCount, isReversed: isReversed,
            spokenPosition: ReaderPagePosition(model: model).long,
            onEditingChanged: { model.sliderEditingChanged($0) },
            onChange: { model.setSliderPage($0) }
        )
    }
}

/// A `UISlider` over the pages.
///
/// SwiftUI's `Slider` cannot say reliably when a drag ends: on iOS 26.3 its `onEditingChanged`
/// reports `false` when the finger lifts and then `true` once more, which left the strip up
/// after every scrub. `UISlider`'s control events are exact. It is not stepped, as a step would
/// draw a tick for every page.
private struct ReaderUISlider: UIViewRepresentable {
    let page: Int
    let pageCount: Int
    let isReversed: Bool
    /// "Page 23 of 48" or "End", VoiceOver's value.
    let spokenPosition: String
    let onEditingChanged: (Bool) -> Void
    let onChange: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UISlider {
        let slider = ReaderPageUISlider()
        slider.minimumValue = 1
        slider.accessibilityLabel = L10n.Localizable.Gallery.Figure.pages
        // The reading direction decides which way it runs, not the interface language.
        slider.semanticContentAttribute = .forceLeftToRight
        let coordinator = context.coordinator
        slider.addTarget(coordinator, action: #selector(Coordinator.touchDown), for: .touchDown)
        slider.addTarget(coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        slider.addTarget(
            coordinator, action: #selector(Coordinator.touchUp),
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )
        slider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return slider
    }

    func updateUIView(_ slider: UISlider, context: Context) {
        context.coordinator.slider = self
        slider.maximumValue = Float(max(pageCount, 2))
        // Mirrored for right to left, so page 1 is on the right and the track fills from there.
        let transform: CGAffineTransform = isReversed ? CGAffineTransform(scaleX: -1, y: 1) : .identity
        if slider.transform != transform {
            slider.transform = transform
        }
        // The finger owns the thumb while it is down.
        if !slider.isTracking, Int(slider.value.rounded()) != page {
            slider.setValue(Float(page), animated: false)
        }
        slider.accessibilityValue = spokenPosition
    }

    /// VoiceOver's swipe up or down turns one page, not the tenth of the range a `UISlider`
    /// steps by. Without a touch the model is not scrubbing, so the reader follows at once.
    private final class ReaderPageUISlider: UISlider {
        override func accessibilityIncrement() { step(by: 1) }
        override func accessibilityDecrement() { step(by: -1) }

        private func step(by pages: Float) {
            setValue(value.rounded() + pages, animated: false)
            sendActions(for: .valueChanged)
        }
    }

    final class Coordinator: NSObject {
        var slider: ReaderUISlider?

        @objc func touchDown() {
            slider?.onEditingChanged(true)
        }

        @objc func valueChanged(_ control: UISlider) {
            slider?.onChange(Int(control.value.rounded()))
        }

        @objc func touchUp() {
            slider?.onEditingChanged(false)
        }
    }
}
