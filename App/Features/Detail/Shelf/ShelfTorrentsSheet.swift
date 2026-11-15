import EhFeatures
import EhModels
import SwiftUI

/// The gallery's torrents as a grouped list on the sheet (`shelf.md` section 4, "Torrents"):
/// each with its seeds, peers, downloads and size. A tap copies the magnet link; swiping shares
/// the torrent file. The list lets the sheet's glass show through; its rows are content.
struct ShelfTorrentsSheet: View {
    @State private var model: TorrentsModel
    @State private var hud: HUDConfiguration?

    @Environment(\.look) private var look
    @Environment(\.lookTint) private var tint

    init(gid: String, token: String) {
        _model = State(initialValue: TorrentsModel(gid: gid, token: token))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(L10n.Localizable.TorrentsView.Title.torrents)
                .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .task { await model.load() }
        .hud($hud)
        .onChange(of: model.copyCount) { hud = .copiedToClipboard }
        .sensoryFeedback(.success, trigger: model.copyCount)
        .sensoryFeedback(.impact(weight: .light), trigger: model.sharedFile) { _, file in file != nil }
        .sheet(item: $model.sharedFile) { file in
            ActivityView(items: [file.url])
                .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var content: some View {
        if !model.torrents.isEmpty {
            List(model.torrents) { torrent in
                ShelfTorrentRow(torrent: torrent) { model.copyMagnet(of: torrent) }
                    .listRowBackground(look.surface)
                    .swipeActions {
                        Button(L10n.Localizable.DetailView.ToolbarItem.Button.share, systemImage: "square.and.arrow.up") {
                            model.shareFile(of: torrent)
                        }
                        .tint(tint)
                    }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        } else if let error = model.loadingState.failed {
            ErrorStateView(error: error, retry: model.retry)
        } else {
            LoadingStateView()
        }
    }
}

private struct ShelfTorrentRow: View {
    let torrent: GalleryTorrent
    let copy: () -> Void

    @Environment(\.look) private var look

    var body: some View {
        Button(action: copy) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xSmall) {
                Text(torrent.fileName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(look.label)
                    .multilineTextAlignment(.leading)
                HStack(spacing: Tokens.Spacing.medium) {
                    figure(torrent.seedCount.formatted(), systemImage: "arrow.up.circle")
                    figure(torrent.peerCount.formatted(), systemImage: "arrow.down.circle")
                    figure(torrent.downloadCount.formatted(), systemImage: "checkmark.circle")
                    Spacer(minLength: 0)
                    Text(torrent.fileSize)
                }
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(look.secondaryLabel)
                .lineLimit(1)
                Text(verbatim: "\(torrent.uploader) · \(torrent.formattedDateString)")
                    .font(.caption)
                    .foregroundStyle(look.tertiaryLabel)
                    .lineLimit(1)
            }
            .padding(.vertical, Tokens.Spacing.xxSmall)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func figure(_ value: String, systemImage: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
            Text(value)
        }
    }
}
