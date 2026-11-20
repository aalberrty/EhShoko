import EhModels
import Foundation

/// How far a download is.
public struct ModelTransferProgress: Sendable, Hashable {
    public var completedBytes: Int64
    public var totalBytes: Int64

    public init(completedBytes: Int64, totalBytes: Int64) {
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
    }

    public var fraction: Double {
        totalBytes > 0 ? min(1, max(0, Double(completedBytes) / Double(totalBytes))) : 0
    }
}

/// Why a download or an install stopped.
public enum ModelStoreFailure: Error, Sendable, Hashable {
    /// The download needs more room than the device has.
    case noSpace(needed: Int64, available: Int64)
    /// None of this user's sources offers the artifact.
    case noSource
    /// Every source answered without the file; the status is the last one's (403, 404, …).
    case refused(status: Int)
    /// No source could be reached.
    case unreachable
    /// What the sources sent is not the file the catalog lists.
    case checksumMismatch
    /// The files are there but could not be compiled or put in place.
    case installFailed
}

/// Where one artifact stands.
public enum ModelArtifactState: Sendable, Hashable {
    /// Not on the device, or only partly.
    case missing
    /// Asked for; nothing has moved yet.
    case waiting
    case downloading(ModelTransferProgress)
    case paused(ModelTransferProgress)
    /// Its files are being checked and compiled.
    case installing
    /// Its models are being loaded for the first time ("Preparing").
    case preparing
    case installed
    case failed(ModelStoreFailure)
}

/// Where the models of the current choices stand, taken together.
public enum ModelSetState: Sendable, Hashable {
    /// A choice has no model this user's sources offer: a source is needed first.
    case unavailable
    /// Ready to download; `bytes` is what is left to fetch.
    case missing(bytes: Int64)
    case downloading(ModelTransferProgress)
    /// A download is under way and there is no network. It goes on by itself.
    case waitingForConnection(ModelTransferProgress)
    case paused(ModelTransferProgress)
    /// Everything has arrived and is being checked, compiled or loaded for the first time.
    case preparing
    case ready
    case failed(ModelStoreFailure)
}

/// Where an installed artifact's files are, for whoever loads them.
public struct InstalledModelFiles: Sendable, Hashable {
    public var artifact: ModelArtifact
    public var folder: URL
    /// Whether its models have been loaded once since the install; a first load takes longer.
    public var isPrepared: Bool

    /// A file of the artifact by its path in the catalog.
    public func file(_ path: String) -> URL {
        folder.appending(path: path, directoryHint: .notDirectory)
    }

    /// The compiled model made from the package at `package` (its path in the catalog).
    public func compiledModel(ofPackage package: String) -> URL {
        folder.appending(path: ModelStoreLayout.compiledPath(ofPackage: package), directoryHint: .isDirectory)
    }
}

/// The settings the model store follows. Closures rather than the settings store itself,
/// so the store stands alone; read inside observation, they are tracked like any property.
public struct ModelStoreChoices: Sendable {
    public var modelSet: @MainActor @Sendable () -> PageTranslationModelSet
    public var repaint: @MainActor @Sendable () -> RepaintChoice
    /// The private store's address as the user typed it.
    public var sourceAddress: @MainActor @Sendable () -> String

    public init(
        modelSet: @escaping @MainActor @Sendable () -> PageTranslationModelSet,
        repaint: @escaping @MainActor @Sendable () -> RepaintChoice,
        sourceAddress: @escaping @MainActor @Sendable () -> String
    ) {
        self.modelSet = modelSet
        self.repaint = repaint
        self.sourceAddress = sourceAddress
    }
}

/// What the model store is built from. The app's values are in `ModelStoreDependencies`.
public struct ModelStoreEnvironment: Sendable {
    public var catalog: ModelCatalog
    public var layout: ModelStoreLayout
    public var transport: any ModelTransport
    public var compiler: ModelCompiler
    public var tokens: ModelSourceTokenStore
    public var publicStore: URL?
    /// The free bytes of the volume that holds a folder.
    public var freeSpace: @Sendable (URL) -> Int64
    /// Whether there is a network, now and each time that changes.
    public var connectivity: @Sendable () -> AsyncStream<Bool>
    /// A line for the app's log: a download's start and end, never its progress.
    public var log: @Sendable (String) -> Void
    public var chunkSize: Int64
    /// How many ranges are handed to the transport at once. The system runs a few of them
    /// at a time; the rest wait in its queue, which is what lets a download go on while the
    /// app is suspended. Enough for every range of the largest download.
    public var chunksInFlight: Int
    /// How a wait is spent; tests replace it.
    public var sleep: @Sendable (Duration) async throws -> Void

    public init(
        catalog: ModelCatalog = .generated,
        layout: ModelStoreLayout,
        transport: any ModelTransport,
        compiler: ModelCompiler,
        tokens: ModelSourceTokenStore,
        publicStore: URL? = ModelCatalog.publicStoreAddress,
        freeSpace: @escaping @Sendable (URL) -> Int64,
        connectivity: @escaping @Sendable () -> AsyncStream<Bool> = { AsyncStream { $0.finish() } },
        log: @escaping @Sendable (String) -> Void = { _ in },
        chunkSize: Int64 = ModelStoreEnvironment.standardChunkSize,
        chunksInFlight: Int = 96,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.catalog = catalog
        self.layout = layout
        self.transport = transport
        self.compiler = compiler
        self.tokens = tokens
        self.publicStore = publicStore
        self.freeSpace = freeSpace
        self.connectivity = connectivity
        self.log = log
        self.chunkSize = chunkSize
        self.chunksInFlight = chunksInFlight
        self.sleep = sleep
    }

    /// A file is fetched in ranges of this size.
    public static let standardChunkSize: Int64 = 32 << 20

    /// The room a download needs: one and a half times what is left to fetch plus 200 MB,
    /// because during an install a package and its compiled copy exist together.
    public static func spaceNeeded(forDownloading bytes: Int64) -> Int64 {
        bytes + bytes / 2 + 200_000_000
    }
}
