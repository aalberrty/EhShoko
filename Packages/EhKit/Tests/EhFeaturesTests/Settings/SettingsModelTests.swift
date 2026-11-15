import Dependencies
import EhCore
import EhDatabase
import EhFeatures
import EhModels
import EhTestSupport
import Foundation
import Testing

@Suite struct AppIconModelTests {
    /// The calls to `setAlternateIconName`, and the icon the system then reports.
    private nonisolated final class SystemIcon: Sendable {
        let shown: SettingsTestLock<String?>
        let requests = SettingsTestLock<[String?]>([])
        init(_ shown: String?) { self.shown = SettingsTestLock(shown) }
    }

    private func makeModel(_ system: SystemIcon, settings: SettingsStore, accepts: Bool = true) -> AppIconModel {
        withDependencies {
            $0.settings = settings
            $0.applicationClient.alternateIconName = { system.shown.withLock { $0 } }
            $0.applicationClient.setAlternateIconName = { name in
                system.requests.withLock { $0.append(name) }
                if accepts { system.shown.withLock { $0 = name } }
                return accepts
            }
        } operation: { AppIconModel() }
    }

    @Test func withOneIconSettingsOffersNoChoice() {
        #expect(AppIconType.allCases.count == 1)
        #expect(!AppIconModel.offersChoice)
    }

    @Test func choosingTheIconShownAsksTheSystemNothing() async {
        let system = SystemIcon(nil)
        let settings = SettingsStore.ephemeral()
        let model = makeModel(system, settings: settings)

        await model.select(.default)

        #expect(system.requests.withLock { $0 }.isEmpty)
        #expect(settings.appIconType == .default)
    }

    @Test func choosingTheDefaultRestoresThePrimaryIcon() async {
        // The system still shows an alternate that is no longer in the app.
        let system = SystemIcon("AppIcon_Ukiyoe")
        let settings = SettingsStore.ephemeral()
        let model = makeModel(system, settings: settings)

        await model.select(.default)

        #expect(system.requests.withLock { $0 } == [nil])
        #expect(system.shown.withLock { $0 } == nil)
        #expect(settings.appIconType == .default)
    }

    @Test func aRefusedChangeRecordsTheIconTheSystemShows() async {
        let system = SystemIcon("AppIcon_Ukiyoe")
        let settings = SettingsStore.ephemeral()
        let model = makeModel(system, settings: settings, accepts: false)

        await model.select(.default)

        #expect(system.requests.withLock { $0 } == [nil])
        #expect(system.shown.withLock { $0 } == "AppIcon_Ukiyoe")
        #expect(settings.appIconType == .default)
    }

    @Test(arguments: [nil, "AppIcon_Ukiyoe"] as [String?])
    func syncReadsThePrimaryAndRemovedIconsAsTheDefault(name: String?) {
        let settings = SettingsStore.ephemeral()
        let model = makeModel(SystemIcon(name), settings: settings)

        model.syncWithSystem()

        #expect(settings.appIconType == .default)
    }
}

@Suite struct GeneralSettingsModelTests {
    @Test func appearingChecksThePasscodeAndMeasuresTheCache() async {
        let model = withDependencies {
            $0.biometricsClient.isAvailable = { false }
            $0.imageCacheClient.diskCacheSize = { 4096 }
        } operation: { GeneralSettingsModel() }
        #expect(model.isPasscodeSet)
        #expect(model.imageCacheSize == nil)

        await model.onAppear()

        #expect(!model.isPasscodeSet)
        #expect(model.imageCacheSize == 4096)
    }

    @Test func aFailedMeasurementKeepsTheSizeUnknown() async {
        struct Failure: Error {}
        let model = withDependencies {
            $0.imageCacheClient.diskCacheSize = { throw Failure() }
        } operation: { GeneralSettingsModel() }

        await model.refreshImageCacheSize()

        #expect(model.imageCacheSize == nil)
    }

    @Test func clearingTheCacheRemovesStoredImageURLsAndRemeasures() async throws {
        let database = try await TestDatabase.inMemory()
        let url = URL(string: "https://ehgt.org/image.webp")
        try await database.upsertPages([
            GalleryPage(gid: "1", index: 1, imageURL: url, previewURL: url),
            GalleryPage(gid: "2", index: 3, pageURL: url, originalImageURL: url)
        ])
        let size = SettingsTestLock(1_000_000)
        let model = withDependencies {
            $0.database = database
            $0.imageCacheClient.diskCacheSize = { size.withLock { $0 } }
            $0.imageCacheClient.clearDiskCache = { size.withLock { $0 = 0 } }
        } operation: { GeneralSettingsModel() }
        await model.refreshImageCacheSize()
        #expect(model.imageCacheSize == 1_000_000)

        await model.clearImageCache()

        #expect(model.imageCacheSize == 0)
        #expect(!model.isClearingImageCache)
        #expect(try await database.pages(gid: "1").isEmpty)
        #expect(try await database.pages(gid: "2").isEmpty)
    }

    @Test func languageOpensTheSettingsApp() async {
        let opened = SettingsTestLock(false)
        let model = withDependencies {
            $0.applicationClient.openSettings = { opened.withLock { $0 = true } }
        } operation: { GeneralSettingsModel() }

        await model.openSystemSettings()

        #expect(opened.withLock { $0 })
    }
}

@Suite struct ReadingSettingsModelTests {
    private func makeModel(isPad: Bool, settings: SettingsStore, locks: SettingsTestLock<[OrientationLock]>) -> ReadingSettingsModel {
        withDependencies {
            $0.settings = settings
            $0.applicationClient.isPad = { isPad }
            $0.applicationClient.setOrientationLock = { lock in locks.withLock { $0.append(lock) } }
        } operation: { ReadingSettingsModel() }
    }

    @Test func turningLandscapeOffOnIPhoneRestoresPortrait() {
        let settings = SettingsStore.ephemeral()
        let locks = SettingsTestLock<[OrientationLock]>([])
        let model = makeModel(isPad: false, settings: settings, locks: locks)

        model.setEnablesLandscape(true)
        #expect(settings.enablesLandscape)
        #expect(locks.withLock { $0 }.isEmpty)

        model.setEnablesLandscape(false)
        #expect(!settings.enablesLandscape)
        #expect(locks.withLock { $0 } == [.portrait])
    }

    @Test func iPadKeepsItsOrientation() {
        let settings = SettingsStore.ephemeral()
        let locks = SettingsTestLock<[OrientationLock]>([])
        let model = makeModel(isPad: true, settings: settings, locks: locks)

        model.setEnablesLandscape(false)

        #expect(locks.withLock { $0 }.isEmpty)
    }
}
