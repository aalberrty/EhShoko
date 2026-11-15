import EhFeatures
import EhModels
import SwiftUI

/// Torrents (`ledger.md` section 4, child screens): a sheet at the medium detent, a ruled
/// table of the gallery's torrents with each size trailing in monospaced digits. A tap copies
/// the magnet link; a swipe shares the torrent file, as in v3.
struct LedgerTorrentsSheet: View {
    @State private var model: TorrentsModel
    @State private var hud: HUDConfiguration?
    @Environment(\.dismiss) private var dismiss

    init(gid: String, token: String) {
        _model = State(initialValue: TorrentsModel(gid: gid, token: token))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(L10n.Localizable.TorrentsView.Title.torrents)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        SheetCloseButton { dismiss() }
                    }
                }
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
                Button { model.copyMagnet(of: torrent) } label: {
                    LedgerTorrentRow(torrent: torrent)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .swipeActions {
                    Button {
                        model.shareFile(of: torrent)
                    } label: {
                        Label(L10n.Localizable.DetailView.ToolbarItem.Button.share, systemImage: "arrow.down.doc.fill")
                    }
                    .tint(.accentColor)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        } else if let error = model.loadingState.failed {
            // On the sheet's glass: a filled Retry, not glass on glass.
            ErrorStateView(error: error, retry: model.retry)
                .statusActionForm(.filled)
        } else {
            LoadingStateView()
        }
    }
}

/// One torrent: its file name, then seeds, peers and downloads in small capitals, the uploader
/// and date, and the size trailing.
private struct LedgerTorrentRow: View {
    let torrent: GalleryTorrent

    @Environment(\.look) private var look

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(torrent.fileName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(look.label)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 10) {
                    figure(torrent.seedCount, systemImage: "arrow.up")
                    figure(torrent.peerCount, systemImage: "arrow.down")
                    figure(torrent.downloadCount, systemImage: "checkmark")
                }
                Text("\(torrent.uploader) · \(torrent.formattedDateString)")
                    .ledgerSmallCaps()
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(torrent.fileSize)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(look.secondaryLabel)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private func figure(_ value: Int, systemImage: String) -> some View {
        Label(value.formatted(), systemImage: systemImage)
            .labelStyle(LedgerFigureLabelStyle())
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(look.secondaryLabel)
    }
}

private struct LedgerFigureLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}
