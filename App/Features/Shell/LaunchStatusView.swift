import EhFeatures
import EhModels
import SwiftUI

/// What shows before the tabs (legacy `MigrationView`): nothing on a normal launch, "Preparing
/// the database…" when opening or importing takes a moment, and the error with "Drop the
/// database" when the database cannot be opened. On the look's tokens; the state views take
/// their colours from it too.
struct LaunchStatusView: View {
    @Bindable var model: AppModel

    @Environment(\.look) private var look

    /// A normal launch is over before this, so it shows no spinner at all.
    private static let progressDelay: Duration = .milliseconds(400)

    @State private var showsProgress = false

    var body: some View {
        ZStack {
            // The empty launch screen is the system's background whatever the look, so the
            // first frame matches it and the hand-over is invisible. The look's ground fades in
            // only when there is something to show (Shelf's and Wall's are the same colour).
            Color(.systemBackground).ignoresSafeArea()
            look.background
                .ignoresSafeArea()
                .opacity(showsStatus ? 1 : 0)
            switch model.launchState {
            case .launching:
                if showsProgress {
                    LoadingStateView(title: L10n.Localizable.LoadingView.Title.preparingDatabase)
                        .transition(.opacity)
                }
            case .failed(let error):
                failure(error)
                    .transition(.opacity)
            case .ready:
                EmptyView()
            }
        }
        .animation(.default, value: model.launchState)
        .animation(.default, value: showsProgress)
        .task(id: model.launchAttempt) {
            // After "Drop the database" the progress shows at once, as legacy did.
            showsProgress = model.launchAttempt > 0
            guard (try? await Task.sleep(for: Self.progressDelay)) != nil else { return }
            showsProgress = true
        }
    }

    private var showsStatus: Bool {
        switch model.launchState {
        case .launching: showsProgress
        case .failed: true
        case .ready: false
        }
    }

    private func failure(_ error: AppError) -> some View {
        ErrorStateView(error: error, retryTitle: L10n.Localizable.ErrorView.Button.dropDatabase) {
            model.isConfirmingDatabaseDrop = true
        }
        .confirmationDialog(
            Text(verbatim: ""), isPresented: $model.isConfirmingDatabaseDrop, titleVisibility: .hidden
        ) {
            Button(L10n.Localizable.ConfirmationDialog.Button.dropDatabase, role: .destructive) {
                model.dropDatabase()
            }
        } message: {
            Text(L10n.Localizable.ConfirmationDialog.Title.dropDatabase)
        }
    }
}
