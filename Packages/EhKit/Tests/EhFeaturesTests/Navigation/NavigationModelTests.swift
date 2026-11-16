import EhFeatures
import EhModels
import Foundation
import Testing

/// The navigation model of `Design/designs/README.md` section 6 (tests named in 10.8).
@MainActor
@Suite struct NavigationModelTests {
    private func makeGallery(gid: String = "1") -> Gallery {
        Gallery(
            gid: gid, token: "t", title: "Title", rating: 4, tags: [], category: .doujinshi,
            uploader: nil, pageCount: 1, postedDate: Date(timeIntervalSince1970: 0),
            coverURL: nil, galleryURL: nil
        )
    }

    // MARK: go(to:start:)

    @Test func wallReplacesTheRootListInPlace() {
        let router = AppRouter()
        router.home.push(.detail(makeGallery()))

        router.go(to: .list(.watched), start: .wall)
        #expect(router.place == .list(.watched))
        #expect(router.home.isAtRoot)

        router.go(to: .list(.favorites), start: .wall)
        #expect(router.place == .list(.favorites))
        #expect(router.home.isAtRoot)
    }

    @Test func wallStoresFrontPageAsTheStart() {
        let router = AppRouter()
        router.go(to: .list(.popular), start: .wall)

        router.go(to: .list(.frontpage), start: .wall)
        #expect(router.place == .start)

        router.go(to: .list(.history), start: .wall)
        router.go(to: .start, start: .wall)
        #expect(router.place == .start)
    }

    @Test func theRootsPlaceIsNotChangedByAListPushedOverIt() {
        let router = AppRouter()
        router.go(to: .list(.watched), start: .wall)
        #expect(router.rootPlace == .list(.watched))

        // A list pushed at the bottom of the stack is the bar's place, not the root's.
        router.home.push(.galleryList(.popular))
        #expect(router.place == .list(.popular))
        #expect(router.rootPlace == .list(.watched))

        router.go(to: .list(.history), start: .shelf)
        #expect(router.rootPlace == .start)

        router.go(to: .list(.toplists), start: .wall)
        router.resetNavigation()
        #expect(router.rootPlace == .start)
    }

    @Test(arguments: [DesignStyle.shelf, .ledger])
    func shelfAndLedgerShowTheListOverTheirRoot(start: DesignStyle) {
        let router = AppRouter()

        router.go(to: .list(.popular), start: start)
        #expect(router.home.path == [.galleryList(.popular)])
        #expect(router.place == .list(.popular))

        // On a list, deeper screens and all, the menu switches the list in place.
        router.home.push(.detail(makeGallery()))
        router.home.push(.search(keyword: "a"))
        router.go(to: .list(.favorites), start: start)
        #expect(router.home.path == [.galleryList(.favorites)])
        #expect(router.place == .list(.favorites))

        router.go(to: .start, start: start)
        #expect(router.home.isAtRoot)
        #expect(router.place == .start)
    }

    @Test(arguments: [DesignStyle.shelf, .ledger])
    func goingBackFromAListMakesTheStartThePlace(start: DesignStyle) {
        let router = AppRouter()
        router.go(to: .list(.toplists), start: start)

        router.home.pop()

        #expect(router.place == .start)
    }

    @Test func aListPushedFromLedgersIndexIsThePlace() {
        let router = AppRouter()

        router.home.push(.galleryList(.watched))
        #expect(router.place == .list(.watched))
        router.home.push(.detail(makeGallery()))
        #expect(router.place == .list(.watched))

        router.home.popToRoot()
        router.home.push(.favoritesFolder(3))
        #expect(router.place == .list(.favorites))
        router.home.popToRoot()
        router.home.push(.favoritesFolder(3, library: FavoritesModel()))
        #expect(router.place == .list(.favorites))

        // A quick search from the Index is a search, not a place.
        router.home.popToRoot()
        router.home.push(.search(keyword: "a"))
        #expect(router.place == .start)
    }

    @Test(arguments: DesignStyle.allCases)
    func goingSomewhereClosesTheSidePane(start: DesignStyle) {
        let router = AppRouter()
        router.home.open(makeGallery(), inSidePane: true)

        router.go(to: .list(.history), start: start)

        #expect(router.home.sideGallery == nil)
    }

    // MARK: resetNavigation

    @Test func resetNavigationReturnsEverythingToTheFirstScreen() {
        let router = AppRouter()
        let gallery = makeGallery()
        router.go(to: .list(.popular), start: .wall)
        for tab in AppTab.allCases {
            router.stack(for: tab).push(.detail(gallery))
            router.stack(for: tab).open(gallery, inSidePane: true)
        }
        router.select(.library)
        router.presentSettings([.settings(.design)])
        router.present(gallery)

        router.resetNavigation()

        for tab in AppTab.allCases {
            #expect(router.stack(for: tab).isAtRoot)
            #expect(router.stack(for: tab).sideGallery == nil)
        }
        #expect(router.selectedTab == .home)
        #expect(router.place == .start)
        // The sheets stay up.
        #expect(router.settingsPath == [.settings(.design)])
        #expect(router.presentedGallery == gallery)
    }

    @Test func resetNavigationKeepsTheReselectionCounters() {
        let router = AppRouter()
        router.select(.home)

        router.resetNavigation()

        #expect(router.rootReselectionCount(for: .home) == 1)
    }

    // MARK: The side pane

    @Test func openingPushesOrUsesTheSidePane() {
        let stack = StackRouter()
        let gallery = makeGallery()

        stack.open(gallery, intent: .read(page: 3), inSidePane: false)
        #expect(stack.path == [.detail(gallery, intent: .read(page: 3))])
        #expect(stack.sideGallery == nil)

        stack.popToRoot()
        stack.push(.galleryList(.popular))
        stack.open(gallery, intent: .read(page: 3), inSidePane: true)
        #expect(stack.path == [.galleryList(.popular)])
        #expect(stack.sideGallery == gallery)
        #expect(stack.sideIntent == .read(page: 3))
    }

    @Test func anotherGalleryInTheSidePaneStartsOnAFreshPaneStack() {
        let stack = StackRouter()
        let first = makeGallery(gid: "1")
        let second = makeGallery(gid: "2")
        stack.open(first, intent: .read(page: 2), inSidePane: true)
        let pane = stack.side
        pane.push(.search(keyword: "artist:a"))

        stack.open(second, inSidePane: true)

        #expect(stack.side === pane)
        #expect(pane.isAtRoot)
        #expect(stack.sideGallery == second)
        #expect(stack.sideIntent == nil)
    }

    @Test func closingTheSidePaneEmptiesIt() {
        let stack = StackRouter()
        stack.open(makeGallery(), intent: .read(page: 2), inSidePane: true)
        stack.side.push(.search(keyword: "a"))

        stack.closeSidePane()

        #expect(stack.sideGallery == nil)
        #expect(stack.sideIntent == nil)
        #expect(stack.side.isAtRoot)
    }

    @Test func theSidePaneDoesNotChangeTheBrowseBar() {
        let stack = StackRouter()
        stack.open(makeGallery(), inSidePane: true)
        #expect(!stack.hidesBrowseChrome)
    }

    @Test func aPaneThatLosesItsPlaceMovesOntoTheStackWithItsScreens() {
        let stack = StackRouter()
        let gallery = makeGallery()
        stack.push(.galleryList(.watched))
        stack.open(gallery, intent: .read(page: 3), inSidePane: true)
        stack.side.push(.search(keyword: "a"))
        stack.side.push(.search(keyword: "b"))

        stack.moveSidePaneOntoStack()

        #expect(stack.path == [
            .galleryList(.watched), .detail(gallery, intent: .read(page: 3)),
            .search(keyword: "a"), .search(keyword: "b"),
        ])
        #expect(stack.sideGallery == nil)
        #expect(stack.sideIntent == nil)
        #expect(stack.side.isAtRoot)
        #expect(stack.hidesBrowseChrome == false)
    }

    @Test func movingAnEmptyPaneOntoTheStackChangesNothing() {
        let stack = StackRouter()
        stack.push(.galleryList(.popular))

        stack.moveSidePaneOntoStack()

        #expect(stack.path == [.galleryList(.popular)])
        #expect(stack.sideGallery == nil)
    }

    @Test func aGalleryMovedOntoTheStackHidesTheBar() {
        let stack = StackRouter()
        stack.open(makeGallery(), inSidePane: true)

        stack.moveSidePaneOntoStack()

        #expect(stack.hidesBrowseChrome)
    }

    // MARK: hidesBrowseChrome

    @Test func aGalleryAndTheScreensPushedFromItHideTheBar() {
        let gallery = makeGallery()
        let child = DetailChildRoute(parent: GalleryDetailModel(gallery: gallery), destination: .galleryInfos)

        #expect(Route.detail(gallery).hidesBrowseChrome)
        #expect(Route.detail(gallery, intent: .read(page: 2)).hidesBrowseChrome)
        #expect(Route.detailChild(child).hidesBrowseChrome)
        for kind in GalleryListKind.allCases {
            #expect(!Route.galleryList(kind).hidesBrowseChrome)
        }
        for scope in SearchScope.allCases {
            #expect(!Route.listSearch(scope, keyword: "a").hidesBrowseChrome)
        }
        #expect(!Route.favoritesFolder(0).hidesBrowseChrome)
        #expect(!Route.search(keyword: "a").hidesBrowseChrome)
        #expect(!Route.typedSearch(keyword: "a").hidesBrowseChrome)
        #expect(!Route.settings(.general).hidesBrowseChrome)
    }

    /// A folder pushed from a library is another screen than the same folder of another
    /// library, or of none.
    @Test func aFoldersRouteIsTheFolderAndTheLibrarysModel() {
        let library = FavoritesModel()
        #expect(Route.favoritesFolder(3) == .favoritesFolder(FavoritesFolderRoute(folder: 3)))
        #expect(Route.favoritesFolder(3, library: library) == .favoritesFolder(3, library: library))
        #expect(Route.favoritesFolder(3, library: library) != .favoritesFolder(3))
        #expect(Route.favoritesFolder(3, library: library) != .favoritesFolder(3, library: FavoritesModel()))
        #expect(Route.favoritesFolder(3, library: library) != .favoritesFolder(4, library: library))
        #expect(Set<Route>([.favoritesFolder(3, library: library), .favoritesFolder(3, library: library)]).count == 1)
        #expect(!Route.favoritesFolder(-1, library: library).hidesBrowseChrome)
    }

    @Test func theTopScreenAloneDecidesTheBarAtAnyDepth() {
        let first = makeGallery(gid: "1")
        let second = makeGallery(gid: "2")
        let infos = DetailChildRoute(parent: GalleryDetailModel(gallery: second), destination: .galleryInfos)
        let stack = StackRouter()
        #expect(!stack.hidesBrowseChrome)

        let pushes: [(Route, Bool)] = [
            (.galleryList(.frontpage), false),
            (.detail(first), true),
            // A tag, the uploader or similar galleries: a search above the gallery shows the bar.
            (.search(keyword: "artist:a"), false),
            (.detail(second), true),
            (.detailChild(infos), true),
            (.listSearch(.favorites, keyword: "b"), false)
        ]
        var expected: [Bool] = [false]
        for (route, hides) in pushes {
            stack.push(route)
            expected.append(hides)
            #expect(stack.hidesBrowseChrome == hides)
        }
        for hides in expected.dropLast().reversed() {
            stack.pop()
            #expect(stack.hidesBrowseChrome == hides)
        }
        #expect(stack.isAtRoot)
    }

    @Test func theSelectedStackDecides() {
        let router = AppRouter()
        router.watched.push(.detail(makeGallery()))
        #expect(!router.selectedStack.hidesBrowseChrome)

        router.select(.watched)

        #expect(router.selectedStack === router.watched)
        #expect(router.selectedStack.hidesBrowseChrome)
    }

    // MARK: Tabs

    @Test func everyTabHasItsOwnStack() {
        let router = AppRouter()
        let stacks = AppTab.allCases.map(router.stack(for:))
        #expect(Set(stacks.map(ObjectIdentifier.init)).count == AppTab.allCases.count)
        #expect(!stacks.contains { $0 === router.settings || $0 === router.presented })
    }

    @Test(arguments: AppTab.allCases)
    func reselectingATabPopsThenBumpsItsCounter(tab: AppTab) {
        let router = AppRouter()
        // Home starts selected; come to it from another tab.
        if tab == .home { router.select(.search) }
        router.select(tab)
        router.stack(for: tab).push(.galleryList(.popular))
        router.stack(for: tab).push(.detail(makeGallery()))

        router.select(tab)
        #expect(router.stack(for: tab).isAtRoot)
        #expect(router.rootReselectionCount(for: tab) == 0)

        router.select(tab)
        #expect(router.rootReselectionCount(for: tab) == 1)
        for other in AppTab.allCases where other != tab {
            #expect(router.rootReselectionCount(for: other) == 0)
        }
    }

    // MARK: Settings

    @Test func settingsOpensClosedAtTheRoot() {
        let router = AppRouter()
        #expect(router.settingsPath == nil)

        router.presentSettings()
        #expect(router.settingsPath == [])
        #expect(router.isSettingsPresented)

        router.settings.push(.settings(.general))
        #expect(router.settingsPath == [.settings(.general)])

        router.dismissSettings()
        #expect(router.settingsPath == nil)

        router.presentSettings()
        #expect(router.settingsPath == [])
    }

    @Test func settingsOpensAtAGivenPath() {
        let router = AppRouter()
        router.presentSettings([.settings(.account), .settings(.login)])

        #expect(router.settingsPath == [.settings(.account), .settings(.login)])
        #expect(router.settings.path == [.settings(.account), .settings(.login)])
        // Settings is not a tab: nothing else moves.
        #expect(router.selectedTab == .home)
    }

    @Test func settingsRoutesForExperience() {
        #expect(Route.settings(.designPart(.list)) != .settings(.designPart(.gallery)))
        #expect(Set(DesignPart.allCases.map { SettingsRoute.designPart($0) }).count == DesignPart.allCases.count)
        #expect(SettingsRoute.design != .designSetup())
        #expect(SettingsRoute.designSetup() == .designSetup(start: nil))
        #expect(SettingsRoute.designSetup(start: .wall) != .designSetup(start: .ledger))
    }

    // MARK: Presented over everything

    @Test func theOfferWaitsForTheLockTheGreetingAndTheGallerySheet() {
        let router = AppRouter()
        #expect(!router.showsOffer(isUnlocked: true))

        router.offer = true
        #expect(router.showsOffer(isUnlocked: true))
        #expect(!router.showsOffer(isUnlocked: false))

        router.presentedGreeting = Greeting()
        #expect(!router.showsOffer(isUnlocked: true))
        router.presentedGreeting = nil

        router.present(makeGallery())
        #expect(!router.showsOffer(isUnlocked: true))
        router.dismissPresentedGallery()
        #expect(router.showsOffer(isUnlocked: true))

        router.offer = false
        #expect(!router.showsOffer(isUnlocked: true))
    }

    /// The offer is presented from the same place as the Settings sheet and the reader opened
    /// from Continue, which can show one at a time.
    @Test func theOfferWaitsForSettingsAndTheReader() {
        let router = AppRouter()
        router.offer = true

        router.presentSettings([.settings(.design)])
        #expect(!router.showsOffer(isUnlocked: true))
        router.dismissSettings()
        #expect(router.showsOffer(isUnlocked: true))

        router.reading = ReadingRequest(gallery: makeGallery(), page: 1)
        #expect(!router.showsOffer(isUnlocked: true))
        router.reading = nil
        #expect(router.showsOffer(isUnlocked: true))
    }

    @Test func aReadingRequestIsIdentifiedByItsGallery() {
        let router = AppRouter()
        let gallery = makeGallery(gid: "7")

        router.reading = ReadingRequest(gallery: gallery, page: 12)

        #expect(router.reading?.id == "7")
        #expect(router.reading?.page == 12)
        #expect(ReadingRequest(gallery: gallery).page == nil)
    }
}
