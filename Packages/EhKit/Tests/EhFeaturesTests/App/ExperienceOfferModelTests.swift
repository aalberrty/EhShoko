import Dependencies
@testable import EhCore
@testable import EhFeatures
import EhModels
import EhNetworking
import EhTestSupport
import Foundation
import Testing

@MainActor @Suite struct ExperienceOfferModelTests {
    // MARK: When it shows

    @Test func aFreshStoreIsOfferedOnce() {
        let harness = OfferHarness()
        #expect(!harness.model.isPresented)

        harness.activate()
        #expect(harness.router.offer)
        #expect(harness.model.isPresented)

        harness.model.appeared()
        #expect(harness.store.experienceOfferShown)
        harness.model.notNow()
        #expect(!harness.model.isPresented)

        // Every later activation, in this process or after a relaunch over the same defaults.
        harness.activate()
        #expect(!harness.router.offer)
        let relaunched = OfferHarness(defaults: harness.defaults)
        relaunched.activate()
        #expect(!relaunched.router.offer)
    }

    /// The import of an earlier build's settings (or the old app's) does not set the flag.
    @Test func anImportedStoreIsOfferedOnce() {
        let defaults = CountingDefaults()
        var earlier = Setting()
        earlier.galleryHost = .exhentai
        earlier.autoLockPolicy = .min5
        earlier.designBar = .command
        earlier.designList = .ledger
        SettingsStore(storage: PreferenceStorage(defaults)).apply(earlier)
        let harness = OfferHarness(defaults: defaults)
        #expect(!harness.store.experienceOfferShown)

        harness.activate()
        #expect(harness.model.isPresented)
        harness.model.appeared()
        harness.model.notNow()

        harness.activate()
        #expect(!harness.router.offer)
        #expect(OfferHarness(defaults: defaults).store.experienceOfferShown)
    }

    @Test func itIsDueOnlyOnceReadyAndUnlocked() {
        let harness = OfferHarness()
        #expect(!harness.model.isDue(isReady: false, isUnlocked: true, isOpeningLink: false))
        #expect(!harness.model.isDue(isReady: true, isUnlocked: false, isOpeningLink: false))
        #expect(harness.model.isDue(isReady: true, isUnlocked: true, isOpeningLink: false))

        harness.model.offerIfDue(isReady: true, isUnlocked: false, isOpeningLink: false)
        #expect(!harness.router.offer)
    }

    @Test func itWaitsForTheGreetingToBeDismissed() {
        let harness = OfferHarness()
        harness.router.presentedGreeting = Greeting()
        // The greeting is no reason to skip this activation: the offer queues behind it.
        harness.activate()
        #expect(harness.router.offer)
        #expect(!harness.model.isPresented)

        harness.router.presentedGreeting = nil
        #expect(harness.model.isPresented)
    }

    @Test func itWaitsForSettingsAndTheReader() {
        let harness = OfferHarness()
        harness.router.presentSettings([.settings(.login)])
        harness.activate()
        #expect(!harness.model.isPresented)
        harness.router.dismissSettings()
        #expect(harness.model.isPresented)

        harness.router.reading = ReadingRequest(gallery: AppFixture.gallery(), page: 1)
        #expect(!harness.model.isPresented)
        harness.router.reading = nil
        #expect(harness.model.isPresented)
    }

    // MARK: Links first

    @Test func aLinkBeingOpenedPutsItOffToTheNextActivation() {
        let harness = OfferHarness()
        harness.activate(isOpeningLink: true)
        #expect(!harness.router.offer)

        harness.router.present(AppFixture.gallery())
        harness.activate()
        #expect(!harness.router.offer)

        harness.router.dismissPresentedGallery()
        harness.activate()
        #expect(harness.model.isPresented)
    }

    @Test func aLinkPresentedWhileQueuedWithdrawsTheOffer() {
        let harness = OfferHarness()
        harness.router.presentedGreeting = Greeting()
        harness.activate()
        #expect(harness.router.offer)

        harness.router.present(AppFixture.gallery())
        harness.model.linkPresented()
        harness.router.presentedGreeting = nil
        harness.router.dismissPresentedGallery()
        #expect(!harness.model.isPresented)
        #expect(!harness.store.experienceOfferShown)

        harness.activate()
        #expect(harness.model.isPresented)
    }

    @Test func aLinkPresentedOverTheSheetEndsIt() {
        let harness = OfferHarness()
        harness.activate()
        harness.model.appeared()

        harness.router.present(AppFixture.gallery())
        harness.model.linkPresented()
        harness.model.didDismiss()
        harness.router.dismissPresentedGallery()
        harness.activate()

        #expect(!harness.model.isPresented)
        #expect(!harness.router.isSettingsPresented)
    }

    /// "Set up step by step", then a link while the sheet is still going: the link wins.
    @Test func aLinkWhileTheSheetClosesForTheWizardWins() {
        let harness = OfferHarness()
        harness.activate()
        harness.model.appeared()
        harness.model.setUp()

        harness.router.present(AppFixture.gallery())
        harness.model.linkPresented()
        harness.model.didDismiss()

        #expect(!harness.router.isSettingsPresented)
        #expect(harness.router.presentedGallery != nil)
    }

    // MARK: Ways out

    @Test func useWritesThePresetOnce() {
        let harness = OfferHarness()
        harness.activate()
        harness.model.appeared()
        #expect(harness.model.selection == .shelf)
        harness.defaults.reset()

        harness.model.selection = .ledger
        harness.model.use()

        #expect(!harness.model.isPresented)
        #expect(harness.store.designChoices == DesignChoices(preset: .ledger))
        #expect(harness.defaults.counts == [
            .designBar: 1, .designStart: 1, .designList: 1, .designGallery: 1,
            .designReader: 1, .designSearch: 1, .designLibrary: 1, .designLook: 1,
        ])
        harness.model.didDismiss()
        #expect(!harness.router.isSettingsPresented)
        #expect(harness.defaults.total == 8)
    }

    @Test func usingTheCurrentPresetWritesNothing() {
        let harness = OfferHarness()
        harness.activate()
        harness.model.appeared()
        harness.defaults.reset()

        harness.model.use()

        #expect(!harness.model.isPresented)
        #expect(harness.defaults.total == 0)
    }

    @Test func setUpOpensTheWizardOnTheSelectedPresetOnceTheSheetHasGone() {
        let harness = OfferHarness()
        harness.activate()
        harness.model.appeared()
        harness.defaults.reset()

        harness.model.selection = .wall
        harness.model.setUp()
        // Two sheets cannot be shown from one place: Settings waits for the offer to go.
        #expect(!harness.model.isPresented)
        #expect(!harness.router.isSettingsPresented)

        harness.model.didDismiss()
        #expect(harness.router.settingsPath == [.settings(.designSetup(start: .wall))])
        #expect(!harness.model.isPresented)
        #expect(harness.defaults.total == 0)

        // Dismissed again later (for another reason): nothing more opens.
        harness.router.dismissSettings()
        harness.model.didDismiss()
        #expect(!harness.router.isSettingsPresented)
    }

    @Test func setUpWithTheDefaultStartsTheWizardOnShelf() {
        let harness = OfferHarness()
        harness.activate()
        harness.model.setUp()
        harness.model.didDismiss()
        #expect(harness.router.settingsPath == [.settings(.designSetup(start: .shelf))])
    }

    @Test func notNowWritesOnlyTheFlag() {
        let harness = OfferHarness()
        harness.activate()
        harness.model.selection = .wall

        harness.model.appeared()
        harness.model.notNow()
        harness.model.didDismiss()

        #expect(!harness.model.isPresented)
        #expect(!harness.router.isSettingsPresented)
        #expect(harness.store.designChoices == DesignChoices(preset: .shelf))
        #expect(harness.defaults.counts == [.experienceOfferShown: 1])
    }

    @Test func aSheetHiddenByAGreetingComesBackAsTheSameOffer() {
        let harness = OfferHarness()
        harness.activate()
        harness.model.appeared()
        harness.defaults.reset()

        // Hidden while something else is presented, then up again: the same offer.
        harness.router.presentedGreeting = Greeting()
        harness.model.didDismiss()
        #expect(!harness.model.isPresented)
        harness.router.presentedGreeting = nil
        #expect(harness.model.isPresented)
        harness.model.appeared()
        #expect(harness.defaults.total == 0)
    }
}

// MARK: - Through the app model

@MainActor @Suite struct ExperienceOfferActivationTests {
    @Test func theFirstActivationQueuesTheOffer() async {
        let harness = LaunchHarness()
        harness.model.scenePhaseChanged(to: .active)
        await harness.launch()
        #expect(!harness.model.experienceOffer.isPresented)

        await harness.model.performActivationWork()

        #expect(harness.model.experienceOffer.isPresented)
    }

    @Test func itWaitsBehindTheLock() async {
        let harness = LaunchHarness(biometrics: AppFixture.biometrics(succeeds: false))
        harness.settings.autoLockPolicy = .instantly
        harness.model.scenePhaseChanged(to: .active)
        await harness.launch()
        #expect(harness.model.lock.isLocked)

        // The authentication fails: no follow-ups, no offer.
        await harness.model.performActivationWork()
        #expect(!harness.model.router.offer)
    }

    @Test func itIsHiddenWhileTheAppIsLockedAgain() async {
        let harness = LaunchHarness()
        harness.settings.autoLockPolicy = .min1
        harness.model.scenePhaseChanged(to: .active)
        await harness.launch()
        await harness.model.performActivationWork()
        #expect(harness.model.experienceOffer.isPresented)

        harness.model.scenePhaseChanged(to: .inactive)
        harness.clock.advance(by: 60)
        harness.model.scenePhaseChanged(to: .active)
        #expect(harness.model.lock.isLocked)
        #expect(!harness.model.experienceOffer.isPresented)

        await harness.model.performActivationWork()
        #expect(!harness.model.lock.isLocked)
        #expect(harness.model.experienceOffer.isPresented)
    }

    @Test func aLinkOnTheClipboardGoesFirst() async {
        let harness = LaunchHarness(clipboard: AppFixture.clipboard(changeCount: 3, url: AppFixture.galleryURL))
        harness.settings.detectsLinksFromClipboard = true
        harness.model.scenePhaseChanged(to: .active)
        await harness.launch()

        await harness.model.performActivationWork()

        #expect(harness.model.links.request != nil)
        #expect(!harness.model.router.offer)
    }
}

// MARK: - Support

@MainActor
private struct OfferHarness {
    let defaults: CountingDefaults
    let store: SettingsStore
    let router = AppRouter()
    let lock = AppLockModel()
    let model: ExperienceOfferModel

    init(defaults: CountingDefaults = CountingDefaults()) {
        self.defaults = defaults
        let store = SettingsStore(storage: PreferenceStorage(defaults))
        self.store = store
        let router = router
        let lock = lock
        model = withDependencies { $0.settings = store } operation: {
            ExperienceOfferModel(router: router, lock: lock)
        }
    }

    /// What `AppModel` does after an activation's follow-ups, once the launch is ready and the
    /// app unlocked.
    func activate(isOpeningLink: Bool = false) {
        model.offerIfDue(isReady: true, isUnlocked: true, isOpeningLink: isOpeningLink)
    }
}
