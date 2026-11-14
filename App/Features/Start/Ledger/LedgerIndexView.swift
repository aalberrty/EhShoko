import SwiftUI

/// Ledger's first screen, the Index (`ledger.md` section 2): Continue, the lists, the
/// favourites folders and the quick searches. On regular width the shell shows it as the
/// leading column beside the list (`chrome.isLeadingColumn`).
///
/// **Adapter.** Until task B3 builds it, today's Home stands in for it: its shortcuts push
/// the lists, as the Index's rows will. B3 replaces this file and keeps the initializer,
/// which is what `StartScreen` calls.
struct LedgerIndexView: View {
    var body: some View {
        HomeScreen()
            // The Index keeps its account button under `command`; under `tabs` the shell
            // adds it.
            .startAccountButton()
    }
}
