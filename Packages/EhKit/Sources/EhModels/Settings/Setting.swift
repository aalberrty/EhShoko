import Foundation

/// The app's own preferences.
public struct Setting: Sendable, Equatable {
    // Account
    public var galleryHost: GalleryHost = .ehentai
    public var showsNewDawnGreeting = false

    // General
    public var enablesTagsExtension = false {
        didSet {
            if !enablesTagsExtension {
                translatesTags = false
                showsTagsSearchSuggestion = false
                showsImagesInTags = false
            }
        }
    }
    public var translatesTags = false
    public var showsTagsSearchSuggestion = false
    public var showsImagesInTags = false
    public var redirectsLinksToSelectedHost = false
    public var detectsLinksFromClipboard = false
    public var backgroundBlurRadius: Double = 10
    public var autoLockPolicy: AutoLockPolicy = .never

    // Appearance
    /// Legacy defaulted to `.thumbnail` on iPad-width screens; the app applies that
    /// default itself because this module cannot know the screen.
    public var listDisplayMode: ListDisplayMode = .detail
    public var preferredColorScheme: PreferredColorScheme = .automatic
    public var accentColor: RGBColor = .systemBlue
    public var appIconType: AppIconType = .default
    public var showsTagsInList = false
    public var listTagsNumberMaximum = 0
    public var displaysJapaneseTitle = true

    // Reading
    public var readingDirection: ReadingDirection = .vertical
    public var prefetchLimit = 10
    public var enablesLandscape = false
    public var enablesDualPageMode = false
    public var exceptCover = false
    public var contentDividerHeight: Double = 0
    public var maximumScaleFactor: Double = 3
    public var doubleTapScaleFactor: Double = 2

    // Laboratory
    public var bypassesSNIFiltering = false

    // Experience: one design per part (defaults: the Shelf preset)
    public var designBar: BarStyle = .tabs
    public var designStart: DesignStyle = .shelf
    public var designList: DesignStyle = .shelf
    public var designGallery: DesignStyle = .shelf
    public var designReader: DesignStyle = .shelf
    public var designSearch: DesignStyle = .shelf
    public var designLibrary: DesignStyle = .shelf
    public var designLook: DesignStyle = .shelf
    /// The last mix that was not a preset, so "Custom" can be chosen again.
    public var designCustom: DesignChoices?
    public var wallDensity: WallDensity = .medium
    public var ledgerShowsCovers = true
    /// The favourites folder a plain tap on Favourite uses (0...9).
    public var lastFavoriteFolder = 0
    /// The list Ledger's first screen reopens at launch; `nil` for its Index.
    public var lastPlace: GalleryListKind?
    /// Whether the offer after install was shown.
    public var experienceOfferShown = false

    // Page translation. There is no switch: Translate is pressed in each reader.
    public var pageTranslationDetector: TextDetectorChoice = .default
    public var pageTranslationReader: TextReaderChoice = .default
    public var pageTranslationTranslator: TranslatorChoice = .default
    public var pageTranslationRepaint: RepaintChoice = .default
    /// "Translate drawn sound effects": off, a box the detector calls a sound effect is read
    /// only when it stands in a balloon; on, every box is read, translated, erased and lettered.
    public var pageTranslationTranslatesSoundEffects = false
    /// The address of the private store the app's own model files come from; empty until
    /// the user enters one. Its access token is kept in the Keychain, not here.
    public var pageTranslationSourceAddress = ""
    /// A model of each kind the user chose while it was not installed: it is downloading and
    /// replaces the current one when its install finishes. Kept so the choice survives the
    /// app being closed before that; `nil` when nothing of the kind waits.
    public var pageTranslationPendingDetector: TextDetectorChoice?
    public var pageTranslationPendingReader: TextReaderChoice?
    public var pageTranslationPendingTranslator: TranslatorChoice?
    public var pageTranslationPendingRepaint: RepaintChoice?

    public init() {}

    /// The detector, reader and translator the page translation settings choose, and whether
    /// drawn sound effects are translated with them.
    public var pageTranslationModelSet: PageTranslationModelSet {
        PageTranslationModelSet(
            detector: pageTranslationDetector, reader: pageTranslationReader, translator: pageTranslationTranslator,
            translatesSoundEffects: pageTranslationTranslatesSoundEffects
        )
    }
}

