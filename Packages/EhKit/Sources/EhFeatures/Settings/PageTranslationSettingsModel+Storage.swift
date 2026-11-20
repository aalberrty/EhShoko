import EhCore
import EhModels
import Foundation

// Storage, the private model source and the credits of Settings › Translation.

/// An installed model, as the storage section lists it.
nonisolated public struct InstalledPageTranslationModel: Identifiable, Equatable, Sendable {
    public var id: ModelArtifactID
    /// The choice it serves; `nil` for an artifact no choice names.
    public var choice: PageTranslationChoice?
    /// Its name in the catalog's credit, for an artifact no choice names.
    public var name: String
    public var bytes: Int64
}

/// What one model's licence asks the app to show (`README.md` section 15.4).
nonisolated public struct PageTranslationModelCredit: Identifiable, Equatable, Sendable {
    public var id: ModelArtifactID
    public var choice: PageTranslationChoice?
    public var credit: ArtifactCredit
    /// The licence's full text is in a file beside the installed model.
    public var hasLicenceFile: Bool
}

/// A licence's full text, read from the file that came with its model.
nonisolated public struct LicenceText: Identifiable, Equatable, Sendable {
    public var id: ModelArtifactID
    /// The model's name, as its credit gives it.
    public var name: String
    public var text: String

    public init(id: ModelArtifactID, name: String, text: String) {
        self.id = id
        self.name = name
        self.text = text
    }
}

extension PageTranslationSettingsModel {
    /// Whether the private store's address, as typed, can be used.
    nonisolated public enum AddressState: Hashable, Sendable {
        case empty
        case valid
        /// Not an address a store can have: it needs `https` and a host (`http` only for
        /// this device).
        case invalid
    }

    // MARK: Models on this device

    /// The installed models, in the catalog's order.
    public var installedModels: [InstalledPageTranslationModel] {
        store.catalog.artifacts.compactMap { artifact in
            guard store.installedFiles(of: artifact.id) != nil else { return nil }
            return InstalledPageTranslationModel(
                id: artifact.id, choice: .choice(downloading: artifact.id), name: artifact.credit.name,
                bytes: store.installedBytes(of: artifact.id)
            )
        }
    }

    /// What every installed model takes together.
    public var installedBytes: Int64 { store.installedBytes }

    /// Whether Delete All has anything to delete: an installed model, or a download that has
    /// started (Delete All also stops downloads and removes what they left).
    public var canDeleteAll: Bool {
        store.installedBytes > 0 || store.catalog.artifacts.contains { artifact in
            switch store.state(of: artifact.id) {
            case .missing, .installed: false
            case .waiting, .downloading, .paused, .installing, .preparing, .failed: true
            }
        }
    }

    /// Deletes one model. Whatever has it loaded lets go first (the store sees to it).
    public func delete(_ artifact: ModelArtifactID) async {
        await store.delete([artifact])
    }

    /// Deletes every model and whatever unfinished downloads left.
    public func deleteAll() async {
        await store.deleteAll()
    }

    // MARK: Translated pages

    /// Measures the patch files in the patch store, off the main actor.
    func measureTranslatedPages() async {
        translatedPagesBytes = Int64(await patchStore.size())
    }

    /// Removes every translated page: results not yet written, every stored row (so nothing
    /// stays recoverable) and every patch file. Clear History does the same.
    public func clearTranslatedPages() async {
        guard !isClearingTranslatedPages else { return }
        isClearingTranslatedPages = true
        defer { isClearingTranslatedPages = false }
        do {
            try await resultWriter.removeAll(patchStore: patchStore)
        } catch {
            // The patch files are gone either way; the rows are tried again by the next Clear.
            logger.warning("Translated pages' text could not be deleted: \(error)", category: "PageTranslation")
        }
        await measureTranslatedPages()
    }

    // MARK: The private model source

    public var addressState: AddressState {
        if addressDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .empty }
        return ModelSourceConfiguration.address(from: addressDraft) == nil ? .invalid : .valid
    }

    /// Writes the typed address to the settings. It applies to the next download; one under
    /// way keeps the source it started with.
    public func commitAddress() {
        guard settings.pageTranslationSourceAddress != addressDraft else { return }
        settings.pageTranslationSourceAddress = addressDraft
    }

    /// Whether a token for the private store is kept. The token itself is never read back.
    public var hasToken: Bool { store.hasSourceToken }

    /// Keeps the token in the Keychain. An empty text keeps the one there was.
    public func saveToken(_ token: String) async {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await writeToken(trimmed)
    }

    public func removeToken() async {
        await writeToken(nil)
    }

    private func writeToken(_ token: String?) async {
        do {
            try await store.setSourceToken(token)
        } catch {
            // The Keychain refused: the token row keeps showing what is kept.
            logger.warning("The access token could not be kept: \(error)", category: "PageTranslation")
        }
    }

    // MARK: Models and licences

    /// Every model of the catalog with what its licence asks the app to show.
    public var credits: [PageTranslationModelCredit] {
        store.catalog.artifacts.map { artifact in
            PageTranslationModelCredit(
                id: artifact.id, choice: .choice(downloading: artifact.id), credit: artifact.credit,
                hasLicenceFile: artifact.licenceFile != nil && store.installedFiles(of: artifact.id) != nil
            )
        }
    }

    /// Shows the full text of a model's licence from the file beside it. Read off the main
    /// actor; nothing is shown when the file cannot be read.
    public func showLicence(of id: ModelArtifactID) async {
        guard let files = store.installedFiles(of: id), let file = files.artifact.licenceFile else { return }
        guard let text = await Self.readText(files.file(file.path)) else { return }
        licence = LicenceText(id: id, name: files.artifact.credit.name, text: text)
    }

    @concurrent
    nonisolated private static func readText(_ url: URL) async -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }
}
