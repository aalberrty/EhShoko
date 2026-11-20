import EhModels
import Foundation
import Testing
@testable import EhCore

/// Installing with a stub compiler: files in place, compiled, recorded, removed.
@Suite struct ModelInstallerTests {
    private let root = StoreSamples.temporaryFolder()
    private let compiler = StubCompiler()

    private var layout: ModelStoreLayout { ModelStoreLayout(root: root) }

    private var installer: ModelInstaller {
        let downloader = ModelDownloader(
            transport: StubModelTransport(), layout: layout, chunkSize: StoreSamples.chunkSize, slots: ModelWorkSlots(4)
        )
        return ModelInstaller(
            layout: layout, catalog: StoreSamples.catalog, compiler: compiler.compiler, downloader: downloader
        )
    }

    private func copyIn(_ id: ModelArtifactID, except skipped: Set<String> = [], corrupting corrupted: Set<String> = []) throws {
        for (path, data) in StoreSamples.contents[id] ?? [] where !skipped.contains(path) {
            var data = data
            if corrupted.contains(path) { data[data.count - 1] ^= 0x01 }
            let url = layout.url(ofPath: path, in: id)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
    }

    private func exists(_ path: String, in id: ModelArtifactID) -> Bool {
        FileManager.default.fileExists(atPath: layout.url(ofPath: path, in: id).path(percentEncoded: false))
    }

    // MARK: Installing

    @Test func aPackageIsCompiledMovedIntoPlaceAndDeleted() async throws {
        try copyIn(.cpt2)
        let artifact = StoreSamples.artifact(.cpt2)

        let record = try await installer.install(artifact)

        #expect(compiler.compiled == ["Encoder.mlpackage", "Decoder.mlpackage"])
        // The model is on disk once: compiled, without its package.
        #expect(exists("Encoder.mlmodelc/weights.bin", in: .cpt2))
        #expect(exists("Decoder.mlmodelc/weights.bin", in: .cpt2))
        #expect(!exists("Encoder.mlpackage", in: .cpt2))
        #expect(!exists("Decoder.mlpackage", in: .cpt2))
        #expect(exists("vocab.txt", in: .cpt2))
        #expect(record.items == [
            .init(path: "Encoder.mlmodelc", isCompiledModel: true),
            .init(path: "Decoder.mlmodelc", isCompiledModel: true),
            .init(path: "vocab.txt", isCompiledModel: false),
            .init(path: "LICENSE", isCompiledModel: false),
            .init(path: "CREDITS.md", isCompiledModel: false)
        ])
        #expect(record.bytes == 4096 + 1500 + 700 + 400 + 120)
        #expect(record.catalogVersion == 7)
        #expect(record.version == "1")
        #expect(!record.isPrepared)
        #expect(compiler.mainThreadCalls == 0)
    }

    @Test func installedJSONRecordsTheCatalogAndTheFiles() async throws {
        try copyIn(.v4s)
        let record = try await installer.install(StoreSamples.artifact(.v4s))

        let data = try Data(contentsOf: layout.folder(of: .v4s).appending(path: "installed.json"))
        #expect(try JSONDecoder().decode(InstalledArtifact.self, from: data) == record)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["catalogVersion"] as? Int == 7)
        #expect(json["artifact"] as? String == "det-v4s")
        #expect(json["version"] as? String == "2")
        #expect((json["items"] as? [[String: Any]])?.count == 3)
    }

    /// A language-model file is one file: neither compiled nor prepared.
    @Test func aLanguageModelFileIsLeftAsItIs() async throws {
        try copyIn(.galTransl4B)
        let artifact = StoreSamples.artifact(.galTransl4B)
        let installer = installer

        let record = try await installer.install(artifact)
        let prepared = try await installer.prepare(artifact, record: record)

        #expect(compiler.compiled.isEmpty)
        #expect(compiler.prepared.isEmpty)
        #expect(record.isPrepared)
        #expect(prepared == record)
        #expect(record.items.map(\.path) == ["model.gguf", "LICENSE", "CREDITS.md"])
        #expect(try Data(contentsOf: layout.url(ofPath: "model.gguf", in: .galTransl4B))
            == StoreSamples.data("model.gguf", of: .galTransl4B))
    }

    @Test func preparingLoadsEachModelOnceWithItsComputeUnits() async throws {
        try copyIn(.cpt2)
        let artifact = StoreSamples.artifact(.cpt2)
        let installer = installer
        let record = try await installer.install(artifact)

        let prepared = try await installer.prepare(artifact, record: record)

        #expect(compiler.prepared == ["Encoder.mlmodelc", "Decoder.mlmodelc"])
        #expect(compiler.preparedUnits == [.cpuAndNeuralEngine, .cpuAndNeuralEngine])
        #expect(prepared.isPrepared)
        #expect(await installer.survey(artifact).record == prepared)
        // Once it is recorded, it is not done again.
        _ = try await installer.prepare(artifact, record: prepared)
        #expect(compiler.prepared.count == 2)
    }

    @Test func aPackageThatCannotBeCompiledIsNotInstalled() async throws {
        try copyIn(.v4s)
        compiler.failCompiling(CocoaError(.fileReadCorruptFile))
        let installer = installer

        await #expect(throws: CocoaError.self) { try await installer.install(StoreSamples.artifact(.v4s)) }

        #expect(await installer.survey(StoreSamples.artifact(.v4s)).record == nil)
        #expect(exists("V4S.mlpackage/Manifest.json", in: .v4s))
    }

    @Test func aMissingFileStopsTheInstall() async throws {
        try copyIn(.cpt2, except: ["vocab.txt"])
        let installer = installer

        await #expect(throws: CocoaError.self) { try await installer.install(StoreSamples.artifact(.cpt2)) }
        #expect(await installer.survey(StoreSamples.artifact(.cpt2)).record == nil)
    }

    // MARK: Where the files are kept

    @Test func theFolderIsKeptOutOfBackups() async throws {
        _ = await installer.survey()

        let values = try layout.root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func theAppsFolderIsInApplicationSupport() {
        let root = ModelStoreLayout.applicationSupport.root
        #expect(root.lastPathComponent == "PageTranslationModels")
        #expect(root.deletingLastPathComponent().standardizedFileURL == URL.applicationSupportDirectory.standardizedFileURL)
        #expect(!root.path().contains("Caches"))
    }

    // MARK: Looking at the folder

    @Test func anEmptyFolderHasNothing() async {
        let surveys = await installer.survey()

        #expect(surveys.count == StoreSamples.catalog.artifacts.count)
        #expect(surveys.values.allSatisfy { $0.record == nil && $0.bytesOnDisk == 0 && !$0.isComplete })
    }

    @Test func aSurveyCountsWhatADownloadLeft() async throws {
        let artifact = StoreSamples.artifact(.galTransl4B)
        let file = artifact.files[0]
        try copyIn(.galTransl4B, except: ["model.gguf"])
        let data = StoreSamples.data("model.gguf", of: .galTransl4B)
        try data.prefix(2 * 1024).write(to: layout.partURL(of: file, in: .galTransl4B))
        try data.subdata(in: 4096..<5120).write(to: layout.chunkURL(of: file, in: .galTransl4B, index: 4))

        let survey = await installer.survey(artifact)

        #expect(survey.record == nil)
        #expect(!survey.isComplete)
        #expect(survey.bytesOnDisk == 400 + 120 + 3 * 1024)
    }

    @Test func filesCopiedInAreCompleteButNotYetInstalled() async throws {
        try copyIn(.v4s)

        let survey = await installer.survey(StoreSamples.artifact(.v4s))

        #expect(survey.isComplete)
        #expect(survey.record == nil)
        #expect(survey.bytesOnDisk == StoreSamples.artifact(.v4s).downloadSize)
    }

    /// After a package was compiled and deleted its files are not asked for again, also
    /// when the app was killed before the record was written.
    @Test func anInstallCutShortIsNotDownloadedAgain() async throws {
        try copyIn(.cpt2)
        let artifact = StoreSamples.artifact(.cpt2)
        let installer = installer
        _ = try await installer.install(artifact)
        try FileManager.default.removeItem(at: layout.folder(of: .cpt2).appending(path: "installed.json"))

        let survey = await installer.survey(artifact)
        #expect(survey.record == nil)
        #expect(survey.isComplete)
        #expect(try await installer.filesToDownload(of: artifact).isEmpty)
        let record = try await installer.install(artifact)
        #expect(record.items.count == 5)
        #expect(compiler.compiled.count == 2)
    }

    @Test func aRecordOfAnotherVersionDoesNotCount() async throws {
        try copyIn(.v4s)
        let installer = installer
        var record = try await installer.install(StoreSamples.artifact(.v4s))
        record.version = "1"
        try JSONEncoder().encode(record).write(to: layout.folder(of: .v4s).appending(path: "installed.json"))

        #expect(await installer.survey(StoreSamples.artifact(.v4s)).record == nil)
    }

    @Test func aRecordWhoseModelIsGoneDoesNotCount() async throws {
        try copyIn(.v4s)
        let installer = installer
        _ = try await installer.install(StoreSamples.artifact(.v4s))
        try FileManager.default.removeItem(at: layout.compiledURL(ofPackage: "V4S.mlpackage", in: .v4s))

        #expect(await installer.survey(StoreSamples.artifact(.v4s)).record == nil)
    }

    // MARK: Checking

    @Test func filesInPlaceAreCheckedAgainstTheCatalog() async throws {
        try copyIn(.cpt2, corrupting: ["vocab.txt", "Decoder.mlpackage/Data/com.apple.CoreML/weights/weight.bin"])

        let unchecked = try await installer.uncheckedFiles(of: StoreSamples.artifact(.cpt2))

        #expect(unchecked.map(\.path) == ["Decoder.mlpackage/Data/com.apple.CoreML/weights/weight.bin", "vocab.txt"])
    }

    /// A file that does not match is refused: removed, and downloaded like a missing one.
    @Test func aFileThatDoesNotMatchIsRemovedAndAskedFor() async throws {
        try copyIn(.cpt2, except: ["LICENSE"], corrupting: ["vocab.txt"])

        let files = try await installer.filesToDownload(of: StoreSamples.artifact(.cpt2))

        #expect(files.map(\.path) == ["vocab.txt", "LICENSE"])
        #expect(!exists("vocab.txt", in: .cpt2))
        #expect(exists("CREDITS.md", in: .cpt2))
    }

    // MARK: Removing

    @Test func removingAnArtifactTakesItsWholeFolder() async throws {
        try copyIn(.v4s)
        try copyIn(.cpt2)
        let installer = installer
        _ = try await installer.install(StoreSamples.artifact(.v4s))

        await installer.remove(.v4s)

        #expect(!FileManager.default.fileExists(atPath: layout.folder(of: .v4s).path(percentEncoded: false)))
        #expect(exists("vocab.txt", in: .cpt2))
        #expect(await installer.survey(StoreSamples.artifact(.v4s)) == ModelArtifactSurvey())
    }

    @Test func discardingADownloadKeepsWholeFiles() async throws {
        let artifact = StoreSamples.artifact(.galTransl4B)
        let file = artifact.files[0]
        try copyIn(.galTransl4B, except: ["model.gguf"])
        try Data(count: 2048).write(to: layout.partURL(of: file, in: .galTransl4B))
        try Data(count: 1024).write(to: layout.chunkURL(of: file, in: .galTransl4B, index: 7))

        await installer.discardPartialDownloads(of: artifact)

        #expect(try FileManager.default.contentsOfDirectory(atPath: layout.folder(of: .galTransl4B).path(percentEncoded: false))
            .sorted() == ["CREDITS.md", "LICENSE"])
    }

    // MARK: What was asked for

    @Test func whatWasAskedForIsKeptOnDisk() async {
        let installer = installer
        #expect(await installer.intent() == ModelDownloadIntent())

        await installer.write(ModelDownloadIntent(artifacts: [.k2xl, .cpt2], isPaused: true))
        #expect(await installer.intent() == ModelDownloadIntent(artifacts: [.k2xl, .cpt2], isPaused: true))

        await installer.write(ModelDownloadIntent())
        #expect(!FileManager.default.fileExists(atPath: layout.root.appending(path: "downloads.json").path(percentEncoded: false)))
    }
}
