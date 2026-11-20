import EhModels
import Foundation
import Observation

/// The app's own preferences, one observable property per `Setting` field.
///
/// A view that reads `settings.showsTagsInList` re-renders only when that property changes,
/// and a change writes only that property's `UserDefaults` key (see `SettingKey`). Rules that
/// tie settings together run here, in each property's `didSet` (see `SettingsStore+Rules`), so
/// no view can break them. Create one per process and share it through `\.settings`.
@MainActor @Observable
public final class SettingsStore {
    @ObservationIgnored let storage: PreferenceStorage

    // MARK: Account
    public var galleryHost: GalleryHost { didSet { persist(.galleryHost, galleryHost, oldValue) } }
    public var showsNewDawnGreeting: Bool {
        didSet { persist(.showsNewDawnGreeting, showsNewDawnGreeting, oldValue) }
    }

    // MARK: General
    public var enablesTagsExtension: Bool {
        didSet {
            persist(.enablesTagsExtension, enablesTagsExtension, oldValue)
            enforceTagsExtensionRule()
        }
    }
    public var translatesTags: Bool { didSet { persist(.translatesTags, translatesTags, oldValue) } }
    public var showsTagsSearchSuggestion: Bool {
        didSet { persist(.showsTagsSearchSuggestion, showsTagsSearchSuggestion, oldValue) }
    }
    public var showsImagesInTags: Bool { didSet { persist(.showsImagesInTags, showsImagesInTags, oldValue) } }
    public var redirectsLinksToSelectedHost: Bool {
        didSet { persist(.redirectsLinksToSelectedHost, redirectsLinksToSelectedHost, oldValue) }
    }
    public var detectsLinksFromClipboard: Bool {
        didSet { persist(.detectsLinksFromClipboard, detectsLinksFromClipboard, oldValue) }
    }
    public var backgroundBlurRadius: Double {
        didSet {
            persist(.backgroundBlurRadius, backgroundBlurRadius, oldValue)
            enforceBlurRadiusRule()
        }
    }
    public var autoLockPolicy: AutoLockPolicy {
        didSet {
            persist(.autoLockPolicy, autoLockPolicy, oldValue)
            enforceAutoLockRule()
        }
    }

    // MARK: Appearance
    public var listDisplayMode: ListDisplayMode {
        didSet { persist(.listDisplayMode, listDisplayMode, oldValue) }
    }
    public var preferredColorScheme: PreferredColorScheme {
        didSet { persist(.preferredColorScheme, preferredColorScheme, oldValue) }
    }
    public var accentColor: RGBColor { didSet { persist(.accentColor, accentColor, oldValue) } }
    public var appIconType: AppIconType { didSet { persist(.appIconType, appIconType, oldValue) } }
    public var showsTagsInList: Bool { didSet { persist(.showsTagsInList, showsTagsInList, oldValue) } }
    public var listTagsNumberMaximum: Int {
        didSet { persist(.listTagsNumberMaximum, listTagsNumberMaximum, oldValue) }
    }
    public var displaysJapaneseTitle: Bool {
        didSet { persist(.displaysJapaneseTitle, displaysJapaneseTitle, oldValue) }
    }

    // MARK: Reading
    public var readingDirection: ReadingDirection {
        didSet { persist(.readingDirection, readingDirection, oldValue) }
    }
    public var prefetchLimit: Int { didSet { persist(.prefetchLimit, prefetchLimit, oldValue) } }
    public var enablesLandscape: Bool { didSet { persist(.enablesLandscape, enablesLandscape, oldValue) } }
    public var enablesDualPageMode: Bool {
        didSet { persist(.enablesDualPageMode, enablesDualPageMode, oldValue) }
    }
    public var exceptCover: Bool { didSet { persist(.exceptCover, exceptCover, oldValue) } }
    public var contentDividerHeight: Double {
        didSet { persist(.contentDividerHeight, contentDividerHeight, oldValue) }
    }
    public var maximumScaleFactor: Double {
        didSet {
            persist(.maximumScaleFactor, maximumScaleFactor, oldValue)
            enforceMaximumScaleFactorRule()
        }
    }
    public var doubleTapScaleFactor: Double {
        didSet {
            persist(.doubleTapScaleFactor, doubleTapScaleFactor, oldValue)
            enforceDoubleTapScaleFactorRule()
        }
    }

    // MARK: Laboratory
    public var bypassesSNIFiltering: Bool {
        didSet { persist(.bypassesSNIFiltering, bypassesSNIFiltering, oldValue) }
    }

    // MARK: Experience
    // Read by the shell's switch points and Settings only (see `SettingsStore+Design`).
    public var designBar: BarStyle { didSet { persist(.designBar, designBar, oldValue) } }
    public var designStart: DesignStyle { didSet { persist(.designStart, designStart, oldValue) } }
    public var designList: DesignStyle { didSet { persist(.designList, designList, oldValue) } }
    public var designGallery: DesignStyle { didSet { persist(.designGallery, designGallery, oldValue) } }
    public var designReader: DesignStyle { didSet { persist(.designReader, designReader, oldValue) } }
    public var designSearch: DesignStyle { didSet { persist(.designSearch, designSearch, oldValue) } }
    public var designLibrary: DesignStyle { didSet { persist(.designLibrary, designLibrary, oldValue) } }
    public var designLook: DesignStyle { didSet { persist(.designLook, designLook, oldValue) } }
    public var designCustom: DesignChoices? {
        didSet {
            guard designCustom != oldValue else { return }
            storage.set(designCustom, for: .designCustom)
        }
    }
    public var wallDensity: WallDensity { didSet { persist(.wallDensity, wallDensity, oldValue) } }
    public var ledgerShowsCovers: Bool { didSet { persist(.ledgerShowsCovers, ledgerShowsCovers, oldValue) } }
    public var lastFavoriteFolder: Int {
        didSet {
            persist(.lastFavoriteFolder, lastFavoriteFolder, oldValue)
            enforceFavoriteFolderRule()
        }
    }
    public var lastPlace: GalleryListKind? {
        didSet {
            guard lastPlace != oldValue else { return }
            storage.set(lastPlace, for: .lastPlace)
        }
    }
    public var experienceOfferShown: Bool {
        didSet { persist(.experienceOfferShown, experienceOfferShown, oldValue) }
    }

    // MARK: Page translation
    // Read by the reader's translation model and the Translation settings screen only; no
    // cell and no engine view reads them. There is no switch: Translate is pressed in each
    // reader and lasts until it closes.
    public var pageTranslationDetector: TextDetectorChoice {
        didSet { persist(.pageTranslationDetector, pageTranslationDetector, oldValue) }
    }
    public var pageTranslationReader: TextReaderChoice {
        didSet { persist(.pageTranslationReader, pageTranslationReader, oldValue) }
    }
    public var pageTranslationTranslator: TranslatorChoice {
        didSet { persist(.pageTranslationTranslator, pageTranslationTranslator, oldValue) }
    }
    public var pageTranslationRepaint: RepaintChoice {
        didSet { persist(.pageTranslationRepaint, pageTranslationRepaint, oldValue) }
    }
    public var pageTranslationSourceAddress: String {
        didSet { persist(.pageTranslationSourceAddress, pageTranslationSourceAddress, oldValue) }
    }
    /// A choice of each kind that waits for its model's install (Settings › Translation).
    public var pageTranslationPendingDetector: TextDetectorChoice? {
        didSet { persistOptional(.pageTranslationPendingDetector, pageTranslationPendingDetector, oldValue) }
    }
    public var pageTranslationPendingReader: TextReaderChoice? {
        didSet { persistOptional(.pageTranslationPendingReader, pageTranslationPendingReader, oldValue) }
    }
    public var pageTranslationPendingTranslator: TranslatorChoice? {
        didSet { persistOptional(.pageTranslationPendingTranslator, pageTranslationPendingTranslator, oldValue) }
    }
    public var pageTranslationPendingRepaint: RepaintChoice? {
        didSet { persistOptional(.pageTranslationPendingRepaint, pageTranslationPendingRepaint, oldValue) }
    }
    /// The detector, reader and translator the settings choose. Reading it observes those three.
    public var pageTranslationModelSet: PageTranslationModelSet {
        PageTranslationModelSet(
            detector: pageTranslationDetector, reader: pageTranslationReader, translator: pageTranslationTranslator
        )
    }

    /// Loads every setting from `defaults`; a missing or invalid key falls back to `Setting()`.
    ///
    /// `nonisolated` so a `DependencyKey` can create the store from any context.
    public nonisolated convenience init(defaults: UserDefaults) {
        self.init(storage: PreferenceStorage(defaults))
    }

    nonisolated init(storage: PreferenceStorage) {
        self.storage = storage
        let setting = Setting(storage: storage).enforcingRules()
        // A nonisolated init cannot call the main-actor setters `@Observable` generates, so it
        // initializes their backing storage directly. This also skips `didSet`: loading
        // writes nothing back.
        _galleryHost = setting.galleryHost
        _showsNewDawnGreeting = setting.showsNewDawnGreeting
        _enablesTagsExtension = setting.enablesTagsExtension
        _translatesTags = setting.translatesTags
        _showsTagsSearchSuggestion = setting.showsTagsSearchSuggestion
        _showsImagesInTags = setting.showsImagesInTags
        _redirectsLinksToSelectedHost = setting.redirectsLinksToSelectedHost
        _detectsLinksFromClipboard = setting.detectsLinksFromClipboard
        _backgroundBlurRadius = setting.backgroundBlurRadius
        _autoLockPolicy = setting.autoLockPolicy
        _listDisplayMode = setting.listDisplayMode
        _preferredColorScheme = setting.preferredColorScheme
        _accentColor = setting.accentColor
        _appIconType = setting.appIconType
        _showsTagsInList = setting.showsTagsInList
        _listTagsNumberMaximum = setting.listTagsNumberMaximum
        _displaysJapaneseTitle = setting.displaysJapaneseTitle
        _readingDirection = setting.readingDirection
        _prefetchLimit = setting.prefetchLimit
        _enablesLandscape = setting.enablesLandscape
        _enablesDualPageMode = setting.enablesDualPageMode
        _exceptCover = setting.exceptCover
        _contentDividerHeight = setting.contentDividerHeight
        _maximumScaleFactor = setting.maximumScaleFactor
        _doubleTapScaleFactor = setting.doubleTapScaleFactor
        _bypassesSNIFiltering = setting.bypassesSNIFiltering
        _designBar = setting.designBar
        _designStart = setting.designStart
        _designList = setting.designList
        _designGallery = setting.designGallery
        _designReader = setting.designReader
        _designSearch = setting.designSearch
        _designLibrary = setting.designLibrary
        _designLook = setting.designLook
        _designCustom = setting.designCustom
        _wallDensity = setting.wallDensity
        _ledgerShowsCovers = setting.ledgerShowsCovers
        _lastFavoriteFolder = setting.lastFavoriteFolder
        _lastPlace = setting.lastPlace
        _experienceOfferShown = setting.experienceOfferShown
        _pageTranslationDetector = setting.pageTranslationDetector
        _pageTranslationReader = setting.pageTranslationReader
        _pageTranslationTranslator = setting.pageTranslationTranslator
        _pageTranslationRepaint = setting.pageTranslationRepaint
        _pageTranslationSourceAddress = setting.pageTranslationSourceAddress
        _pageTranslationPendingDetector = setting.pageTranslationPendingDetector
        _pageTranslationPendingReader = setting.pageTranslationPendingReader
        _pageTranslationPendingTranslator = setting.pageTranslationPendingTranslator
        _pageTranslationPendingRepaint = setting.pageTranslationPendingRepaint
    }

    /// Reads the selected host off the main actor from the same defaults this store writes.
    public nonisolated var galleryHostProvider: GalleryHostProvider {
        GalleryHostProvider(storage: storage)
    }

    /// Writes `key` only when the value really changed; `didSet` also runs for equal values.
    private func persist<Value: PreferenceValue>(_ key: SettingKey, _ value: Value, _ oldValue: Value) {
        guard value != oldValue else { return }
        storage.set(value, for: key)
    }

    /// Writes or removes an optional setting's key when its value really changed.
    private func persistOptional<Value: PreferenceValue>(_ key: SettingKey, _ value: Value?, _ oldValue: Value?) {
        guard value != oldValue else { return }
        storage.set(value, for: key)
    }
}

extension Setting {
    /// Reads every field from `storage`, falling back to the field's default.
    init(storage: PreferenceStorage) {
        let defaults = Setting()
        self.init()
        galleryHost = storage.value(.galleryHost, fallback: defaults.galleryHost)
        showsNewDawnGreeting = storage.value(.showsNewDawnGreeting, fallback: defaults.showsNewDawnGreeting)
        enablesTagsExtension = storage.value(.enablesTagsExtension, fallback: defaults.enablesTagsExtension)
        translatesTags = storage.value(.translatesTags, fallback: defaults.translatesTags)
        showsTagsSearchSuggestion = storage.value(
            .showsTagsSearchSuggestion, fallback: defaults.showsTagsSearchSuggestion
        )
        showsImagesInTags = storage.value(.showsImagesInTags, fallback: defaults.showsImagesInTags)
        redirectsLinksToSelectedHost = storage.value(
            .redirectsLinksToSelectedHost, fallback: defaults.redirectsLinksToSelectedHost
        )
        detectsLinksFromClipboard = storage.value(
            .detectsLinksFromClipboard, fallback: defaults.detectsLinksFromClipboard
        )
        backgroundBlurRadius = storage.value(.backgroundBlurRadius, fallback: defaults.backgroundBlurRadius)
        autoLockPolicy = storage.value(.autoLockPolicy, fallback: defaults.autoLockPolicy)
        listDisplayMode = storage.value(.listDisplayMode, fallback: defaults.listDisplayMode)
        preferredColorScheme = storage.value(.preferredColorScheme, fallback: defaults.preferredColorScheme)
        accentColor = storage.value(.accentColor, fallback: defaults.accentColor)
        appIconType = storage.value(.appIconType, fallback: defaults.appIconType)
        showsTagsInList = storage.value(.showsTagsInList, fallback: defaults.showsTagsInList)
        listTagsNumberMaximum = storage.value(.listTagsNumberMaximum, fallback: defaults.listTagsNumberMaximum)
        displaysJapaneseTitle = storage.value(.displaysJapaneseTitle, fallback: defaults.displaysJapaneseTitle)
        readingDirection = storage.value(.readingDirection, fallback: defaults.readingDirection)
        prefetchLimit = storage.value(.prefetchLimit, fallback: defaults.prefetchLimit)
        enablesLandscape = storage.value(.enablesLandscape, fallback: defaults.enablesLandscape)
        enablesDualPageMode = storage.value(.enablesDualPageMode, fallback: defaults.enablesDualPageMode)
        exceptCover = storage.value(.exceptCover, fallback: defaults.exceptCover)
        contentDividerHeight = storage.value(.contentDividerHeight, fallback: defaults.contentDividerHeight)
        maximumScaleFactor = storage.value(.maximumScaleFactor, fallback: defaults.maximumScaleFactor)
        doubleTapScaleFactor = storage.value(.doubleTapScaleFactor, fallback: defaults.doubleTapScaleFactor)
        bypassesSNIFiltering = storage.value(.bypassesSNIFiltering, fallback: defaults.bypassesSNIFiltering)
        designBar = storage.value(.designBar, fallback: defaults.designBar)
        designStart = storage.value(.designStart, fallback: defaults.designStart)
        designList = storage.value(.designList, fallback: defaults.designList)
        designGallery = storage.value(.designGallery, fallback: defaults.designGallery)
        designReader = storage.value(.designReader, fallback: defaults.designReader)
        designSearch = storage.value(.designSearch, fallback: defaults.designSearch)
        designLibrary = storage.value(.designLibrary, fallback: defaults.designLibrary)
        designLook = storage.value(.designLook, fallback: defaults.designLook)
        designCustom = storage.optionalValue(.designCustom, as: DesignChoices.self)
        wallDensity = storage.value(.wallDensity, fallback: defaults.wallDensity)
        ledgerShowsCovers = storage.value(.ledgerShowsCovers, fallback: defaults.ledgerShowsCovers)
        lastFavoriteFolder = storage.value(.lastFavoriteFolder, fallback: defaults.lastFavoriteFolder)
        lastPlace = storage.optionalValue(.lastPlace, as: GalleryListKind.self)
        experienceOfferShown = storage.value(.experienceOfferShown, fallback: defaults.experienceOfferShown)
        pageTranslationDetector = storage.value(.pageTranslationDetector, fallback: defaults.pageTranslationDetector)
        pageTranslationReader = storage.value(.pageTranslationReader, fallback: defaults.pageTranslationReader)
        pageTranslationTranslator = storage.value(
            .pageTranslationTranslator, fallback: defaults.pageTranslationTranslator
        )
        pageTranslationRepaint = storage.value(.pageTranslationRepaint, fallback: defaults.pageTranslationRepaint)
        pageTranslationSourceAddress = storage.value(
            .pageTranslationSourceAddress, fallback: defaults.pageTranslationSourceAddress
        )
        pageTranslationPendingDetector = storage.optionalValue(.pageTranslationPendingDetector, as: TextDetectorChoice.self)
        pageTranslationPendingReader = storage.optionalValue(.pageTranslationPendingReader, as: TextReaderChoice.self)
        pageTranslationPendingTranslator = storage.optionalValue(
            .pageTranslationPendingTranslator, as: TranslatorChoice.self
        )
        pageTranslationPendingRepaint = storage.optionalValue(.pageTranslationPendingRepaint, as: RepaintChoice.self)
    }
}
