import EhModels

extension SettingsStore {
    /// Every setting as one value. Reading it observes every property, so views should read
    /// the individual properties instead.
    public var setting: Setting {
        var setting = Setting()
        setting.galleryHost = galleryHost
        setting.showsNewDawnGreeting = showsNewDawnGreeting
        setting.enablesTagsExtension = enablesTagsExtension
        setting.translatesTags = translatesTags
        setting.showsTagsSearchSuggestion = showsTagsSearchSuggestion
        setting.showsImagesInTags = showsImagesInTags
        setting.redirectsLinksToSelectedHost = redirectsLinksToSelectedHost
        setting.detectsLinksFromClipboard = detectsLinksFromClipboard
        setting.backgroundBlurRadius = backgroundBlurRadius
        setting.autoLockPolicy = autoLockPolicy
        setting.listDisplayMode = listDisplayMode
        setting.preferredColorScheme = preferredColorScheme
        setting.accentColor = accentColor
        setting.appIconType = appIconType
        setting.showsTagsInList = showsTagsInList
        setting.listTagsNumberMaximum = listTagsNumberMaximum
        setting.displaysJapaneseTitle = displaysJapaneseTitle
        setting.readingDirection = readingDirection
        setting.prefetchLimit = prefetchLimit
        setting.enablesLandscape = enablesLandscape
        setting.enablesDualPageMode = enablesDualPageMode
        setting.exceptCover = exceptCover
        setting.contentDividerHeight = contentDividerHeight
        setting.maximumScaleFactor = maximumScaleFactor
        setting.doubleTapScaleFactor = doubleTapScaleFactor
        setting.bypassesSNIFiltering = bypassesSNIFiltering
        setting.designBar = designBar
        setting.designStart = designStart
        setting.designList = designList
        setting.designGallery = designGallery
        setting.designReader = designReader
        setting.designSearch = designSearch
        setting.designLibrary = designLibrary
        setting.designLook = designLook
        setting.designCustom = designCustom
        setting.wallDensity = wallDensity
        setting.ledgerShowsCovers = ledgerShowsCovers
        setting.lastFavoriteFolder = lastFavoriteFolder
        setting.lastPlace = lastPlace
        setting.experienceOfferShown = experienceOfferShown
        setting.pageTranslationDetector = pageTranslationDetector
        setting.pageTranslationReader = pageTranslationReader
        setting.pageTranslationTranslator = pageTranslationTranslator
        setting.pageTranslationRepaint = pageTranslationRepaint
        setting.pageTranslationTranslatesSoundEffects = pageTranslationTranslatesSoundEffects
        setting.pageTranslationSourceAddress = pageTranslationSourceAddress
        setting.pageTranslationPendingDetector = pageTranslationPendingDetector
        setting.pageTranslationPendingReader = pageTranslationPendingReader
        setting.pageTranslationPendingTranslator = pageTranslationPendingTranslator
        setting.pageTranslationPendingRepaint = pageTranslationPendingRepaint
        return setting
    }

    /// Replaces every setting with `setting`, after making it satisfy the coupling rules
    /// (see `Setting.enforcingRules()`). Only the keys whose value changes are written.
    public func apply(_ setting: Setting) {
        // Assigning a value that already satisfies every rule never triggers a rule that
        // changes a field assigned earlier, so plain assignment in field order lands exactly on
        // `setting`.
        let setting = setting.enforcingRules()
        galleryHost = setting.galleryHost
        showsNewDawnGreeting = setting.showsNewDawnGreeting
        enablesTagsExtension = setting.enablesTagsExtension
        translatesTags = setting.translatesTags
        showsTagsSearchSuggestion = setting.showsTagsSearchSuggestion
        showsImagesInTags = setting.showsImagesInTags
        redirectsLinksToSelectedHost = setting.redirectsLinksToSelectedHost
        detectsLinksFromClipboard = setting.detectsLinksFromClipboard
        backgroundBlurRadius = setting.backgroundBlurRadius
        autoLockPolicy = setting.autoLockPolicy
        listDisplayMode = setting.listDisplayMode
        preferredColorScheme = setting.preferredColorScheme
        accentColor = setting.accentColor
        appIconType = setting.appIconType
        showsTagsInList = setting.showsTagsInList
        listTagsNumberMaximum = setting.listTagsNumberMaximum
        displaysJapaneseTitle = setting.displaysJapaneseTitle
        readingDirection = setting.readingDirection
        prefetchLimit = setting.prefetchLimit
        enablesLandscape = setting.enablesLandscape
        enablesDualPageMode = setting.enablesDualPageMode
        exceptCover = setting.exceptCover
        contentDividerHeight = setting.contentDividerHeight
        maximumScaleFactor = setting.maximumScaleFactor
        doubleTapScaleFactor = setting.doubleTapScaleFactor
        bypassesSNIFiltering = setting.bypassesSNIFiltering
        designBar = setting.designBar
        designStart = setting.designStart
        designList = setting.designList
        designGallery = setting.designGallery
        designReader = setting.designReader
        designSearch = setting.designSearch
        designLibrary = setting.designLibrary
        designLook = setting.designLook
        designCustom = setting.designCustom
        wallDensity = setting.wallDensity
        ledgerShowsCovers = setting.ledgerShowsCovers
        lastFavoriteFolder = setting.lastFavoriteFolder
        lastPlace = setting.lastPlace
        experienceOfferShown = setting.experienceOfferShown
        pageTranslationDetector = setting.pageTranslationDetector
        pageTranslationReader = setting.pageTranslationReader
        pageTranslationTranslator = setting.pageTranslationTranslator
        pageTranslationRepaint = setting.pageTranslationRepaint
        pageTranslationTranslatesSoundEffects = setting.pageTranslationTranslatesSoundEffects
        pageTranslationSourceAddress = setting.pageTranslationSourceAddress
        pageTranslationPendingDetector = setting.pageTranslationPendingDetector
        pageTranslationPendingReader = setting.pageTranslationPendingReader
        pageTranslationPendingTranslator = setting.pageTranslationPendingTranslator
        pageTranslationPendingRepaint = setting.pageTranslationPendingRepaint
    }
}
