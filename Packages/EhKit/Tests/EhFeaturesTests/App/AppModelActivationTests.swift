import ConcurrencyExtras
import Dependencies
@testable import EhCore
@testable import EhFeatures
import EhModels
import EhNetworking
import Foundation
import Testing

@MainActor @Suite struct AppModelActivationTests {
    private static let link = URL(string: "https://e-hentai.org/g/1/abc/")!

    /// A launched model whose scene is active.
    private func launchedHarness(
        policy: AutoLockPolicy = .never, biometrics: BiometricsClient = AppFixture.biometrics(),
        clipboard: ClipboardClient = AppFixture.clipboard(changeCount: 3, url: link)
    ) async -> LaunchHarness {
        let harness = LaunchHarness(biometrics: biometrics, clipboard: clipboard)
        harness.settings.autoLockPolicy = policy
        harness.settings.detectsLinksFromClipboard = true
        harness.model.scenePhaseChanged(to: .active)
        await harness.launch()
        return harness
    }

    @Test func inactiveBlursAndActiveRequestsTheFollowUps() async throws {
        let harness = await launchedHarness()
        let launchRequest = try #require(harness.model.activationRequest)

        harness.model.scenePhaseChanged(to: .inactive)
        #expect(harness.model.lock.blurRadius == harness.settings.backgroundBlurRadius)

        harness.model.scenePhaseChanged(to: .active)
        #expect(harness.model.lock.blurRadius == 0)
        #expect(harness.model.activationRequest?.work == .followUps)
        #expect(harness.model.activationRequest != launchRequest)
    }

    @Test func followUpsCheckTheClipboard() async {
        let harness = await launchedHarness()

        await harness.model.performActivationWork()

        #expect(harness.model.links.request?.url == Self.link)
    }

    @Test func expiredLockAuthenticatesThenRunsTheFollowUps() async {
        let harness = await launchedHarness(policy: .min1)
        harness.model.scenePhaseChanged(to: .inactive)
        harness.clock.advance(by: 60)
        harness.model.scenePhaseChanged(to: .active)
        #expect(harness.model.lock.isLocked)
        #expect(harness.model.activationRequest?.work == .authenticate)

        await harness.model.performActivationWork()

        #expect(!harness.model.lock.isLocked)
        #expect(harness.model.links.request?.url == Self.link)
    }

    @Test func failedAuthenticationSkipsTheFollowUps() async {
        let clipboard = ClipboardClient(
            changeCount: { Issue.record("Clipboard read while locked"); return 0 },
            url: { nil }, copyText: { _ in }, copyImage: { _ in }
        )
        let harness = await launchedHarness(
            policy: .instantly, biometrics: AppFixture.biometrics(succeeds: false), clipboard: clipboard
        )
        #expect(harness.model.activationRequest?.work == .authenticate)

        await harness.model.performActivationWork()

        #expect(harness.model.lock.isLocked)
        #expect(harness.model.links.request == nil)
    }

    @Test func lockControlRequestsAuthenticationOnlyWhenLocked() async throws {
        let harness = await launchedHarness()
        let request = harness.model.activationRequest

        harness.model.unlock()
        #expect(harness.model.activationRequest == request)

        harness.settings.autoLockPolicy = .instantly
        harness.model.scenePhaseChanged(to: .inactive)
        harness.model.scenePhaseChanged(to: .active)
        let lockRequest = try #require(harness.model.activationRequest)

        harness.model.unlock()
        #expect(harness.model.activationRequest?.work == .authenticate)
        #expect(harness.model.activationRequest != lockRequest)
    }

    // MARK: Tabs

    @Test func reselectingHomeOrSearchAlwaysGivesFeedback() {
        let harness = LaunchHarness()
        let model = harness.model!

        model.selectTab(.home)
        #expect(model.tabReselectionFeedback == 1)
        #expect(model.router.rootReselectionCount(for: .home) == 1)

        model.selectTab(.search)
        #expect(model.tabReselectionFeedback == 1)
        model.selectTab(.search)
        #expect(model.tabReselectionFeedback == 2)
    }

    @Test func reselectingTopAlwaysGivesFeedback() {
        let harness = LaunchHarness()
        let model = harness.model!
        model.selectTab(.top)

        model.selectTab(.top)

        #expect(model.tabReselectionFeedback == 1)
        #expect(model.router.rootReselectionCount(for: .top) == 1)
    }

    @Test(arguments: [AppTab.watched, .library])
    func reselectingASignedInTabGivesFeedbackWhenItActs(tab: AppTab) {
        let harness = LaunchHarness()
        let model = harness.model!
        model.selectTab(tab)

        // At the root and logged out: nothing reloads.
        model.selectTab(tab)
        #expect(model.tabReselectionFeedback == 0)

        model.router.stack(for: tab).push(.galleryList(.popular))
        model.selectTab(tab)
        #expect(model.tabReselectionFeedback == 1)
        #expect(model.router.stack(for: tab).isAtRoot)
    }

    @Test(arguments: [AppTab.watched, .library])
    func reselectingASignedInTabWhileLoggedInGivesFeedback(tab: AppTab) {
        let model = withDependencies {
            $0.cookieStore = AppFixture.loggedInCookies()
        } operation: {
            AppModel()
        }
        model.selectTab(tab)

        model.selectTab(tab)

        #expect(model.tabReselectionFeedback == 1)
    }
}
