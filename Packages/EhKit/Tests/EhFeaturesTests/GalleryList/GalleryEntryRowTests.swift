@testable import EhFeatures
import EhModels
import EhTestSupport
import Foundation
import Testing

/// What an entry carries for the three row forms besides its title, worked out when its page
/// is mapped: credit, uploader, rating, tags and ages.
@Suite struct GalleryEntryRowTests {
    static let now = Date(timeIntervalSince1970: 2_000_000_000)
    static let posix = GalleryEntry.Mapping(now: now, locale: Locale(identifier: "en_US_POSIX"))

    // MARK: Credit and uploader

    @Test(arguments: [
        ("(C102) [Circle (Artist)] Title", "Circle · Artist"),
        ("[Circle (Artist One, Artist Two)] Title [English]", "Circle · Artist One, Artist Two"),
        ("[Someone] Title", "Someone"),
        ("[Artist、Other] Title", "Artist, Other"),
        ("(C97) [Circle ()] Title", "Circle"),
        ("[Name (name)] Title", "Name"),
        ("[某汉化组] (C97) [Circle (Artist)] Title", "Circle · Artist"),
    ])
    func theCreditIsTheCircleAndTheArtists(title: String, credit: String) {
        #expect(GalleryEntry(gallery: .row(title: title)).credit == credit)
    }

    @Test func aTitleThatNamesNoOneHasNoCredit() {
        for title in ["Title", "(C102) Title", "[Pixiv] name (123)", "Title [English] | Other"] {
            #expect(GalleryEntry(gallery: .row(title: title, uploader: "uploader")).credit == nil, "\(title)")
        }
    }

    @Test func theUploaderIsNilWhenThePageGaveNone() {
        #expect(GalleryEntry(gallery: .row(uploader: "  someone ")).uploader == "someone")
        #expect(GalleryEntry(gallery: .row(uploader: "")).uploader == nil)
        #expect(GalleryEntry(gallery: .row(uploader: nil)).uploader == nil)
    }

    // MARK: Rating

    @Test(arguments: [
        (Float(0), 0, "0.0"), (0.5, 1, "0.5"), (2, 4, "2.0"), (4.5, 9, "4.5"), (4.25, 9, "4.25"),
        (4.24, 8, "4.24"), (4.7, 9, "4.7"), (4.72, 9, "4.72"), (4.05, 8, "4.05"), (4.75, 10, "4.75"),
        (5, 10, "5.0"), (7, 10, "5.0"), (-1, 0, "0.0"), (.nan, 0, "0.0"), (.infinity, 0, "0.0"),
    ] as [(Float, Int, String)])
    func theRatingIsHalfStarsAndText(rating: Float, halfStars: Int, text: String) {
        let entry = GalleryEntry(gallery: .row(rating: rating), favorite: nil, readingProgress: nil, mapping: Self.posix)
        #expect(entry.halfStars == halfStars)
        #expect(entry.ratingText == text)
    }

    @Test func theRatingTextUsesTheUsersDecimalSeparator() {
        #expect(GalleryEntry.ratingText(4.5, decimalSeparator: ",") == "4,5")
        #expect(GalleryEntry.Mapping(now: Self.now, locale: Locale(identifier: "de_DE")).decimalSeparator == ",")
        #expect(GalleryEntry.Mapping(now: Self.now, locale: Locale(identifier: "ja_JP")).decimalSeparator == ".")
    }

    // MARK: Tags

    @Test func tagsAreFlattenedInThePagesOrder() {
        let gallery = Gallery.row(tags: [
            .group("female", ["big breasts", "glasses"]),
            .group("male", ["sole male"], watched: RGBColor(red: 1, green: 0, blue: 0)),
            .group("language", ["english"]),
            .group("someday", ["new namespace"]),
        ])
        let tags = GalleryEntry(gallery: gallery).tags

        #expect(tags.map(\.text) == ["big breasts", "glasses", "sole male", "english", "new namespace"])
        #expect(tags.map(\.id) == ["femalebig breasts", "femaleglasses", "malesole male", "languageenglish", "somedaynew namespace"])
        #expect(tags.map(\.namespace) == [.female, .female, .male, .language, nil])
        #expect(tags.map(\.watchedColor) == [nil, nil, RGBColor(red: 1, green: 0, blue: 0), nil, nil])
    }

    @Test func tagsStopAtWhatARowCanShow() {
        let gallery = Gallery.row(tags: [
            .group("female", (1...5).map { "f\($0)" }),
            .group("male", (1...5).map { "m\($0)" }),
            .group("other", ["o1"]),
        ])
        let tags = GalleryEntry(gallery: gallery).tags
        #expect(GalleryEntry.rowTagLimit == 8)
        #expect(tags.map(\.text) == ["f1", "f2", "f3", "f4", "f5", "m1", "m2", "m3"])
    }

    @Test func aRepeatedTagIsKeptOnce() {
        let gallery = Gallery.row(tags: [.group("female", ["glasses", "glasses"]), .group("female", ["glasses", "x"])])
        #expect(GalleryEntry(gallery: gallery).tags.map(\.id) == ["femaleglasses", "femalex"])
        #expect(GalleryEntry(gallery: .row(tags: [])).tags.isEmpty)
    }

    // MARK: Ages

    @Test(arguments: [
        (0, 1, .minute), (59, 1, .minute), (119, 1, .minute), (120, 2, .minute), (3_599, 59, .minute),
        (3_600, 1, .hour), (86_399, 23, .hour),
        (86_400, 1, .day), (7 * 86_400 - 1, 6, .day),
        (7 * 86_400, 1, .week), (30 * 86_400 - 1, 4, .week),
        (30 * 86_400, 1, .month), (364 * 86_400, 11, .month),
        (365 * 86_400, 1, .year), (800 * 86_400, 2, .year),
        (-500, 1, .minute),
    ] as [(TimeInterval, Int, GalleryEntry.Age.Unit)])
    func anAgeIsItsLargestWholeUnit(seconds: TimeInterval, count: Int, unit: GalleryEntry.Age.Unit) {
        let age = GalleryEntry.Age(from: Self.now.addingTimeInterval(-seconds), to: Self.now)
        #expect(age == GalleryEntry.Age(count: count, unit: unit))
    }

    @Test func anAgeGivesTheSystemFormattersOneUnit() {
        #expect(GalleryEntry.Age(count: 5, unit: .minute).dateComponents == DateComponents(minute: 5))
        #expect(GalleryEntry.Age(count: 3, unit: .hour).dateComponents == DateComponents(hour: 3))
        #expect(GalleryEntry.Age(count: 2, unit: .day).dateComponents == DateComponents(day: 2))
        #expect(GalleryEntry.Age(count: 2, unit: .week).dateComponents == DateComponents(weekOfMonth: 2))
        #expect(GalleryEntry.Age(count: 4, unit: .month).dateComponents == DateComponents(month: 4))
        #expect(GalleryEntry.Age(count: 6, unit: .year).dateComponents == DateComponents(year: 6))
    }

    @Test func anEntryCountsItsAgesToWhenItWasMapped() {
        let gallery = Gallery.row(posted: Self.now.addingTimeInterval(-3 * 3_600), opened: Self.now.addingTimeInterval(-300))
        let favorite = FavoriteMark(folder: 2, favoritedDate: Self.now.addingTimeInterval(-2 * 86_400))

        let entry = GalleryEntry(gallery: gallery, favorite: favorite, now: Self.now)
        #expect(entry.postedAge == GalleryEntry.Age(count: 3, unit: .hour))
        #expect(entry.openedAge == GalleryEntry.Age(count: 5, unit: .minute))
        #expect(entry.addedAge == GalleryEntry.Age(count: 2, unit: .day))

        let plain = GalleryEntry(gallery: .row(), favorite: FavoriteMark(folder: 2), now: Self.now)
        #expect(plain.openedAge == nil)
        #expect(plain.addedAge == nil)
        #expect(GalleryEntry(gallery: .row(), now: Self.now).addedAge == nil)
    }

    @Test func entriesMappedAtDifferentMomentsDifferByTheirAges() {
        let gallery = Gallery.row(posted: Self.now.addingTimeInterval(-600))
        let first = GalleryEntry(gallery: gallery, now: Self.now)
        #expect(first == GalleryEntry(gallery: gallery, now: Self.now.addingTimeInterval(30)))
        #expect(first != GalleryEntry(gallery: gallery, now: Self.now.addingTimeInterval(3_600)))
    }

    // MARK: Mapping

    @Test func aReusedEntryCountsItsAgesAgain() {
        let gallery = Gallery.row(title: "[Circle (Artist)] Title", posted: Self.now.addingTimeInterval(-600))
        let previous = GalleryEntry.entries(for: [gallery], now: Self.now)
        let later = Self.now.addingTimeInterval(2 * 3_600)
        let added = FavoriteMark(folder: 1, favoritedDate: Self.now)

        let entries = GalleryEntry.entries(for: [gallery], marks: [gallery.gid: added], reusing: previous, now: later)

        #expect(entries[0].postedAge == GalleryEntry.Age(count: 2, unit: .hour))
        #expect(entries[0].addedAge == GalleryEntry.Age(count: 2, unit: .hour))
        #expect(entries[0].favorite == added)
        #expect(entries[0].credit == "Circle · Artist")
        #expect(GalleryEntry.entries(for: [gallery], reusing: previous, now: Self.now) == previous)
    }

    @Test func copyingProgressKeepsWhatTheRowShows() throws {
        let gallery = Gallery.row(
            title: "[Circle (Artist)] Title", tags: [.group("female", ["glasses"])], opened: Self.now
        )
        let entry = GalleryEntry(gallery: gallery, favorite: FavoriteMark(folder: 3, favoritedDate: Self.now), now: Self.now)

        let copy = try #require(GalleryListPaging.withReadingProgress([entry], [entry.id: 4]).first)

        #expect(copy.readingProgress == 4)
        #expect(copy.credit == entry.credit)
        #expect(copy.uploader == entry.uploader)
        #expect(copy.tags == entry.tags)
        #expect(copy.ratingText == entry.ratingText)
        #expect(copy.halfStars == entry.halfStars)
        #expect(copy.postedAge == entry.postedAge)
        #expect(copy.addedAge == entry.addedAge)
        #expect(copy.openedAge == entry.openedAge)
    }

    /// Mapping the fixtures' pages gives every entry what mapping its gallery alone gives.
    @Test func aPageMapsEachGalleryAsAloneWould() throws {
        let galleries = try GalleryEntryTests.fixtureGalleries()
        let entries = GalleryEntry.entries(for: galleries, now: Self.now)

        #expect(entries.count == galleries.count)
        for (entry, gallery) in zip(entries, galleries) {
            let alone = GalleryEntry(gallery: gallery, now: Self.now)
            #expect(entry == alone)
            #expect(entry.credit == alone.credit)
            #expect(entry.tags == alone.tags)
            #expect(entry.ratingText == alone.ratingText)
            #expect(entry.tags.count <= GalleryEntry.rowTagLimit)
            #expect(Set(entry.tags.map(\.id)).count == entry.tags.count)
        }
        #expect(entries.contains { !$0.tags.isEmpty })
        #expect(entries.contains { $0.credit != nil })
        #expect(entries.contains { $0.uploader != nil })
    }

    // MARK: Through the lists

    @Test func aListsEntriesCarryTheirRowValues() async throws {
        let env = try ListTestEnvironment()
        env.transport.on(.any, reply: .fixture(ListFixture.frontpage))
        let model = env.make { GalleryListModel(source: .frontpage) }

        await model.loadIfNeeded()

        let entry = try #require(model.entries.first { $0.gallery.title == "[ROM宅 (ROM)] せめぱん3 (ドラゴンボールGT) [DL版]" })
        #expect(entry.credit == "ROM宅 · ROM")
        #expect(entry.halfStars == Int((Double(entry.gallery.rating) * 2).rounded()))
        #expect(!model.entries.isEmpty)
        #expect(model.entries.allSatisfy { $0.addedAge == nil && $0.openedAge == nil })
        #expect(model.entries.contains { !$0.tags.isEmpty })
    }

    @Test func favouritesEntriesCarryWhenTheyWereAdded() async throws {
        let env = try ListTestEnvironment()
        env.transport.on(.any, reply: .fixture("Parser/List/FavoritesMinimalList.html"))
        let model = env.make { GalleryListModel(source: .favorites(category: 2, keyword: "", sortOrder: nil)) }

        await model.loadIfNeeded()

        #expect(!model.entries.isEmpty)
        #expect(model.entries.allSatisfy { $0.addedAge != nil })
    }

    @Test func historyEntriesCarryWhenTheyWereOpened() async throws {
        let env = try ListTestEnvironment()
        try await env.database.recordOpened(.stub("1"), at: Date.now.addingTimeInterval(-2 * 3_600))
        let model = env.make { HistoryModel() }

        await model.refresh()

        #expect(model.entries.map(\.openedAge) == [GalleryEntry.Age(count: 2, unit: .hour)])
    }
}

private extension Gallery {
    static func row(
        title: String = "[Circle (Artist)] Title", rating: Float = 4.5, tags: [GalleryTag] = [],
        uploader: String? = "uploader", posted: Date = GalleryEntryRowTests.now, opened: Date? = nil
    ) -> Gallery {
        Gallery(
            gid: "1", token: "t", title: title, rating: rating, tags: tags, category: .manga,
            uploader: uploader, pageCount: 48, postedDate: posted, coverURL: nil, galleryURL: nil,
            lastOpenDate: opened
        )
    }
}

private extension GalleryTag {
    static func group(_ namespace: String, _ texts: [String], watched: RGBColor? = nil) -> GalleryTag {
        GalleryTag(rawNamespace: namespace, contents: texts.map {
            GalleryTag.Content(
                rawNamespace: namespace, text: $0, isVotedUp: false, isVotedDown: false, backgroundColor: watched
            )
        })
    }
}
