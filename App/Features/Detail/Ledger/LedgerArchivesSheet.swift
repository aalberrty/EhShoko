import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// Archive (`ledger.md` section 4, child screens): a sheet at the medium detent, a ruled table
/// of the Hentai@Home options with each size and cost trailing in monospaced digits, the
/// account's funds and the download command. The rows sit on the sheet's own glass.
struct LedgerArchivesSheet: View {
    @State private var model: ArchivesModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.look) private var look

    init(gallery: Gallery, archiveURL: URL) {
        _model = State(initialValue: ArchivesModel(gallery: gallery, archiveURL: archiveURL))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(L10n.Localizable.ArchivesView.Title.archives)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        SheetCloseButton { dismiss() }
                    }
                }
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
                        Button { model.select(archive) } label: { row(archive) }
                            .disabled(!archive.isValid)
                    }
                } footer: {
                    LedgerArchiveFunds()
                }
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom) {
                Button(action: model.sendDownloadCommand) {
                    Text(L10n.Localizable.ArchivesView.Button.downloadToHathClient)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                // A fill on the sheet's glass, not glass on glass.
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .disabled(model.selection == nil)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        } else if let error = model.loadingState.failed {
            ErrorStateView(error: error, retry: model.retry)
        } else {
            LoadingStateView()
        }
    }

    private func row(_ archive: GalleryArchive.HathArchive) -> some View {
        let isSelected = archive.resolution == model.selection
        return HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(look.tertiaryLabel))
            Text(archive.resolution.localizedName)
                .font(.body.weight(.semibold))
                .foregroundStyle(archive.isValid ? look.label : look.tertiaryLabel)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(archive.fileSize)
                    .font(.subheadline)
                    .foregroundStyle(look.label)
                Text(archive.price)
                    .font(.caption)
                    .foregroundStyle(look.secondaryLabel)
            }
            .monospacedDigit()
            .lineLimit(1)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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

/// GP and credits, read from the user store, which the archive page keeps current.
private struct LedgerArchiveFunds: View {
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
            .monospacedDigit()
            .foregroundStyle(look.secondaryLabel)
            .lineLimit(1)
            .padding(.top, 8)
        }
    }
}
