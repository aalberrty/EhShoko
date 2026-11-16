import EhModels
import Foundation

/// Where the model store keeps its files.
///
/// ```
/// <root>/                               Library/Application Support/PageTranslationModels
///   downloads.json                      What was asked for and is not finished
///   <artifact>/installed.json           What is installed, written last
///   <artifact>/<path>                   A file as the catalog lists it
///   <artifact>/<path>.part              …while it is being put together
///   <artifact>/<path>.chunk-<n>         …a range that arrived before its turn
///   <artifact>/<Name>.mlmodelc          A compiled package; the package itself is deleted
/// ```
///
/// Not in Caches: the system empties that folder when space is short, and losing gigabytes
/// of models would mean downloading them again. Excluded from backup instead.
public struct ModelStoreLayout: Sendable, Hashable {
    public var root: URL

    public init(root: URL) {
        self.root = root
    }

    /// The app's folder.
    public static var applicationSupport: ModelStoreLayout {
        let support = URL.applicationSupportDirectory
        return ModelStoreLayout(root: support.appending(path: "PageTranslationModels", directoryHint: .isDirectory))
    }

    public func folder(of artifact: ModelArtifactID) -> URL {
        root.appending(path: artifact.rawValue, directoryHint: .isDirectory)
    }

    /// A file of the catalog, as it is downloaded or copied in.
    public func url(of file: ModelFile, in artifact: ModelArtifactID) -> URL {
        folder(of: artifact).appending(path: file.path, directoryHint: .notDirectory)
    }

    /// A file by its path inside an artifact's folder.
    public func url(ofPath path: String, in artifact: ModelArtifactID) -> URL {
        folder(of: artifact).appending(path: path, directoryHint: .notDirectory)
    }

    func partURL(of file: ModelFile, in artifact: ModelArtifactID) -> URL {
        url(ofPath: file.path + ".part", in: artifact)
    }

    func chunkURL(of file: ModelFile, in artifact: ModelArtifactID, index: Int) -> URL {
        url(ofPath: file.path + ".chunk-\(index)", in: artifact)
    }

    /// Where the compiled form of a package is kept: `A/B.mlpackage` becomes `A/B.mlmodelc`.
    public func compiledURL(ofPackage package: String, in artifact: ModelArtifactID) -> URL {
        folder(of: artifact).appending(path: Self.compiledPath(ofPackage: package), directoryHint: .isDirectory)
    }

    static func compiledPath(ofPackage package: String) -> String {
        String(package.dropLast(ModelFile.packageExtension.count)) + ".mlmodelc"
    }

    func recordURL(of artifact: ModelArtifactID) -> URL {
        folder(of: artifact).appending(path: "installed.json", directoryHint: .notDirectory)
    }

    var intentURL: URL {
        root.appending(path: "downloads.json", directoryHint: .notDirectory)
    }

    /// Creates the folder and keeps it out of backups. The flag is the folder's, so it
    /// covers everything put inside later.
    func prepareRoot() throws {
        try ModelFiles.createFolder(root)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var folder = root
        try folder.setResourceValues(values)
    }
}

/// What `installed.json` records about an installed artifact.
public struct InstalledArtifact: Sendable, Hashable, Codable {
    public struct Item: Sendable, Hashable, Codable {
        /// Relative to the artifact's folder.
        public var path: String
        /// A compiled Core ML model (a folder) rather than a plain file.
        public var isCompiledModel: Bool
    }

    /// The catalog the files were checked against.
    public var catalogVersion: Int
    public var artifact: ModelArtifactID
    public var version: String
    public var items: [Item]
    /// What the artifact takes on disk.
    public var bytes: Int64
    /// Its Core ML models have been loaded once since the install, so the system has built
    /// their programs. Always true for an artifact that needs no such step.
    public var isPrepared: Bool
}

/// What `downloads.json` records: the artifacts that were asked for and are not installed
/// yet, so a download goes on after the app was closed.
struct ModelDownloadIntent: Sendable, Hashable, Codable {
    var artifacts: [ModelArtifactID] = []
    var isPaused = false
}
