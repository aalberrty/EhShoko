import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// The archive options, the account's funds and the download command, as a sheet at the
/// medium detent. Below full height the sheet is glass on iOS 26, so its options are flat
/// fills from the look: content on the sheet, no glass on glass.
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
            VStack(spacing: 12) {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(model.archives) { archive in
                            Button {
                                model.select(archive)
                            } label: {
                                WallArchiveOption(archive: archive, isSelected: archive.resolution == model.selection)
                            }
                            .buttonStyle(.plain)
                            .disabled(!archive.isValid)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
                WallArchiveFunds()
                Button(action: model.sendDownloadCommand) {
                    Text(L10n.Localizable.ArchivesView.Button.downloadToHathClient)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .disabled(model.selection == nil)
                .padding([.horizontal, .bottom], 20)
            }
        } else if let error = model.loadingState.failed {
            ErrorStateView(error: error, retry: model.retry)
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

/// One resolution with its size and its cost; the chosen one is outlined in the tint.
private struct WallArchiveOption: View {
    let archive: GalleryArchive.HathArchive
    let isSelected: Bool

    @Environment(\.look) private var look
    @Environment(\.lookTint) private var tint

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(spacing: 6) {
            Text(archive.resolution.localizedName)
                .font(.headline)
                .foregroundStyle(archive.isValid ? look.label : look.tertiaryLabel)
            VStack(spacing: 2) {
                Text(verbatim: archive.fileSize)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(archive.isValid ? look.label : look.tertiaryLabel)
                Text(verbatim: archive.price)
                    .font(.caption2)
                    .foregroundStyle(archive.isValid ? look.secondaryLabel : look.tertiaryLabel)
            }
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 84)
        .background(look.fill3, in: shape)
        .overlay { shape.strokeBorder(isSelected ? tint : .clear, lineWidth: 2) }
        .contentShape(shape)
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
            HStack(spacing: 20) {
                Label(galleryPoints.formatted(), systemImage: "g.circle.fill")
                Label(credits.formatted(), systemImage: "c.circle.fill")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(look.label)
            .lineLimit(1)
            .contentTransition(.numericText())
            .animation(.default, value: galleryPoints)
            .animation(.default, value: credits)
        }
    }
}
