import EhModels
import UIKit

/// What a page shows while it has no image (`ledger.md` section 5, the same in every reader
/// design): "PAGE 23" in small capitals over a spinner while its URL is resolved; a progress
/// ring, the percentage and "Loading · 1.4 MB of 2.3 MB" while it downloads; a short card with
/// a warning, "This page didn't load", the reason, a Retry pill and "Reload all 2 failed pages"
/// when it failed. It keeps the page's full height, and in a very long page its content stays
/// near the top.
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
    /// "Reload all N failed pages".
    var onRetryAllFailed: (() -> Void)?

    private let kickerLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let ring = ReaderProgressRing()
    private let percentLabel = UILabel()
    private let bytesLabel = UILabel()
    private let card = UIView()
    private let symbolView = UIImageView()
    private let messageLabel = UILabel()
    private let reasonLabel = UILabel()
    private let retryButton = UIButton(configuration: .tinted())
    private let retryAllButton = UIButton(configuration: .plain())
    private var mode: Mode?
    private var page = 0
    private var percent = -1
    private var failedPageCount = 0

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
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .readerBackground
        // The card has to fit in the page it stands for, which in the vertical strip is as tall
        // as a page's image: beyond this size its text would push Retry out of the page.
        maximumContentSizeCategory = .accessibilityMedium

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
        for label in [percentLabel, bytesLabel] {
            label.textAlignment = .center
            label.isHidden = true
            addSubview(label)
        }
        bytesLabel.numberOfLines = 0

        symbolView.image = UIImage(systemName: "exclamationmark.triangle")
        symbolView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .title2)
        symbolView.contentMode = .center
        symbolView.isHidden = true
        // The title says the page failed; VoiceOver need not read "Warning" first.
        symbolView.isAccessibilityElement = false
        symbolView.accessibilityElementsHidden = true
        addSubview(symbolView)

        messageLabel.text = L10n.Localizable.Reader.Page.failed
        for label in [messageLabel, reasonLabel] {
            label.textAlignment = .center
            label.numberOfLines = 0
            label.isHidden = true
            addSubview(label)
        }

        configureButtons()
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

    private func configureButtons() {
        var retry = UIButton.Configuration.tinted()
        retry.title = L10n.Localizable.ErrorView.Button.retry
        retry.image = UIImage(systemName: "arrow.clockwise")
        retry.imagePadding = 6
        retry.cornerStyle = .capsule
        retryButton.configuration = retry
        retryButton.isHidden = true
        retryButton.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .primaryActionTriggered)
        addSubview(retryButton)

        var retryAll = UIButton.Configuration.plain()
        retryAll.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
        retryAll.titleLineBreakMode = .byWordWrapping
        retryAllButton.configuration = retryAll
        retryAllButton.isHidden = true
        retryAllButton.addAction(UIAction { [weak self] _ in self?.onRetryAllFailed?() }, for: .primaryActionTriggered)
        addSubview(retryAllButton)
    }

    // MARK: State

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
        reasonLabel.isHidden = !isFailed || reasonLabel.text == nil
        retryButton.isHidden = !isFailed
        updateRetryAll()
        ring.isHidden = newMode != .loading
        percentLabel.isHidden = newMode != .loading
        bytesLabel.isHidden = true
        if newMode == .loading {
            resetProgress()
        }
        if newMode == .resolving {
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
        }
        setNeedsLayout()
    }

    /// How far the download has come. The bytes line appears with the first report: a
    /// download reports only once the server has said how large the image is.
    func setProgress(_ progress: ImageLoadProgress) {
        ring.setProgress(CGFloat(progress.fraction), animated: true)
        let newPercent = Int(progress.fraction * 100)
        if newPercent != percent {
            setProgressText(percent: newPercent)
        }
        let bytes = L10n.Localizable.Reader.Page.loading(
            Self.byteFormatter.string(fromByteCount: progress.receivedBytes),
            Self.byteFormatter.string(fromByteCount: progress.expectedBytes)
        )
        guard bytes != bytesLabel.text || bytesLabel.isHidden else { return }
        bytesLabel.text = bytes
        if bytesLabel.isHidden {
            bytesLabel.isHidden = mode != .loading
            setNeedsLayout()
        }
    }

    /// Why the page failed, the line under "This page didn't load"; none when it is not known.
    func setFailureReason(_ text: String?) {
        guard text != reasonLabel.text else { return }
        reasonLabel.text = text
        reasonLabel.isHidden = mode != .failed || text == nil
        setNeedsLayout()
    }

    /// How many pages of the gallery have failed. From two on, a failed page offers to reload
    /// them all; for one, its own Retry does that.
    func setFailedPageCount(_ count: Int) {
        guard count != failedPageCount else { return }
        failedPageCount = count
        updateRetryAll()
    }

    /// Stops the spinner while the view is hidden or waiting in the reuse pool.
    func pause() {
        mode = nil
        spinner.stopAnimating()
    }

    private func resetProgress() {
        ring.setProgress(0, animated: false)
        setProgressText(percent: 0)
        bytesLabel.text = nil
    }

    private func setProgressText(percent newPercent: Int) {
        percent = newPercent
        percentLabel.text = Self.percentFormatter.string(from: NSNumber(value: Double(newPercent) / 100))
    }

    private func updateRetryAll() {
        let shows = mode == .failed && failedPageCount > 1
        if shows {
            let title = L10n.Localizable.Reader.Page.reloadFailed(failedPageCount)
            if retryAllButton.configuration?.title != title {
                retryAllButton.configuration?.title = title
                setNeedsLayout()
            }
        }
        guard shows == retryAllButton.isHidden else { return }
        retryAllButton.isHidden = !shows
        setNeedsLayout()
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
        let label = look.uiLabel.resolvedColor(with: traits)
        let secondary = look.uiSecondaryLabel.resolvedColor(with: traits)

        updateKicker()
        spinner.color = secondary
        percentLabel.font = Self.font(.headline, weight: .semibold, monospacedDigits: true, traits: traits)
        percentLabel.textColor = label
        bytesLabel.font = Self.font(.footnote, traits: traits)
        bytesLabel.textColor = secondary
        symbolView.tintColor = secondary
        ring.trackColor = UIColor(look.fill).resolvedColor(with: traits)
        ring.progressColor = tint.resolvedColor(with: traits)
        card.backgroundColor = UIColor(look.raised).resolvedColor(with: traits)

        let headline = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .headline, compatibleWith: traits)
        let design: UIFontDescriptor.SystemDesign = look.titleDesign == .serif ? .serif : .default
        messageLabel.font = UIFont(descriptor: headline.withDesign(design) ?? headline, size: 0)
        messageLabel.textColor = label
        reasonLabel.font = Self.font(.footnote, traits: traits)
        reasonLabel.textColor = secondary

        retryButton.configuration?.baseForegroundColor = tint
        retryButton.configuration?.baseBackgroundColor = tint
        retryAllButton.configuration?.baseForegroundColor = tint
        // From the view's traits, so it keeps to the card's largest text size.
        let retryAllFont = Self.font(.subheadline, traits: traits)
        retryAllButton.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = retryAllFont
            return outgoing
        }
    }

    private static func font(
        _ style: UIFont.TextStyle, weight: UIFont.Weight? = nil, monospacedDigits: Bool = false,
        traits: UITraitCollection
    ) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits)
        guard weight != nil || monospacedDigits else { return base }
        let size = base.pointSize
        let weight = weight ?? .regular
        return monospacedDigits
            ? .monospacedDigitSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
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

    /// The kicker over the spinner, or over the ring, its percentage and the bytes line.
    private func layoutIndicator() {
        let width = bounds.width
        let fitting = CGSize(width: max(width - 2 * Self.cardPadding, 0), height: .greatestFiniteMagnitude)
        let kickerHeight = kickerLabel.sizeThatFits(bounds.size).height
        let isLoading = mode == .loading
        let percentHeight = isLoading ? percentLabel.sizeThatFits(fitting).height + 8 : 0
        let bytesHeight = isLoading && !bytesLabel.isHidden ? bytesLabel.sizeThatFits(fitting).height + 2 : 0
        let groupHeight = kickerHeight + 14 + Self.ringSize + percentHeight + bytesHeight
        var y = max(min(bounds.midY, Self.maximumCenterY) - groupHeight / 2, 0)

        kickerLabel.frame = CGRect(x: 0, y: y, width: width, height: kickerHeight)
        y += kickerHeight + 14
        let indicator = CGRect(x: bounds.midX - Self.ringSize / 2, y: y, width: Self.ringSize, height: Self.ringSize)
        spinner.center = CGPoint(x: indicator.midX, y: indicator.midY)
        ring.frame = indicator
        y += Self.ringSize + 8
        percentLabel.frame = CGRect(x: 0, y: y, width: width, height: max(percentHeight - 8, 0))
        y += max(percentHeight - 8, 0) + 2
        bytesLabel.frame = CGRect(x: Self.cardPadding, y: y, width: fitting.width, height: max(bytesHeight - 2, 0))
    }

    /// The failed card: kicker, warning, message, reason, Retry and "Reload all", centred, as
    /// wide as fits.
    private func layoutCard() {
        let padding = Self.cardPadding
        let cardWidth = min(bounds.width - 2 * padding, Self.cardMaximumWidth)
        guard cardWidth > 2 * padding else { return }
        let inner = cardWidth - 2 * padding
        let fitting = CGSize(width: inner, height: .greatestFiniteMagnitude)
        let kickerHeight = kickerLabel.sizeThatFits(fitting).height
        let symbolHeight = symbolView.intrinsicContentSize.height
        let messageHeight = messageLabel.sizeThatFits(fitting).height
        let reasonHeight = reasonLabel.isHidden ? 0 : reasonLabel.sizeThatFits(fitting).height + 6
        let retrySize = retryButton.sizeThatFits(fitting)
        let retryAllSize = retryAllButton.isHidden ? .zero : retryAllButton.sizeThatFits(fitting)
        let retryAllHeight = retryAllButton.isHidden ? 0 : min(retryAllSize.height, 200) + 6
        let cardHeight = padding + kickerHeight + 12 + symbolHeight + 8 + messageHeight + reasonHeight + 16
            + retrySize.height + retryAllHeight + padding

        let cardY = max(min(bounds.midY, Self.maximumCenterY) - cardHeight / 2, 0)
        card.frame = CGRect(x: bounds.midX - cardWidth / 2, y: cardY, width: cardWidth, height: cardHeight)
        let x = card.frame.minX + padding
        var y = cardY + padding
        kickerLabel.frame = CGRect(x: x, y: y, width: inner, height: kickerHeight)
        y += kickerHeight + 12
        symbolView.frame = CGRect(x: x, y: y, width: inner, height: symbolHeight)
        y += symbolHeight + 8
        messageLabel.frame = CGRect(x: x, y: y, width: inner, height: messageHeight)
        y += messageHeight
        if !reasonLabel.isHidden {
            reasonLabel.frame = CGRect(x: x, y: y + 6, width: inner, height: reasonHeight - 6)
            y += reasonHeight
        }
        y += 16
        retryButton.frame = CGRect(
            x: bounds.midX - retrySize.width / 2, y: y, width: retrySize.width, height: retrySize.height
        )
        y += retrySize.height
        if !retryAllButton.isHidden {
            let width = min(retryAllSize.width, inner)
            retryAllButton.frame = CGRect(x: bounds.midX - width / 2, y: y + 6, width: width, height: retryAllHeight - 6)
        }
    }
}
