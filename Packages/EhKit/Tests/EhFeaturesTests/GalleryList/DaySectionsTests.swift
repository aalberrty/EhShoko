@testable import EhFeatures
import EhModels
import Foundation
import Testing

@Suite struct DaySectionsTests {
    private func calendar(_ timeZone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return calendar
    }

    /// 2024-03-09 at `hour`:`minute` UTC.
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var components = DateComponents(year: 2024, month: 3, day: day, hour: hour, minute: minute)
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    @Test func aDayStartsWhereTheDateCrossesMidnight() {
        let utc = calendar("UTC")
        let dates = [date(10, 0, 1), date(9, 23, 59), date(9, 12), date(8, 18)]

        let sections = DaySections.group(dates, calendar: utc).sections

        #expect(sections.map(\.rows) == [0..<1, 1..<3, 3..<4])
        #expect(sections.map(\.day) == [date(10, 0), date(9, 0), date(8, 0)])
        #expect(sections.map(\.id) == [0, 1, 3])
    }

    @Test func daysFollowTheCalendarsTimeZone() {
        // 15:30 and 14:30 UTC are the same day in London and two days in Tokyo (UTC+9).
        let dates = [date(9, 15, 30), date(9, 14, 30)]

        #expect(DaySections.group(dates, calendar: calendar("Europe/London")).sections.count == 1)
        let tokyo = DaySections.group(dates, calendar: calendar("Asia/Tokyo")).sections
        #expect(tokyo.map(\.rows) == [0..<1, 1..<2])
        // 20:00 and 23:00 on the 8th in Los Angeles are the 9th in UTC.
        let losAngeles = DaySections.group([date(9, 7), date(9, 4)], calendar: calendar("America/Los_Angeles"))
        #expect(losAngeles.sections.count == 1)
    }

    @Test func anEmptyListHasNoSections() {
        let sections = DaySections.group([Date](), calendar: calendar("UTC"))
        #expect(sections.sections.isEmpty)
        #expect(sections.count == 0)
    }

    @Test func appendingExtendsTheLastDayOrStartsANewOne() {
        let utc = calendar("UTC")
        var sections = DaySections.group([date(9, 20), date(9, 10)], calendar: utc)

        sections.append([date(9, 2), date(8, 22)], calendar: utc)

        #expect(sections.sections.map(\.rows) == [0..<3, 3..<4])
        #expect(sections.count == 4)
        #expect(sections == DaySections.group([date(9, 20), date(9, 10), date(9, 2), date(8, 22)], calendar: utc))
    }

    // MARK: Following a list

    private func entries(_ days: [(String, Date)]) -> [GalleryEntry] {
        days.map { gid, date in
            GalleryEntry(gallery: Gallery(
                gid: gid, token: "t", title: "Title", rating: 4, tags: [], category: .doujinshi,
                pageCount: 1, postedDate: date, coverURL: nil, galleryURL: nil, lastOpenDate: date
            ))
        }
    }

    @Test func aGrownListIsExtendedAndAReplacedOneRegrouped() {
        let utc = calendar("UTC")
        let firstPage = entries([("1", date(9, 20)), ("2", date(9, 10))])
        var sections = DaySections()
        sections.update(with: firstPage, by: .posted, calendar: utc)
        #expect(sections.sections.map(\.rows) == [0..<2])

        // A page appended.
        let twoPages = firstPage + entries([("3", date(9, 1)), ("4", date(8, 23))])
        sections.update(with: twoPages, by: .posted, calendar: utc)
        #expect(sections.sections.map(\.rows) == [0..<3, 3..<4])

        // The list replaced by a refresh that starts with a new gallery.
        let refreshed = entries([("5", date(10, 1))]) + twoPages
        sections.update(with: refreshed, by: .posted, calendar: utc)
        #expect(sections.sections.map(\.rows) == [0..<1, 1..<4, 4..<5])

        // The same list in another time zone.
        sections.update(with: refreshed, by: .posted, calendar: calendar("Asia/Tokyo"))
        #expect(sections.sections.map(\.rows) == [0..<2, 2..<5])

        sections.update(with: [], by: .posted, calendar: utc)
        #expect(sections.sections.isEmpty)
    }

    @Test func historyIsGroupedByTheDayItWasOpened() {
        let opened = Gallery(
            gid: "1", token: "t", title: "Title", rating: 4, tags: [], category: .doujinshi, pageCount: 1,
            postedDate: date(1, 12), coverURL: nil, galleryURL: nil, lastOpenDate: date(9, 12)
        )
        var sections = DaySections()
        sections.update(with: [GalleryEntry(gallery: opened)], by: .opened, calendar: calendar("UTC"))
        #expect(sections.sections.map(\.day) == [date(9, 0)])
        sections.update(with: [GalleryEntry(gallery: opened)], by: .posted, calendar: calendar("UTC"))
        #expect(sections.sections.map(\.day) == [date(1, 0)])
    }
}
