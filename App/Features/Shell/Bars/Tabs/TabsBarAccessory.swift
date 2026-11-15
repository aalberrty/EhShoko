import EhFeatures
import EhModels
import SwiftUI

/// Continue in the tab bar's accessory (`shelf.md` section 1): the cover, the title and the
/// page of the gallery read last; one tap opens the reader there.
///
/// A first working form, for task A1: the expanded layout only. It draws no background: the
/// accessory's glass is the system's, and the capsule's on the systems that have no accessory.
struct TabsBarAccessory: View {
    @Environment(ContinueModel.self) private var continueModel
    @Environment(AppRouter.self) private var appRouter
    @Environment(\.look) private var look

    private static var height: CGFloat { 48 }

    var body: some View {
        if let item = continueModel.first {
            Button {
                appRouter.reading = ReadingRequest(gallery: item.gallery, page: item.page)
            } label: {
                HStack(spacing: 10) {
                    CoverImage(url: item.gallery.coverURL, size: CGSize(width: 25, height: 36), cornerRadius: 4)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title.core)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(look.label)
                        Text(L10n.Localizable.Shell.Continue.page(item.page, item.pageCount))
                            .font(.caption)
                            .foregroundStyle(look.secondaryLabel)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "play.fill")
                        .foregroundStyle(look.label)
                }
                .padding(.horizontal, 12)
                // The slot's height on every system (`spikes/S3.md`, question 4). Never an
                // unlimited height: in the capsule's bottom inset that would take the screen.
                .frame(maxWidth: .infinity)
                .frame(height: Self.height)
                .contentShape(.rect)
                // On the content, inside the accessory's glass: a marker around glass does
                // nothing (`spikes/S4.md`).
                .readerSource(.continueBar(gid: item.gallery.gid))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.Localizable.Shell.Continue.reading)
            .accessibilityValue(item.title.core)
        }
    }
}

extension EnvironmentValues {
    /// Whether the screens of this stack show the capsule that stands in for the accessory:
    /// true for the tabs' stacks but the search tab's, false everywhere else.
    @Entry var tabsBarKeepsLegacyAccessory = false
}

/// On iOS 18 and iOS 26.0, which have no accessory that can be switched off without
/// rebuilding every tab: the same content in a capsule in a bottom inset, on each screen that
/// keeps the tab bar, outside the screen's own insets (`spikes/S3.md` section 5). On later
/// systems it reads nothing and adds nothing.
struct TabsBarLegacyAccessory: ViewModifier {
    /// Whether this screen's route keeps the tab bar.
    let isAllowed: Bool

    @Environment(\.tabsBarKeepsLegacyAccessory) private var keepsAccessory
    @Environment(ContinueModel.self) private var continueModel: ContinueModel?

    func body(content: Content) -> some View {
        content.legacyTabAccessory(isVisible: isVisible) {
            TabsBarAccessory()
        }
    }

    private var isVisible: Bool {
        !TabAccessoryKind.usesSystemAccessory && keepsAccessory && isAllowed && continueModel?.first != nil
    }
}
