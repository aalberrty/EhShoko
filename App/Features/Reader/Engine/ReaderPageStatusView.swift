import EhModels
import SwiftUI
import UIKit

/// What a page shows while it has no image (`ledger.md` section 5, the same in every reader
/// design): "PAGE 23" in small capitals over a spinner while its URL is resolved; a progress
/// ring and the percentage while it downloads; a short card with a warning, "This page didn't
/// load" and a Retry pill when it failed. It keeps the page's full height, and in a very long
/// page its content stays near the top.
///
/// It is content, never glass, in the look's colours and title face (`ReaderPageStyle`, which
/// the reader hands down from SwiftUI's environment as a trait).
final class ReaderPageStatusView: UIView {
    enum Mode: Equatable {
        /// The image URL is being resolved.
        case resolving
        /// The image is downloading or decoding.
        case loading
        /// Resolving or loading failed.
        case failed
    }

    var onRetry: (() -> Void)?

    private let kickerLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let ring = ReaderProgressRing()
    private let percentLabel = UILabel()
    private let card = UIView()
    private let symbolView = UIImageView()
    private let messageLabel = UILabel()
    private let retryButton = UIButton(configuration: .tinted())
    private var mode: Mode?
    private var page = 0
    private var percent = -1

    /// In a very long page the middle can be screens away, so the content stays near the top.
    private static let maximumCenterY: CGFloat = 400
    private static let ringSize: CGFloat = 44
    private static let cardMaximumWidth: CGFloat = 300
    private static let cardPadding: CGFloat = 20
    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .readerBackground

        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        card.isHidden = true
        addSubview(card)

        kickerLabel.textAlignment = .center
        kickerLabel.adjustsFontForContentSizeCategory = true
        addSubview(kickerLabel)

        spinner.hidesWhenStopped = true
        addSubview(spinner)

        ring.isHidden = true
        addSubview(ring)
        percentLabel.textAlignment = .center
        percentLabel.font = UIFont.monospacedDigitSystemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize, weight: .medium
        )
        percentLabel.isHidden = true
        addSubview(percentLabel)

        symbolView.image = UIImage(systemName: "exclamationmark.triangle")
        symbolView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .title2)
        symbolView.contentMode = .center
        symbolView.isHidden = true
        addSubview(symbolView)

        messageLabel.text = L10n.Localizable.Reader.Page.failed
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.isHidden = true
        addSubview(messageLabel)

        var retry = UIButton.Configuration.tinted()
        retry.title = L10n.Localizable.ErrorView.Button.retry
        retry.image = UIImage(systemName: "arrow.clockwise")
        retry.imagePadding = 6
        retry.cornerStyle = .capsule
        retryButton.configuration = retry
        retryButton.isHidden = true
        retryButton.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .primaryActionTriggered)
        addSubview(retryButton)

        applyStyle()
        registerForTraitChanges(
            [
                ReaderPageStyleTrait.self, UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self,
                UITraitPreferredContentSizeCategory.self
            ],
            action: #selector(traitsDidChange)
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setPageNumber(_ page: Int) {
        self.page = page
        updateKicker()
        setNeedsLayout()
    }

    func setMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode
        let isFailed = newMode == .failed
        card.isHidden = !isFailed
        symbolView.isHidden = !isFailed
        messageLabel.isHidden = !isFailed
        retryButton.isHidden = !isFailed
        ring.isHidden = newMode != .loading
        percentLabel.isHidden = newMode != .loading
        if newMode == .loading {
            setProgress(0)
        }
        if newMode == .resolving {
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
        }
        setNeedsLayout()
    }

    func setProgress(_ fraction: Float) {
        let fraction = min(max(fraction, 0), 1)
        ring.progress = CGFloat(fraction)
        // Downloads report many times a second; the text changes once per percent.
        let newPercent = Int(fraction * 100)
        guard newPercent != percent else { return }
        percent = newPercent
        percentLabel.text = Self.percentFormatter.string(from: NSNumber(value: Double(newPercent) / 100))
    }

    /// Stops the spinner while the view is hidden or waiting in the reuse pool.
    func pause() {
        mode = nil
        spinner.stopAnimating()
    }

    // MARK: Style

    @objc private func traitsDidChange() {
        applyStyle()
        setNeedsLayout()
    }

    private func applyStyle() {
        let style = traitCollection.readerPageStyle
        let look = style.look
        let traits = traitCollection
        let tint = look.pageTint(for: style.accent).uiTint
        let secondary = look.uiSecondaryLabel.resolvedColor(with: traits)

        updateKicker()
        spinner.color = secondary
        percentLabel.textColor = secondary
        symbolView.tintColor = secondary
        ring.trackColor = UIColor(look.fill).resolvedColor(with: traits)
        ring.progressColor = tint.resolvedColor(with: traits)
        card.backgroundColor = UIColor(look.raised).resolvedColor(with: traits)

        let headline = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .headline, compatibleWith: traits)
        let design: UIFontDescriptor.SystemDesign = look.titleDesign == .serif ? .serif : .default
        messageLabel.font = UIFont(descriptor: headline.withDesign(design) ?? headline, size: 0)
        messageLabel.textColor = look.uiLabel.resolvedColor(with: traits)

        retryButton.configuration?.baseForegroundColor = tint
        retryButton.configuration?.baseBackgroundColor = tint
    }

    /// "PAGE 23": the label in small capitals, tracked, in the secondary colour. Uppercase is
    /// applied to the shown text only, so VoiceOver reads the original string.
    private func updateKicker() {
        let traits = traitCollection
        let label = L10n.Localizable.Reader.Page.label(page)
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .caption2, compatibleWith: traits)
        let font = UIFont(descriptor: descriptor.withSymbolicTraits(.traitBold) ?? descriptor, size: 0)
        kickerLabel.attributedText = NSAttributedString(
            string: label.localizedUppercase,
            attributes: [
                .font: font,
                .kern: 0.9,
                .foregroundColor: traits.readerPageStyle.look.uiSecondaryLabel.resolvedColor(with: traits)
            ]
        )
        kickerLabel.accessibilityLabel = label
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        if mode == .failed {
            layoutCard()
        } else {
            layoutIndicator()
        }
    }

    /// The kicker over the spinner or over the ring and its percentage.
    private func layoutIndicator() {
        let width = bounds.width
        let kickerHeight = kickerLabel.sizeThatFits(bounds.size).height
        let percentHeight = mode == .loading ? percentLabel.sizeThatFits(bounds.size).height + 8 : 0
        let groupHeight = kickerHeight + 14 + Self.ringSize + percentHeight
        var y = max(min(bounds.midY, Self.maximumCenterY) - groupHeight / 2, 0)

        kickerLabel.frame = CGRect(x: 0, y: y, width: width, height: kickerHeight)
        y += kickerHeight + 14
        let indicator = CGRect(x: bounds.midX - Self.ringSize / 2, y: y, width: Self.ringSize, height: Self.ringSize)
        spinner.center = CGPoint(x: indicator.midX, y: indicator.midY)
        ring.frame = indicator
        y += Self.ringSize + 8
        percentLabel.frame = CGRect(x: 0, y: y, width: width, height: max(percentHeight - 8, 0))
    }

    /// The failed card: kicker, warning, message and Retry, centred, as wide as fits.
    private func layoutCard() {
        let padding = Self.cardPadding
        let cardWidth = min(bounds.width - 2 * padding, Self.cardMaximumWidth)
        guard cardWidth > 2 * padding else { return }
        let inner = cardWidth - 2 * padding
        let fitting = CGSize(width: inner, height: .greatestFiniteMagnitude)
        let kickerHeight = kickerLabel.sizeThatFits(fitting).height
        let symbolHeight = symbolView.intrinsicContentSize.height
        let messageHeight = messageLabel.sizeThatFits(fitting).height
        let retrySize = retryButton.sizeThatFits(fitting)
        let cardHeight = padding + kickerHeight + 12 + symbolHeight + 8 + messageHeight + 16 + retrySize.height + padding

        let cardY = max(min(bounds.midY, Self.maximumCenterY) - cardHeight / 2, 0)
        card.frame = CGRect(x: bounds.midX - cardWidth / 2, y: cardY, width: cardWidth, height: cardHeight)
        let x = card.frame.minX + padding
        var y = cardY + padding
        kickerLabel.frame = CGRect(x: x, y: y, width: inner, height: kickerHeight)
        y += kickerHeight + 12
        symbolView.frame = CGRect(x: x, y: y, width: inner, height: symbolHeight)
        y += symbolHeight + 8
        messageLabel.frame = CGRect(x: x, y: y, width: inner, height: messageHeight)
        y += messageHeight + 16
        retryButton.frame = CGRect(
            x: bounds.midX - retrySize.width / 2, y: y, width: retrySize.width, height: retrySize.height
        )
    }
}

/// A determinate ring: a track and the fraction done, drawn by two shape layers.
private final class ReaderProgressRing: UIView {
    var progress: CGFloat = 0 {
        didSet {
            guard progress != oldValue else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            progressLayer.strokeEnd = progress
            CATransaction.commit()
        }
    }

    var trackColor: UIColor = .clear {
        didSet { trackLayer.strokeColor = trackColor.cgColor }
    }

    var progressColor: UIColor = .clear {
        didSet { progressLayer.strokeColor = progressColor.cgColor }
    }

    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()
    private static let lineWidth: CGFloat = 3

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        for shape in [trackLayer, progressLayer] {
            shape.fillColor = nil
            shape.lineWidth = Self.lineWidth
            shape.lineCap = .round
            layer.addSublayer(shape)
        }
        progressLayer.strokeEnd = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = Self.lineWidth / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        // From the top, clockwise.
        let path = UIBezierPath(
            arcCenter: CGPoint(x: rect.midX, y: rect.midY), radius: min(rect.width, rect.height) / 2,
            startAngle: -.pi / 2, endAngle: 1.5 * .pi, clockwise: true
        ).cgPath
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for shape in [trackLayer, progressLayer] {
            shape.frame = bounds
            shape.path = path
        }
        CATransaction.commit()
    }
}

// MARK: - The look, from SwiftUI to the engine's views

/// The look and accent the page status views draw in. The engine is UIKit and cannot read
/// SwiftUI's environment, so the reader sets this environment value and SwiftUI hands it to
/// the engine's views as a trait.
nonisolated struct ReaderPageStyle: Equatable, Sendable {
    var look: Look = .shelf
    /// `nil`: the look's own tint.
    var accent: RGBColor?
}

nonisolated struct ReaderPageStyleTrait: UITraitDefinition {
    static let defaultValue = ReaderPageStyle()
    static let affectsColorAppearance = true
}

extension UITraitCollection {
    nonisolated var readerPageStyle: ReaderPageStyle { self[ReaderPageStyleTrait.self] }
}

extension UIMutableTraits {
    nonisolated var readerPageStyle: ReaderPageStyle {
        get { self[ReaderPageStyleTrait.self] }
        set { self[ReaderPageStyleTrait.self] = newValue }
    }
}

nonisolated private struct ReaderPageStyleKey: EnvironmentKey, UITraitBridgedEnvironmentKey {
    static let defaultValue = ReaderPageStyle()

    static func read(from traitCollection: UITraitCollection) -> ReaderPageStyle {
        traitCollection.readerPageStyle
    }

    static func write(to mutableTraits: inout UIMutableTraits, value: ReaderPageStyle) {
        mutableTraits.readerPageStyle = value
    }
}

extension EnvironmentValues {
    /// Set by the reader around its engine (`ReaderScreen`).
    nonisolated var readerPageStyle: ReaderPageStyle {
        get { self[ReaderPageStyleKey.self] }
        set { self[ReaderPageStyleKey.self] = newValue }
    }
}

private extension Look {
    func pageTint(for accent: RGBColor?) -> LookTint {
        if let accent { tint(for: accent) } else { LookTint(tint: defaultAccent, onTint: onAccent, uiTint: uiDefaultAccent) }
    }
}
