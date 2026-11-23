import EhModels
import Foundation

/// The models page translation can download: every file of each with its size and SHA-256,
/// plus whose it is and how it is loaded.
///
/// The catalog is compiled into the app (`ModelCatalog.generated`, written by
/// `Scripts/translation_catalog.py`), so whatever host a file comes from, it is accepted only
/// when its size and checksum match what is written here. The address of a private store is
/// never part of it: that is entered in Settings.
public struct ModelCatalog: Sendable, Hashable, Codable {
    /// Raised by the script whenever an entry changes.
    public var version: Int
    /// In the order choices fall back: of a kind, an earlier artifact is preferred.
    public var artifacts: [ModelArtifact]

    public init(version: Int, artifacts: [ModelArtifact]) {
        self.version = version
        self.artifacts = artifacts
    }

    /// The address of the store anyone can read: the artifacts marked `.publicStore`, laid out
    /// as a private store is. A public address is not a secret.
    public static let publicStoreAddress: URL? = URL(
        string: "https://huggingface.co/aalberrty/ehshoko-models-public/resolve/main"
    )

    public func artifact(_ id: ModelArtifactID) -> ModelArtifact? {
        artifacts.first { $0.id == id }
    }

    public func artifacts(for role: ModelRole) -> [ModelArtifact] {
        artifacts.filter { $0.role == role }
    }
}

/// One model with the files it needs.
public struct ModelArtifact: Sendable, Hashable, Codable, Identifiable {
    public var id: ModelArtifactID
    /// The folder under the artifact in a store. A changed model gets a new version, so an
    /// installed app keeps finding the files it knows.
    public var version: String
    public var role: ModelRole
    public var sharing: ArtifactSharing
    public var credit: ArtifactCredit
    public var loading: ModelLoading
    /// Where its author or publisher offers the files, most preferred first: each address is
    /// followed by a file's path. Empty unless `sharing` is `.fromPublisher`.
    public var publisherAddresses: [URL]
    public var files: [ModelFile]

    public init(
        id: ModelArtifactID, version: String, role: ModelRole, sharing: ArtifactSharing, credit: ArtifactCredit,
        loading: ModelLoading, publisherAddresses: [URL] = [], files: [ModelFile]
    ) {
        self.id = id
        self.version = version
        self.role = role
        self.sharing = sharing
        self.credit = credit
        self.loading = loading
        self.publisherAddresses = publisherAddresses
        self.files = files
    }

    /// What there is to download, in bytes.
    public var downloadSize: Int64 {
        files.reduce(0) { $0 + $1.size }
    }

    /// The Core ML packages among the files, as paths relative to the artifact's folder.
    public var packages: [String] {
        var seen: Set<String> = []
        return files.compactMap(\.package).filter { seen.insert($0).inserted }
    }

    /// The licence's full text, when the artifact carries it as a file.
    public var licenceFile: ModelFile? {
        files.first { $0.path == ModelFile.licenceName }
    }

    /// The author, the source and what was changed, when the artifact carries them as a file.
    public var creditsFile: ModelFile? {
        files.first { $0.path == ModelFile.creditsName }
    }
}

/// One file of an artifact. A Core ML package is a folder, so it is listed as its files.
public struct ModelFile: Sendable, Hashable, Codable {
    /// Relative to the artifact's folder, in a store and on the device alike.
    public var path: String
    public var size: Int64
    /// Lowercase hexadecimal.
    public var sha256: String

    public init(_ path: String, _ size: Int64, _ sha256: String) {
        self.path = path
        self.size = size
        self.sha256 = sha256
    }

    static let licenceName = "LICENSE"
    static let creditsName = "CREDITS.md"
    static let packageExtension = ".mlpackage"

    /// The Core ML package this file is part of, as a path relative to the artifact's folder.
    public var package: String? {
        let components = path.split(separator: "/")
        // The last component is the file itself, never the package.
        guard let index = components.dropLast().firstIndex(where: { $0.hasSuffix(Self.packageExtension) })
        else { return nil }
        return components[...index].joined(separator: "/")
    }
}

/// Whether a copy of an artifact may be passed on, and so where it is looked for.
public enum ArtifactSharing: String, Sendable, Hashable, Codable {
    /// Downloaded where its author or publisher offers it.
    case fromPublisher
    /// The project may pass it on: a private store, or the public one.
    case publicStore
    /// The project may not pass it on: a private store only.
    case privateOnly
}

/// What the licences require the app to show and to pass on. Data, never translated.
public struct ArtifactCredit: Sendable, Hashable, Codable {
    public var name: String
    public var author: String
    /// The original the artifact was made from.
    public var source: URL
    /// The licence's name, such as "Apache-2.0".
    public var licence: String
    /// The licence's full text.
    public var licenceText: URL
    /// What the project changed, or `nil` when the files are the author's own.
    public var changes: String?
    public var nonCommercial: Bool

    public init(
        name: String, author: String, source: URL, licence: String, licenceText: URL, changes: String?,
        nonCommercial: Bool
    ) {
        self.name = name
        self.author = author
        self.source = source
        self.licence = licence
        self.licenceText = licenceText
        self.changes = changes
        self.nonCommercial = nonCommercial
    }
}

/// How an artifact is loaded once it is installed.
public enum ModelLoading: Sendable, Hashable, Codable {
    /// Core ML packages, compiled on the device and loaded once after the install.
    case coreML(ModelComputeUnits)
    /// One file read by the language-model runtime: neither compiled nor prepared.
    /// `promptFamily` names the prompt the translator renders for it.
    case languageModel(promptFamily: String)
}

/// The Core ML compute units an artifact was measured with.
public enum ModelComputeUnits: String, Sendable, Hashable, Codable {
    case cpuOnly
    case cpuAndGPU
    case cpuAndNeuralEngine
    case all
}

extension URL {
    /// An address of the generated catalog, which writes them as text. The force unwrap
    /// cannot fail in a shipped build: the catalog is a static constant and its tests build
    /// every entry.
    static func catalog(_ text: StaticString) -> URL {
        URL(string: "\(text)")!
    }
}
