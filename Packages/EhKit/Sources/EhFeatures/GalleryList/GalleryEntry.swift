import EhModels
import Foundation

/// One row of a gallery list, as every list design draws it: the gallery and everything a row
/// shows that is derived from it, worked out once when its page is mapped, off the main actor,
/// so that a row's body formats nothing.
///
/// Words stay in the app: an age is a count and a unit, which the app turns into "3 h" or
/// "added 2 d ago"; the category's name and "48 p" are the app's too. Everything else a row
/// shows is here as a value it can draw as it is.
public nonisolated struct GalleryEntry: Identifiable, Equatable, Sendable {
    public let gallery: Gallery
    public let title: ParsedTitle
    /// "EN", "ZH", …: from the gallery's language tag, else from its title; `nil` when neither
    /// names one.
    public let languageCode: String?
    /// Which favourites folder holds it, from the page it came with.
    public private(set) var favorite: FavoriteMark?
    /// The page last read, when known.
    public private(set) var readingProgress: Int?

    /// The circle and the artists the title names, "Circle · Artist, Artist"; `nil` when it
    /// names neither. The uploader never takes its place.
    public let credit: String?
    /// The uploader's name; `nil` when the page gave none.
    public let uploader: String?
    /// The rating rounded to the nearest half star (x.25 rounds up), 0...10: which strip of
    /// stars a row draws.
    public let halfStars: Int
    /// The rating with one or two decimals, "4.5" or "4.72", in the user's decimal separator.
    /// List pages give halves, so a row almost always shows one decimal.
    public let ratingText: String
    /// The gallery's first tags across its namespaces, in the page's order: at most
    /// `rowTagLimit`, which no row has room to exceed on its one line of tags.
    public let tags: [Tag]
    /// How long before its page was mapped the gallery was posted.
    public private(set) var postedAge: Age
    /// How long before its page was mapped it was favourited: favourites pages say, except in
    /// the Thumbnail mode; `nil` elsewhere.
    public private(set) var addedAge: Age?
    /// How long before its page was mapped it was last opened: History's rows; `nil` elsewhere.
    public private(set) var openedAge: Age?

    public var id: String { gallery.gid }

    /// The most tags an entry keeps: the chips that fit one line of the widest row.
    public static let rowTagLimit = 8

    /// Parses the title and works out the rest of the row, counting ages to `now`. Call it off
    /// the main actor.
    public init(gallery: Gallery, favorite: FavoriteMark? = nil, readingProgress: Int? = nil, now: Date = .now) {
        self.init(gallery: gallery, favorite: favorite, readingProgress: readingProgress, mapping: Mapping(now: now))
    }

    init(gallery: Gallery, favorite: FavoriteMark?, readingProgress: Int?, mapping: Mapping) {
        let title = TitleParser.parse(gallery.title)
        let rating = Self.clamped(gallery.rating)
        self.gallery = gallery
        self.title = title
        languageCode = Self.languageCode(of: gallery, title: title)
        self.favorite = favorite
        self.readingProgress = readingProgress
        credit = Self.credit(of: title)
        uploader = Self.uploader(of: gallery)
        halfStars = Int((rating * 2).rounded())
        ratingText = Self.ratingText(rating, decimalSeparator: mapping.decimalSeparator)
        tags = Self.rowTags(of: gallery.tags)
        postedAge = Age(from: gallery.postedDate, to: mapping.now)
        addedAge = favorite?.favoritedDate.map { Age(from: $0, to: mapping.now) }
        openedAge = gallery.lastOpenDate.map { Age(from: $0, to: mapping.now) }
    }

    /// Everything else follows from `gallery` (and the locale), so it is not compared. The ages
    /// are, since they also follow from the moment the page was mapped.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.gallery == rhs.gallery && lhs.favorite == rhs.favorite && lhs.readingProgress == rhs.readingProgress
            && lhs.postedAge == rhs.postedAge && lhs.addedAge == rhs.addedAge && lhs.openedAge == rhs.openedAge
    }
}

// MARK: Row values

nonisolated extension GalleryEntry {
    /// One tag of a row's tag line.
    public nonisolated struct Tag: Identifiable, Hashable, Sendable {
        /// The namespace and the tag run together, `femalebig breasts`: unique within a
        /// gallery, and the key tag translations are stored under.
        public let id: String
        public let text: String
        /// Which namespace's colour it takes; `nil` for one the app does not know, which takes
        /// Other's.
        public let namespace: TagNamespace?
        /// The colour the site highlights a watched tag with.
        public let watchedColor: RGBColor?

        public init(id: String, text: String, namespace: TagNamespace?, watchedColor: RGBColor? = nil) {
            self.id = id
            self.text = text
            self.namespace = namespace
            self.watchedColor = watchedColor
        }
    }

    /// How long ago something happened, in its largest whole unit: what a row shows as "3 h",
    /// "2 d" or "opened 5 min ago". A list meets fewer than 150 values, so the app can keep each
    /// one's text instead of formatting it in a row.
    public nonisolated struct Age: Hashable, Sendable {
        public enum Unit: Int, Hashable, Sendable, CaseIterable {
            case minute, hour, day, week, month, year
        }

        public let count: Int
        public let unit: Unit

        public init(count: Int, unit: Unit) {
            self.count = count
            self.unit = unit
        }

        /// The time from `date` to `now`, cut down to whole units: minutes up to an hour (at
        /// least one), hours up to a day, days up to a week, weeks up to 30 days, months of 30
        /// days up to a year (at most 11), then years of 365 days. A date after `now`, from a
        /// clock ahead of the device's, counts as now. Counted in seconds, not in calendar days,
        /// so it does not depend on the time zone.
        public init(from date: Date, to now: Date) {
            let interval = now.timeIntervalSince(date)
            // Held under about 30,000 years, so that no date, however wrong, overflows a count.
            let seconds = interval.isNaN ? 0 : min(max(interval, 0), 1e12)
            let days = Int(seconds / 86_400)
            switch seconds {
            case ..<3_600: self.init(count: max(Int(seconds / 60), 1), unit: .minute)
            case ..<86_400: self.init(count: Int(seconds / 3_600), unit: .hour)
            default:
                switch days {
                case ..<7: self.init(count: days, unit: .day)
                case ..<30: self.init(count: days / 7, unit: .week)
                case ..<365: self.init(count: min(days / 30, 11), unit: .month)
                default: self.init(count: days / 365, unit: .year)
                }
            }
        }

        /// The age as date components with only its unit set, for the system's formatters
        /// (`DateComponentsFormatter`, `RelativeDateTimeFormatter`).
        public var dateComponents: DateComponents {
            switch unit {
            case .minute: DateComponents(minute: count)
            case .hour: DateComponents(hour: count)
            case .day: DateComponents(day: count)
            case .week: DateComponents(weekOfMonth: count)
            case .month: DateComponents(month: count)
            case .year: DateComponents(year: count)
            }
        }
    }

    /// What mapping a page reads once for all its entries.
    nonisolated struct Mapping: Sendable {
        /// The moment ages are counted to.
        let now: Date
        let decimalSeparator: String

        init(now: Date, locale: Locale = .current) {
            self.now = now
            decimalSeparator = locale.decimalSeparator ?? "."
        }
    }

    static func languageCode(of gallery: Gallery, title: ParsedTitle) -> String? {
        if let code = gallery.language?.code { return code }
        return title.language.flatMap(TitleParser.language(named:))?.code
    }

    /// "Circle · Artist, Artist", "Circle" or "Artist"; a circle named after its one artist once.
    static func credit(of title: ParsedTitle) -> String? {
        let artists = title.artists.joined(separator: ", ")
        switch (title.circle, artists.isEmpty) {
        case (let circle?, false):
            return circle.caseInsensitiveCompare(artists) == .orderedSame ? circle : circle + " · " + artists
        case (let circle?, true): return circle
        case (nil, false): return artists
        case (nil, true): return nil
        }
    }

    static func uploader(of gallery: Gallery) -> String? {
        guard let name = gallery.uploader?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        return name
    }

    /// The rating within 0...5; a value that is not a number counts as unrated.
    static func clamped(_ rating: Float) -> Double {
        let value = Double(rating)
        return value.isFinite ? min(max(value, 0), 5) : 0
    }

    /// `rating` (0...5) with two decimals, or one when the second is zero: "4.72", "4.5", "4.0".
    /// Built from whole hundredths, which keeps the mapping clear of number formatters.
    static func ratingText(_ rating: Double, decimalSeparator: String) -> String {
        let hundredths = Int((rating * 100).rounded())
        let whole = String(hundredths / 100)
        let fraction = hundredths % 100
        if fraction % 10 == 0 { return whole + decimalSeparator + String(fraction / 10) }
        return whole + decimalSeparator + (fraction < 10 ? "0" : "") + String(fraction)
    }

    /// The first `rowTagLimit` tags across `tags`' namespaces, without repeats.
    static func rowTags(of tags: [GalleryTag]) -> [Tag] {
        var result: [Tag] = []
        result.reserveCapacity(min(tags.reduce(0) { $0 + $1.contents.count }, rowTagLimit))
        for group in tags {
            let namespace = group.namespace
            for content in group.contents {
                let id = content.id
                guard !result.contains(where: { $0.id == id }) else { continue }
                result.append(Tag(id: id, text: content.text, namespace: namespace, watchedColor: content.backgroundColor))
                if result.count == rowTagLimit { return result }
            }
        }
        return result
    }
}

// MARK: Mapping

nonisolated extension GalleryEntry {
    /// Entries for `galleries`, with their favourite marks, their ages counted to `now`. An
    /// entry in `previous` for the same version of a gallery is reused with its ages counted
    /// again, so a gallery's title is parsed once however often its list is re-read.
    static func entries(
        for galleries: [Gallery], marks: [String: FavoriteMark] = [:], reusing previous: [GalleryEntry] = [],
        now: Date = .now
    ) -> [GalleryEntry] {
        let mapping = Mapping(now: now)
        let known = previous.isEmpty
            ? [:] : Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return galleries.map { gallery in
            let favorite = marks[gallery.gid]
            if let entry = known[gallery.gid], entry.gallery == gallery {
                return entry.recounted(favorite: favorite, now: now)
            }
            return GalleryEntry(gallery: gallery, favorite: favorite, readingProgress: nil, mapping: mapping)
        }
    }

    /// The entry with `favorite` and its ages counted to `now`; the title is not parsed again.
    func recounted(favorite: FavoriteMark?, now: Date) -> GalleryEntry {
        var entry = self
        entry.favorite = favorite
        entry.postedAge = Age(from: gallery.postedDate, to: now)
        entry.addedAge = favorite?.favoritedDate.map { Age(from: $0, to: now) }
        entry.openedAge = gallery.lastOpenDate.map { Age(from: $0, to: now) }
        return entry
    }

    func with(readingProgress: Int?) -> GalleryEntry {
        var entry = self
        entry.readingProgress = readingProgress
        return entry
    }
}
