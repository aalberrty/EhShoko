import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// The Hentai@Home archive options at the medium height (`wall.md` section 4, "Child
/// screens"): each resolution with its size and its cost, the account's funds, and the command
/// that sends the chosen one to the H@H client. The sheet is the system's, so it is glass
/// below full height; the list lets it show through and its rows are fills.
struct WallArchivesSheet: View {
    @State private var model: ArchivesModel

    @Environment(\.look) private var look

    init(gallery: Gallery, archiveURL: URL) {
        _model = State(initialValue: ArchivesModel(gallery: gallery, archiveURL: archiveURL))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(L10n.Localizable.ArchivesView.Title.archives)
                .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .task { await model.load() }
        .hud(downloadHUD)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: model.selectionCount)
        .sensoryFeedback(trigger: model.feedback) { _, feedback in
            feedback.map { $0.isSuccess ? .success : .error }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !model.archives.isEmpty {
            List {
                Section {
                    ForEach(model.archives) { archive in
                        WallArchiveRow(archive: archive, isSelected: archive.resolution == model.selection) {
                            model.select(archive)
                        }
                        .listRowBackground(look.fill2)
                    }
                } footer: {
                    WallArchiveFunds()
                }
                Section {
                    Button(L10n.Localizable.ArchivesView.Button.downloadToHathClient, action: model.sendDownloadCommand)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .disabled(model.selection == nil)
                        .listRowBackground(look.fill2)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        } else if let error = model.loadingState.failed {
            WallSheetFailure(error: error, retry: model.retry)
        } else {
            LoadingStateView()
        }
    }

    private var downloadHUD: Binding<HUDConfiguration?> {
        Binding(
            get: {
                switch model.download {
                case .communicating: .communicating
                case .finished(let result): Self.hud(for: result)
                case nil: nil
                }
            },
            set: { if $0 == nil { model.dismissDownloadResult() } }
        )
    }

    private static func hud(for result: ArchivesModel.DownloadResult) -> HUDConfiguration {
        switch result {
        case .success(let message): .success(caption: message)
        case .hathClientNotFound: .error(caption: L10n.Localizable.Website.Response.hathClientNotFound)
        case .hathClientNotOnline: .error(caption: L10n.Localizable.Website.Response.hathClientNotOnline)
        case .invalidResolution: .error(caption: L10n.Localizable.Website.Response.invalidResolution)
        case .failed: .error
        }
    }
}

/// A resolution, its size and its cost, checked when chosen. One the site does not offer is
/// greyed out.
private struct WallArchiveRow: View {
    let archive: GalleryArchive.HathArchive
    let isSelected: Bool
    let select: () -> Void

    @Environment(\.look) private var look

    var body: some View {
        Button(action: select) {
            HStack(spacing: Tokens.Spacing.medium) {
                Text(archive.resolution.localizedName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(archive.isValid ? look.label : look.tertiaryLabel)
                Spacer(minLength: Tokens.Spacing.small)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(archive.fileSize)
                        .font(.subheadline)
                        .foregroundStyle(archive.isValid ? look.label : look.tertiaryLabel)
                    Text(archive.price)
                        .font(.caption)
                        .foregroundStyle(archive.isValid ? look.secondaryLabel : look.tertiaryLabel)
                }
                .monospacedDigit()
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .lineLimit(1)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!archive.isValid)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// GP and credits, read from the user store, which the archive page keeps current.
private struct WallArchiveFunds: View {
    @Environment(UserStore.self) private var userStore
    @Environment(\.look) private var look

    var body: some View {
        if let galleryPoints = userStore.galleryPoints.flatMap({ Int($0) }),
           let credits = userStore.credits.flatMap({ Int($0) }) {
            HStack(spacing: Tokens.Spacing.xLarge) {
                Label(galleryPoints.formatted(), systemImage: "g.circle.fill")
                Label(credits.formatted(), systemImage: "c.circle.fill")
            }
            .font(.subheadline.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(look.secondaryLabel)
            .lineLimit(1)
            .contentTransition(.numericText())
            .animation(.default, value: galleryPoints)
            .animation(.default, value: credits)
        }
    }
}

/// A sheet's content could not be loaded: what went wrong and Retry as a fill, because the
/// sheet under it is glass below full height.
struct WallSheetFailure: View {
    let error: AppError
    let retry: () -> Void

    @Environment(\.look) private var look
    @Environment(\.onTint) private var onTint

    var body: some View {
        VStack(spacing: Tokens.Spacing.medium) {
            Image(systemName: error.symbol.rawValue)
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(look.tertiaryLabel)
                .accessibilityHidden(true)
            Text(error.alertText)
                .font(.subheadline)
                .foregroundStyle(look.secondaryLabel)
                .multilineTextAlignment(.center)
            Button(action: retry) {
                Text(L10n.Localizable.ErrorView.Button.retry)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(onTint)
                    .padding(.horizontal, Tokens.Spacing.xLarge)
                    .frame(minHeight: 36)
                    .background(.tint, in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Tokens.Spacing.xLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
