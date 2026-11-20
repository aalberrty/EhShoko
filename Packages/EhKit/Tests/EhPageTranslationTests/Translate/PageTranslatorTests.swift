import EhModels
@testable import EhPageTranslation
import Foundation
import Testing

@Suite struct PageTranslatorLoaderTests {
    private struct Echo: PageTranslator {
        func translate(_ lines: [String]) async throws -> [String?] { lines }
    }

    @Test func runsOnlyTheDefaultOnCoreML() {
        #expect(TranslatorChoice.allCases.filter { $0.engine == .coreML } == [.jmtFast1])
    }

    @Test(arguments: [TranslatorChoice.galTransl4B, .sakura1_5B, .hyMT2, .qwen35_4B])
    func cannotLoadALanguageModelWithoutAnEngine(choice: TranslatorChoice) async {
        await #expect(throws: PageTranslatorError.unavailable(choice)) {
            try await PageTranslatorLoader().load(choice, from: URL(filePath: "/nowhere.gguf"))
        }
    }

    @Test func handsLanguageModelsToTheirLoader() async throws {
        let loader = PageTranslatorLoader(languageModel: { choice, url in
            #expect(choice == .hyMT2 && url.lastPathComponent == "model.gguf")
            return Echo()
        })
        let translator = try await loader.load(.hyMT2, from: URL(filePath: "/models/model.gguf"))
        #expect(try await translator.translate(["a"]) == ["a"])
    }

    @Test func failsToLoadTheDefaultFromAFolderWithoutItsFiles() async {
        let folder = FileManager.default.temporaryDirectory.appending(path: "jmt-missing-\(UUID().uuidString)")
        await #expect(throws: (any Error).self) {
            try await PageTranslatorLoader().load(.jmtFast1, from: folder)
        }
    }
}
