#if DEBUG || HARNESS
import Dependencies
import EhCore
import EhDatabase
import EhModels
import Foundation

/// Quick searches and recent searches for trying Shelf's search where the database has none
/// (the part harness's is seeded with galleries only): `-HarnessSearchWords YES` adds four of
/// each once per launch, when there are no quick searches yet.
enum ShelfSearchSampleWords {
    private static var isRequested: Bool { UserDefaults.standard.bool(forKey: "HarnessSearchWords") }
    @MainActor private static var hasRun = false

    @MainActor
    static func addIfRequested(hasQuickSearches: Bool) async {
        guard isRequested, !hasRun, !hasQuickSearches else { return }
        hasRun = true
        @Dependency(\.database) var database
        let words = [
            QuickSearchWord(name: "", content: #"artist:"hoshino kanae$""#),
            QuickSearchWord(name: "", content: "language:chinese$ female:glasses$"),
            QuickSearchWord(name: "Stellar fleet", content: #"parody:"stellar fleet chronicle$""#),
            QuickSearchWord(name: "", content: "uploader:lantern_scans")
        ]
        for word in words {
            try? await database.insertQuickSearchWord(word)
        }
        let recent = ["summer vacation", "female:kimono$ full color", #"artist:"hoshino kanae$""#, "glasses"]
        for (index, keyword) in recent.enumerated() {
            try? await database.recordSearchKeyword(keyword, at: Date(timeIntervalSinceNow: -Double(index) * 600))
        }
    }
}
#endif
