import EhModels
import Foundation

/// The stores this user's models may come from.
public struct ModelSourceConfiguration: Sendable, Hashable {
    /// The private store's address, when one is entered and valid.
    public var privateStore: URL?
    /// The private store's token. It goes to that store and to no other source.
    public var token: String?
    /// The store anyone can read, when there is one.
    public var publicStore: URL?

    public init(
        privateStore: URL? = nil, token: String? = nil, publicStore: URL? = ModelCatalog.publicStoreAddress
    ) {
        self.privateStore = privateStore
        self.token = token
        self.publicStore = publicStore
    }

    /// The address a user typed, or `nil` when it cannot be a store: it needs a host and
    /// `https`. Plain `http` is taken for this device alone (a developer's own server), so a
    /// token never crosses a network unencrypted.
    public static func address(from text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        guard let url = URL(string: trimmed), let host = url.host(), !host.isEmpty, url.user() == nil,
              url.query() == nil, url.fragment() == nil
        else { return nil }
        switch url.scheme?.lowercased() {
        case "https": return url
        case "http": return ["localhost", "127.0.0.1", "::1"].contains(host) ? url : nil
        default: return nil
        }
    }

    /// Whether any source can provide `artifact`.
    public func offers(_ artifact: ModelArtifact) -> Bool {
        switch artifact.sharing {
        case .fromPublisher: !artifact.publisherAddresses.isEmpty || privateStore != nil
        case .publicStore: privateStore != nil || publicStore != nil
        case .privateOnly: privateStore != nil
        }
    }

    /// Where `file` is looked for, in order: its publisher, the private store, the public
    /// store, each left out when it does not apply. A source that does not have the file
    /// answers "not found" and the next is asked.
    public func sources(for file: ModelFile, of artifact: ModelArtifact) -> [ModelFileSource] {
        var sources: [ModelFileSource] = []
        if artifact.sharing == .fromPublisher {
            sources += artifact.publisherAddresses.map {
                ModelFileSource(kind: .publisher, url: $0.appending(path: file.path), token: nil)
            }
        }
        let storePath = "\(artifact.id.rawValue)/\(artifact.version)/\(file.path)"
        if let privateStore {
            // Whoever set a private store up meant it, so it is asked for every artifact.
            sources.append(ModelFileSource(kind: .privateStore, url: privateStore.appending(path: storePath), token: token))
        }
        if artifact.sharing == .publicStore, let publicStore {
            sources.append(ModelFileSource(kind: .publicStore, url: publicStore.appending(path: storePath), token: nil))
        }
        return sources
    }
}

/// One place a file can be downloaded from.
public struct ModelFileSource: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case publisher, privateStore, publicStore
    }

    public var kind: Kind
    /// The file's own address at this source.
    public var url: URL
    /// Sent to `url`'s host and never to one it redirects to. Only a private store has one.
    public var token: String?

    public init(kind: Kind, url: URL, token: String?) {
        self.kind = kind
        self.url = url
        self.token = token
    }
}
