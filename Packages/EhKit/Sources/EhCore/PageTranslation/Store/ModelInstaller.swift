import CoreML
import EhModels
import Foundation

/// Turns a Core ML package into what the app loads. Tests replace it.
public struct ModelCompiler: Sendable {
    /// Compiles the package at the given place and returns where the compiled model was
    /// put, which is a temporary place.
    public var compile: @Sendable (URL) async throws -> URL
    /// Loads a compiled model once with the compute units it will run on, so the system
    /// builds its program now and keeps it.
    public var prepare: @Sendable (URL, ModelComputeUnits) async throws -> Void

    public init(
        compile: @escaping @Sendable (URL) async throws -> URL,
        prepare: @escaping @Sendable (URL, ModelComputeUnits) async throws -> Void
    ) {
        self.compile = compile
        self.prepare = prepare
    }

    /// Core ML itself. Both calls are its asynchronous ones, which do their work on Core
    /// ML's own threads.
    public static let coreML = ModelCompiler(
        compile: { try await MLModel.compileModel(at: $0) },
        prepare: { url, units in
            let configuration = MLModelConfiguration()
            configuration.computeUnits = switch units {
            case .cpuOnly: .cpuOnly
            case .cpuAndGPU: .cpuAndGPU
            case .cpuAndNeuralEngine: .cpuAndNeuralEngine
            case .all: .all
            }
            _ = try await MLModel.load(contentsOf: url, configuration: configuration)
        }
    )
}

/// What the installer found on disk for one artifact.
struct ModelArtifactSurvey: Sendable, Equatable {
    /// The record of a finished install whose files are all there.
    var record: InstalledArtifact?
    /// Bytes of the artifact's download that are on disk.
    var bytesOnDisk: Int64 = 0
    /// Every file is in place but nothing says they were checked: files copied in, or an
    /// install that was cut short.
    var isComplete = false
}

/// Everything the model store does to files on disk: looking at what is there, checking
/// files against the catalog, compiling, recording, removing. An actor, so installs happen
/// one at a time and never on the main actor.
actor ModelInstaller {
    let layout: ModelStoreLayout
    let catalog: ModelCatalog
    private let compiler: ModelCompiler
    private let downloader: ModelDownloader
    /// One heavy step at a time: an actor alone lets a second install start while the
    /// first waits for Core ML.
    private let heavyWork = ModelWorkSlots(1)

    init(layout: ModelStoreLayout, catalog: ModelCatalog, compiler: ModelCompiler, downloader: ModelDownloader) {
        self.layout = layout
        self.catalog = catalog
        self.compiler = compiler
        self.downloader = downloader
    }

    // MARK: Looking

    func survey() -> [ModelArtifactID: ModelArtifactSurvey] {
        try? layout.prepareRoot()
        var surveys: [ModelArtifactID: ModelArtifactSurvey] = [:]
        for artifact in catalog.artifacts {
            surveys[artifact.id] = survey(artifact)
        }
        return surveys
    }

    func survey(_ artifact: ModelArtifact) -> ModelArtifactSurvey {
        if let record = record(of: artifact) { return ModelArtifactSurvey(record: record, bytesOnDisk: artifact.downloadSize) }
        var survey = ModelArtifactSurvey(isComplete: true)
        for file in artifact.files {
            if isInPlace(file, of: artifact) {
                survey.bytesOnDisk += file.size
            } else {
                survey.isComplete = false
                survey.bytesOnDisk += downloader.bytesOnDisk(of: file, in: artifact.id)
            }
        }
        return survey
    }

    /// The record of `artifact`, when it is of this version and everything it lists exists.
    private func record(of artifact: ModelArtifact) -> InstalledArtifact? {
        guard let data = try? Data(contentsOf: layout.recordURL(of: artifact.id)),
              let record = try? JSONDecoder().decode(InstalledArtifact.self, from: data),
              record.artifact == artifact.id, record.version == artifact.version
        else { return nil }
        let complete = record.items.allSatisfy { ModelFiles.exists(layout.url(ofPath: $0.path, in: artifact.id)) }
        return complete ? record : nil
    }

    /// Whether `file` needs no download: it is there at its size, or the package it belongs
    /// to has been compiled already (the package is deleted once it is).
    private func isInPlace(_ file: ModelFile, of artifact: ModelArtifact) -> Bool {
        if ModelFiles.size(of: layout.url(of: file, in: artifact.id)) == file.size { return true }
        guard let package = file.package else { return false }
        return !ModelFiles.exists(layout.folder(of: artifact.id).appending(path: package))
            && ModelFiles.exists(layout.compiledURL(ofPackage: package, in: artifact.id))
    }

    // MARK: Checking

    private func mismatchedFiles(of artifact: ModelArtifact) async throws -> [ModelFile] {
        var mismatched: [ModelFile] = []
        for file in artifact.files {
            let url = layout.url(of: file, in: artifact.id)
            guard ModelFiles.size(of: url) == file.size else { continue }
            if try await ModelChecksum.sha256(of: url) != file.sha256 { mismatched.append(file) }
        }
        return mismatched
    }

    /// The files of `artifact` that are in place but are not what the catalog lists.
    func uncheckedFiles(of artifact: ModelArtifact) async throws -> [ModelFile] {
        try await heavyWork.withSlot { try await self.mismatchedFiles(of: artifact) }
    }

    /// The files still to download. A file in place that does not match the catalog is
    /// refused: it is removed and downloaded like a missing one.
    func filesToDownload(of artifact: ModelArtifact) async throws -> [ModelFile] {
        try layout.prepareRoot()
        for file in try await uncheckedFiles(of: artifact) {
            ModelFiles.remove(layout.url(of: file, in: artifact.id))
        }
        return artifact.files.filter { !isInPlace($0, of: artifact) }
    }

    // MARK: Installing

    /// Compiles the artifact's packages, deletes them and writes the record. Every file
    /// must be in place and checked. A language-model file is left as it is.
    func install(_ artifact: ModelArtifact) async throws -> InstalledArtifact {
        try await heavyWork.withSlot { try await self.compileAndRecord(artifact) }
    }

    private func compileAndRecord(_ artifact: ModelArtifact) async throws -> InstalledArtifact {
        var items: [InstalledArtifact.Item] = []
        for package in artifact.packages {
            let source = layout.folder(of: artifact.id).appending(path: package, directoryHint: .isDirectory)
            let compiled = layout.compiledURL(ofPackage: package, in: artifact.id)
            if ModelFiles.exists(source) {
                try Task.checkCancellation()
                let temporary = try await compiler.compile(source)
                try ModelFiles.move(temporary, to: compiled)
                // The model is on disk once: the package is not kept beside its compiled form.
                ModelFiles.remove(source)
            } else if !ModelFiles.exists(compiled) {
                throw CocoaError(.fileNoSuchFile)
            }
            items.append(.init(path: ModelStoreLayout.compiledPath(ofPackage: package), isCompiledModel: true))
        }
        for file in artifact.files where file.package == nil {
            guard ModelFiles.size(of: layout.url(of: file, in: artifact.id)) == file.size else {
                throw CocoaError(.fileNoSuchFile)
            }
            items.append(.init(path: file.path, isCompiledModel: false))
        }
        let needsPreparing = if case .coreML = artifact.loading { !artifact.packages.isEmpty } else { false }
        let record = InstalledArtifact(
            catalogVersion: catalog.version, artifact: artifact.id, version: artifact.version, items: items,
            bytes: items.reduce(0) { $0 + ModelFiles.totalSize(of: layout.url(ofPath: $1.path, in: artifact.id)) },
            isPrepared: !needsPreparing
        )
        try write(record)
        return record
    }

    /// Loads each compiled model of an installed artifact once and records that it was done.
    func prepare(_ artifact: ModelArtifact, record: InstalledArtifact) async throws -> InstalledArtifact {
        try await heavyWork.withSlot { try await self.loadOnce(artifact, record: record) }
    }

    private func loadOnce(_ artifact: ModelArtifact, record: InstalledArtifact) async throws -> InstalledArtifact {
        guard !record.isPrepared, case .coreML(let units) = artifact.loading else { return record }
        for item in record.items where item.isCompiledModel {
            try Task.checkCancellation()
            try await compiler.prepare(layout.url(ofPath: item.path, in: artifact.id), units)
        }
        var prepared = record
        prepared.isPrepared = true
        try write(prepared)
        return prepared
    }

    private func write(_ record: InstalledArtifact) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: layout.recordURL(of: record.artifact), options: .atomic)
    }

    // MARK: Removing

    /// Removes everything of an artifact: its models, its record and what a download left.
    func remove(_ artifact: ModelArtifactID) {
        ModelFiles.remove(layout.folder(of: artifact))
    }

    /// Removes what unfinished downloads of `artifact` left, keeping files that are whole.
    func discardPartialDownloads(of artifact: ModelArtifact) {
        for file in artifact.files {
            downloader.discard(ModelFileJob(artifact: artifact.id, file: file, sources: []))
        }
    }

    // MARK: What was asked for

    func intent() -> ModelDownloadIntent {
        guard let data = try? Data(contentsOf: layout.intentURL),
              let intent = try? JSONDecoder().decode(ModelDownloadIntent.self, from: data)
        else { return ModelDownloadIntent() }
        return intent
    }

    func write(_ intent: ModelDownloadIntent) {
        guard !intent.artifacts.isEmpty else {
            ModelFiles.remove(layout.intentURL)
            return
        }
        try? layout.prepareRoot()
        try? JSONEncoder().encode(intent).write(to: layout.intentURL, options: .atomic)
    }
}
