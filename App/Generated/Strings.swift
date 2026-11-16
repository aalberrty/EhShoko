// swiftlint:disable all
// Generated using SwiftGen — https://github.com/SwiftGen/SwiftGen

import Foundation

// swiftlint:disable superfluous_disable_command file_length implicit_return prefer_self_in_static_references

// MARK: - Strings

// swiftlint:disable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:disable nesting type_body_length type_name vertical_whitespace_opening_braces
internal enum L10n {
  internal enum Constant {
    internal enum App {
      internal enum Acknowledgement {
        internal enum Link {
          /// https://github.com/groue/GRDB.swift
          internal static let grdb = L10n.tr("Constant", "app.acknowledgement.link.grdb", fallback: "https://github.com/groue/GRDB.swift")
          /// https://github.com/tid-kijyun/Kanna
          internal static let kanna = L10n.tr("Constant", "app.acknowledgement.link.kanna", fallback: "https://github.com/tid-kijyun/Kanna")
          /// https://github.com/onevcat/Kingfisher
          internal static let kingfisher = L10n.tr("Constant", "app.acknowledgement.link.kingfisher", fallback: "https://github.com/onevcat/Kingfisher")
          /// https://github.com/SFSafeSymbols/SFSafeSymbols
          internal static let sfSafeSymbols = L10n.tr("Constant", "app.acknowledgement.link.sfSafeSymbols", fallback: "https://github.com/SFSafeSymbols/SFSafeSymbols")
          /// https://github.com/pointfreeco/swift-dependencies
          internal static let swiftDependencies = L10n.tr("Constant", "app.acknowledgement.link.swiftDependencies", fallback: "https://github.com/pointfreeco/swift-dependencies")
          /// https://github.com/SwiftGen/SwiftGen
          internal static let swiftGen = L10n.tr("Constant", "app.acknowledgement.link.swiftGen", fallback: "https://github.com/SwiftGen/SwiftGen")
          /// https://github.com/ddddxxx/SwiftyOpenCC
          internal static let swiftyOpenCC = L10n.tr("Constant", "app.acknowledgement.link.swiftyOpenCC", fallback: "https://github.com/ddddxxx/SwiftyOpenCC")
        }
        internal enum Text {
          /// GRDB.swift
          internal static let grdb = L10n.tr("Constant", "app.acknowledgement.text.grdb", fallback: "GRDB.swift")
          /// Kanna
          internal static let kanna = L10n.tr("Constant", "app.acknowledgement.text.kanna", fallback: "Kanna")
          /// Kingfisher
          internal static let kingfisher = L10n.tr("Constant", "app.acknowledgement.text.kingfisher", fallback: "Kingfisher")
          /// SFSafeSymbols
          internal static let sfSafeSymbols = L10n.tr("Constant", "app.acknowledgement.text.sfSafeSymbols", fallback: "SFSafeSymbols")
          /// swift-dependencies
          internal static let swiftDependencies = L10n.tr("Constant", "app.acknowledgement.text.swiftDependencies", fallback: "swift-dependencies")
          /// SwiftGen
          internal static let swiftGen = L10n.tr("Constant", "app.acknowledgement.text.swiftGen", fallback: "SwiftGen")
          /// SwiftyOpenCC
          internal static let swiftyOpenCC = L10n.tr("Constant", "app.acknowledgement.text.swiftyOpenCC", fallback: "SwiftyOpenCC")
        }
      }
      internal enum Contact {
        internal enum Link {
          /// https://github.com/aalberrty/EhShoko
          internal static let gitHub = L10n.tr("Constant", "app.contact.link.gitHub", fallback: "https://github.com/aalberrty/EhShoko")
        }
        internal enum Text {
          /// GitHub
          internal static let gitHub = L10n.tr("Constant", "app.contact.text.gitHub", fallback: "GitHub")
        }
      }
      internal enum SpecialThanks {
        internal enum Link {
          /// https://github.com/EhTagTranslation
          internal static let ehTagTranslation = L10n.tr("Constant", "app.special_thanks.link.ehTagTranslation", fallback: "https://github.com/EhTagTranslation")
        }
        internal enum Text {
          /// EhTagTranslation
          internal static let ehTagTranslation = L10n.tr("Constant", "app.special_thanks.text.ehTagTranslation", fallback: "EhTagTranslation")
        }
      }
    }
    internal enum Website {
      internal enum Response {
        /// ExHentai did not accept your login. The login may have expired, or this account may not have access to ExHentai. Log in again in Settings › Account, or switch the gallery host to E-Hentai there.
        internal static let exhentaiAccessDenied = L10n.tr("Localizable", "error_view.title.exhentai_access_denied", fallback: "ExHentai did not accept your login. The login may have expired, or this account may not have access to ExHentai. Log in again in Settings › Account, or switch the gallery host to E-Hentai there.")
        /// This gallery has been removed or is unavailable.
        internal static let galleryUnavailable = L10n.tr("Constant", "website.response.gallery_unavailable", fallback: "This gallery has been removed or is unavailable.")
        /// Constant.strings
        ///   EhShoko
        internal static let hathClientNotFound = L10n.tr("Constant", "website.response.hath_client_not_found", fallback: "You must have a H@H client assigned to your account to use this feature.")
        /// Your H@H client appears to be offline. Turn it on, then try again.
        internal static let hathClientNotOnline = L10n.tr("Constant", "website.response.hath_client_not_online", fallback: "Your H@H client appears to be offline. Turn it on, then try again.")
        /// The requested gallery cannot be downloaded with the selected resolution.
        internal static let invalidResolution = L10n.tr("Constant", "website.response.invalid_resolution", fallback: "The requested gallery cannot be downloaded with the selected resolution.")
      }
    }
  }
  internal enum InfoPlist {
    /// InfoPlist.strings
    ///   EhShoko
    internal static let nsFaceIDUsageDescription = L10n.tr("InfoPlist", "NSFaceIDUsageDescription", fallback: "EhShoko uses Face ID to unlock the app when Auto-Lock is on.")
    /// EhShoko saves the images you choose to your photo library.
    internal static let nsPhotoLibraryAddUsageDescription = L10n.tr("InfoPlist", "NSPhotoLibraryAddUsageDescription", fallback: "EhShoko saves the images you choose to your photo library.")
  }
  internal enum Localizable {
    internal enum AboutView {
      internal enum Section {
        internal enum Title {
          /// Open-source software
          internal static let acknowledgements = L10n.tr("Localizable", "about_view.section.title.acknowledgements", fallback: "Open-source software")
          /// Thanks to
          internal static let specialThanks = L10n.tr("Localizable", "about_view.section.title.special_thanks", fallback: "Thanks to")
        }
      }
      internal enum Title {
        /// EhShoko
        internal static let ehShoko = L10n.tr("Localizable", "about_view.title.ehShoko", fallback: "EhShoko")
        /// Version
        internal static let version = L10n.tr("Localizable", "about_view.title.version", fallback: "Version")
      }
    }
    internal enum AccountSettingView {
      internal enum Button {
        /// Site settings
        internal static let accountConfiguration = L10n.tr("Localizable", "account_setting_view.button.account_configuration", fallback: "Site settings")
        /// Copy cookies
        internal static let copyCookies = L10n.tr("Localizable", "account_setting_view.button.copy_cookies", fallback: "Copy cookies")
        /// Sign in
        internal static let login = L10n.tr("Localizable", "account_setting_view.button.login", fallback: "Sign in")
        /// Sign out
        internal static let logout = L10n.tr("Localizable", "account_setting_view.button.logout", fallback: "Sign out")
        /// Edit My Tags
        internal static let tagsManagement = L10n.tr("Localizable", "account_setting_view.button.tags_management", fallback: "Edit My Tags")
      }
      internal enum Title {
        /// Show the daily reward
        internal static let showsNewDawnGreeting = L10n.tr("Localizable", "account_setting_view.title.shows_new_dawn_greeting", fallback: "Show the daily reward")
      }
    }
    internal enum AppIconView {
      internal enum Title {
        /// App icon
        internal static let appIcon = L10n.tr("Localizable", "app_icon_view.title.app_icon", fallback: "App icon")
      }
    }
    internal enum AppearanceSettingView {
      internal enum Button {
        /// App icon
        internal static let appIcon = L10n.tr("Localizable", "appearance_setting_view.button.app_icon", fallback: "App icon")
      }
      internal enum Menu {
        internal enum Title {
          /// No limit
          internal static let infite = L10n.tr("Localizable", "appearance_setting_view.menu.title.infite", fallback: "No limit")
        }
      }
      internal enum Title {
        /// Prefer Japanese titles
        internal static let displaysJapaneseTitle = L10n.tr("Localizable", "appearance_setting_view.title.displays_japanese_title", fallback: "Prefer Japanese titles")
        /// Tags to show
        internal static let maximumNumberOfTags = L10n.tr("Localizable", "appearance_setting_view.title.maximum_number_of_tags", fallback: "Tags to show")
        /// Show tags in lists
        internal static let showsTagsInList = L10n.tr("Localizable", "appearance_setting_view.title.shows_tags_in_list", fallback: "Show tags in lists")
        /// Theme
        internal static let theme = L10n.tr("Localizable", "appearance_setting_view.title.theme", fallback: "Theme")
      }
    }
    internal enum ArchivesView {
      internal enum Button {
        /// Send to H@H client
        internal static let downloadToHathClient = L10n.tr("Localizable", "archives_view.button.download_to_hath_client", fallback: "Send to H@H client")
      }
      internal enum Title {
        /// Archive
        internal static let archives = L10n.tr("Localizable", "archives_view.title.archives", fallback: "Archive")
      }
    }
    internal enum CommentsView {
      internal enum Title {
        /// Comments
        internal static let comments = L10n.tr("Localizable", "comments_view.title.comments", fallback: "Comments")
      }
    }
    internal enum Common {
      /// Back
      internal static let back = L10n.tr("Localizable", "common.back", fallback: "Back")
      /// Cancel
      internal static let cancel = L10n.tr("Localizable", "common.cancel", fallback: "Cancel")
      /// Close
      internal static let close = L10n.tr("Localizable", "common.close", fallback: "Close")
      internal enum Value {
        /// %@ day
        internal static func day(_ p1: Any) -> String {
          return L10n.tr("Localizable", "common.value.day", String(describing: p1), fallback: "%@ day")
        }
        /// %@ days
        internal static func days(_ p1: Any) -> String {
          return L10n.tr("Localizable", "common.value.days", String(describing: p1), fallback: "%@ days")
        }
        /// %@ hour
        internal static func hour(_ p1: Any) -> String {
          return L10n.tr("Localizable", "common.value.hour", String(describing: p1), fallback: "%@ hour")
        }
        /// %@ hours
        internal static func hours(_ p1: Any) -> String {
          return L10n.tr("Localizable", "common.value.hours", String(describing: p1), fallback: "%@ hours")
        }
        /// %@ minute
        internal static func minute(_ p1: Any) -> String {
          return L10n.tr("Localizable", "common.value.minute", String(describing: p1), fallback: "%@ minute")
        }
        /// %@ minutes
        internal static func minutes(_ p1: Any) -> String {
          return L10n.tr("Localizable", "common.value.minutes", String(describing: p1), fallback: "%@ minutes")
        }
        /// %@ pages
        internal static func pages(_ p1: Any) -> String {
          return L10n.tr("Localizable", "common.value.pages", String(describing: p1), fallback: "%@ pages")
        }
        /// %@ entries
        internal static func records(_ p1: Any) -> String {
          return L10n.tr("Localizable", "common.value.records", String(describing: p1), fallback: "%@ entries")
        }
        /// %@ second
        internal static func second(_ p1: Any) -> String {
          return L10n.tr("Localizable", "common.value.second", String(describing: p1), fallback: "%@ second")
        }
        /// %@ seconds
        internal static func seconds(_ p1: Any) -> String {
          return L10n.tr("Localizable", "common.value.seconds", String(describing: p1), fallback: "%@ seconds")
        }
        /// %@ stars
        internal static func stars(_ p1: Any) -> String {
          return L10n.tr("Localizable", "common.value.stars", String(describing: p1), fallback: "%@ stars")
        }
        /// %@ times
        internal static func times(_ p1: Any) -> String {
          return L10n.tr("Localizable", "common.value.times", String(describing: p1), fallback: "%@ times")
        }
      }
    }
    internal enum ConfirmationDialog {
      internal enum Button {
        /// Clear
        internal static let clear = L10n.tr("Localizable", "confirmation_dialog.button.clear", fallback: "Clear")
        /// Delete
        internal static let delete = L10n.tr("Localizable", "confirmation_dialog.button.delete", fallback: "Delete")
        /// Delete database
        internal static let dropDatabase = L10n.tr("Localizable", "confirmation_dialog.button.drop_database", fallback: "Delete database")
        /// Sign out
        internal static let logout = L10n.tr("Localizable", "confirmation_dialog.button.logout", fallback: "Sign out")
        /// Remove
        internal static let remove = L10n.tr("Localizable", "confirmation_dialog.button.remove", fallback: "Remove")
        /// Reset
        internal static let reset = L10n.tr("Localizable", "confirmation_dialog.button.reset", fallback: "Reset")
      }
      internal enum Title {
        /// Clear everything here? This can't be undone.
        internal static let clear = L10n.tr("Localizable", "confirmation_dialog.title.clear", fallback: "Clear everything here? This can't be undone.")
        /// Delete this? It can't be undone.
        internal static let delete = L10n.tr("Localizable", "confirmation_dialog.title.delete", fallback: "Delete this? It can't be undone.")
        /// Everything EhShoko has stored will be erased.
        /// Delete the database?
        internal static let dropDatabase = L10n.tr("Localizable", "confirmation_dialog.title.drop_database", fallback: "Everything EhShoko has stored will be erased.\nDelete the database?")
        /// Sign out of your account?
        internal static let logout = L10n.tr("Localizable", "confirmation_dialog.title.logout", fallback: "Sign out of your account?")
        /// Remove the translations you imported?
        internal static let removeCustomTranslations = L10n.tr("Localizable", "confirmation_dialog.title.remove_custom_translations", fallback: "Remove the translations you imported?")
        /// Reset all filters to their defaults?
        internal static let reset = L10n.tr("Localizable", "confirmation_dialog.title.reset", fallback: "Reset all filters to their defaults?")
      }
    }
    internal enum DetailView {
      internal enum ActionSection {
        internal enum Button {
          /// Rate
          internal static let giveARating = L10n.tr("Localizable", "detail_view.action_section.button.give_a_rating", fallback: "Rate")
        }
      }
      internal enum ContextMenu {
        internal enum Button {
          /// Tag details
          internal static let detail = L10n.tr("Localizable", "detail_view.context_menu.button.detail", fallback: "Tag details")
          /// Vote down
          internal static let voteDown = L10n.tr("Localizable", "detail_view.context_menu.button.vote_down", fallback: "Vote down")
          /// Vote up
          internal static let voteUp = L10n.tr("Localizable", "detail_view.context_menu.button.vote_up", fallback: "Vote up")
          /// Remove vote
          internal static let withdrawVote = L10n.tr("Localizable", "detail_view.context_menu.button.withdraw_vote", fallback: "Remove vote")
        }
      }
      internal enum Section {
        internal enum Title {
          /// Comments
          internal static let comments = L10n.tr("Localizable", "detail_view.section.title.comments", fallback: "Comments")
        }
      }
      internal enum ToolbarItem {
        internal enum Button {
          /// Share
          internal static let share = L10n.tr("Localizable", "detail_view.toolbar_item.button.share", fallback: "Share")
        }
      }
    }
    internal enum EhSettingView {
      internal enum Button {
        /// New profile
        internal static let createNew = L10n.tr("Localizable", "eh_setting_view.button.create_new", fallback: "New profile")
        /// Delete profile
        internal static let deleteProfile = L10n.tr("Localizable", "eh_setting_view.button.delete_profile", fallback: "Delete profile")
        /// Rename
        internal static let rename = L10n.tr("Localizable", "eh_setting_view.button.rename", fallback: "Rename")
        /// Make default
        internal static let setAsDefault = L10n.tr("Localizable", "eh_setting_view.button.set_as_default", fallback: "Make default")
      }
      internal enum Description {
        /// By default, the Archiver asks you to confirm the cost and choose original or resampled, then gives you a link to download. You can change that here.
        internal static let archiverBehavior = L10n.tr("Localizable", "eh_setting_view.description.archiver_behavior", fallback: "By default, the Archiver asks you to confirm the cost and choose original or resampled, then gives you a link to download. You can change that here.")
        /// The site thinks you're browsing from **%@** (or through a VPN or proxy there), so it loads images from H@H clients in that region. If that's wrong, or you'd rather use another region (with a split-tunnel VPN, for example), choose a country below.
        internal static func browsingCountry(_ p1: Any) -> String {
          return L10n.tr("Localizable", "eh_setting_view.description.browsing_country", String(describing: p1), fallback: "The site thinks you're browsing from **%@** (or through a VPN or proxy there), so it loads images from H@H clients in that region. If that's wrong, or you'd rather use another region (with a split-tunnel VPN, for example), choose a country below.")
        }
        /// In the Thumbnail and Extended layouts, covers can be shown at 75%% to 150%% of their size.
        internal static let coverScaleFactor = L10n.tr("Localizable", "eh_setting_view.description.cover_scale_factor", fallback: "In the Thumbnail and Extended layouts, covers can be shown at 75%% to 150%% of their size.")
        /// The layout the site uses for the frontpage and search results.
        internal static let displayMode = L10n.tr("Localizable", "eh_setting_view.description.display_mode", fallback: "The layout the site uses for the frontpage and search results.")
        /// Galleries in the languages you select here are hidden from lists and searches, whatever you search for.
        internal static let excludedLanguages = L10n.tr("Localizable", "eh_setting_view.description.excluded_languages", fallback: "Galleries in the languages you select here are hidden from lists and searches, whatever you search for.")
        /// Galleries from the uploaders listed here are hidden from lists and searches, whatever you search for. Enter one username per line.
        internal static let excludedUploaders = L10n.tr("Localizable", "eh_setting_view.description.excluded_uploaders", fallback: "Galleries from the uploaders listed here are hidden from lists and searches, whatever you search for. Enter one username per line.")
        /// **%@ of %@** slots used.
        internal static func excludedUploadersCount(_ p1: Any, _ p2: Any) -> String {
          return L10n.tr("Localizable", "eh_setting_view.description.excluded_uploaders_count", String(describing: p1), String(describing: p2), fallback: "**%@ of %@** slots used.")
        }
        /// Rename your favorites folders here.
        internal static let favoriteCategories = L10n.tr("Localizable", "eh_setting_view.description.favorite_categories", fallback: "Rename your favorites folders here.")
        /// The default order of galleries in your favorites. Favorites added before March 2016 have no saved date, so they're ordered by posting date whatever you choose.
        internal static let favoritesSortOrder = L10n.tr("Localizable", "eh_setting_view.description.favorites_sort_order", fallback: "The default order of galleries in your favorites. Favorites added before March 2016 have no saved date, so they're ordered by posting date whatever you choose.")
        /// Show a line saying how many galleries your default filters removed from a page.
        internal static let filteredRemovalCount = L10n.tr("Localizable", "eh_setting_view.description.filtered_removal_count", fallback: "Show a line saying how many galleries your default filters removed from a page.")
        /// Choose the categories the frontpage and searches show by default. Dimmed ones are hidden.
        internal static let galleryCategory = L10n.tr("Localizable", "eh_setting_view.description.gallery_category", fallback: "Choose the categories the frontpage and searches show by default. Dimmed ones are hidden.")
        /// Many galleries have one title in English or romaji and another in Japanese. Choose which one to show by default.
        internal static let galleryName = L10n.tr("Localizable", "eh_setting_view.description.gallery_name", fallback: "Many galleries have one title in English or romaji and another in Japanese. Choose which one to show by default.")
        /// Images are normally resized to 1280 pixels wide for viewing. You can choose another width here. For now, widths above 1280 are limited to donors, Hath Perk holders and accounts with a user ID below 3,000,000.
        internal static let imageResolution = L10n.tr("Localizable", "eh_setting_view.description.image_resolution", fallback: "Images are normally resized to 1280 pixels wide for viewing. You can choose another width here. For now, widths above 1280 are limited to donors, Hath Perk holders and accounts with a user ID below 3,000,000.")
        /// The site already shrinks images to fit your screen. You can also cap how large an image is shown; the image itself isn't resampled. Use 0 for no limit.
        internal static let imageSize = L10n.tr("Localizable", "eh_setting_view.description.image_size", fallback: "The site already shrinks images to fit your screen. You can also cap how large an image is shown; the image itself isn't resampled. Use 0 for no limit.")
        /// Use this if an H@H client runs on your local network behind the same public IP you browse from, and your router can't route requests back to its own address.
        /// If the client runs on the device you browse with, enter the loopback address (127.0.0.1:port). If it runs on another device on your network, enter that device's local IP address. Some browsers block sites from opening local addresses; you may need to allow the site for this to work.
        internal static let ipAddressPort = L10n.tr("Localizable", "eh_setting_view.description.ip_address_port", fallback: "Use this if an H@H client runs on your local network behind the same public IP you browse from, and your router can't route requests back to its own address.\nIf the client runs on the device you browse with, enter the loopback address (127.0.0.1:port). If it runs on another device on your network, enter that device's local IP address. Some browsers block sites from opening local addresses; you may need to allow the site for this to work.")
        /// Some older parts of the site's interface are off by default. You can turn them on here.
        internal static let optionalUIElements = L10n.tr("Localizable", "eh_setting_view.description.optional_UI_elements", fallback: "Some older parts of the site's interface are off by default. You can turn them on here.")
        /// Stars on galleries you've rated are colored: by default red for 2 stars or fewer, green for 2.5 to 4 and blue for 4.5 or 5. To change this, enter five letters, one per star: R (red), G (green), B (blue) or Y (yellow). The default, RRGGB, makes stars 1 and 2 red, 3 and 4 green and 5 blue.
        internal static let ratingsColor = L10n.tr("Localizable", "eh_setting_view.description.ratings_color", fallback: "Stars on galleries you've rated are colored: by default red for 2 stars or fewer, green for 2.5 to 4 and blue for 4.5 or 5. To change this, enter five letters, one per star: R (red), G (green), B (blue) or Y (yellow). The default, RRGGB, makes stars 1 and 2 red, 3 and 4 green and 5 blue.")
        /// How many results each page shows on the frontpage, in searches and in torrent searches.
        /// (Needs the Paging Enlargement Hath Perk.)
        internal static let resultCount = L10n.tr("Localizable", "eh_setting_view.description.result_count", fallback: "How many results each page shows on the frontpage, in searches and in torrent searches.\n(Needs the Paging Enlargement Hath Perk.)")
        /// Tags you add to My Tags with a negative weight count against a gallery. When a gallery's total falls below this number, it's hidden. Enter a value from 0 to -9999.
        internal static let tagFilteringThreshold = L10n.tr("Localizable", "eh_setting_view.description.tag_filtering_threshold", fallback: "Tags you add to My Tags with a negative weight count against a gallery. When a gallery's total falls below this number, it's hidden. Enter a value from 0 to -9999.")
        /// A new gallery shows up in Watched when at least one of its watched tags has a positive weight and the weights of its watched tags add up to this number or more. Enter a value from 0 to 9999.
        internal static let tagWatchingThreshold = L10n.tr("Localizable", "eh_setting_view.description.tag_watching_threshold", fallback: "A new gallery shows up in Watched when at least one of its watched tags has a positive weight and the weights of its watched tags add up to this number or more. Enter a value from 0 to 9999.")
        /// The thumbnail size and number of rows used for every gallery you open.
        internal static let thumbnailConfiguration = L10n.tr("Localizable", "eh_setting_view.description.thumbnail_configuration", fallback: "The thumbnail size and number of rows used for every gallery you open.")
        /// When the site loads the thumbnails that pop up on hover in its list view.
        internal static let thumbnailLoadTiming = L10n.tr("Localizable", "eh_setting_view.description.thumbnail_load_timing", fallback: "When the site loads the thumbnails that pop up on hover in its list view.")
        /// Sets the width the site lays out its pages for on phones and tablets, which your device normally picks from its screen density. At a thumbnail scale of 100%%, 640 to 1400 works well.
        internal static let virtualWidth = L10n.tr("Localizable", "eh_setting_view.description.virtual_width", fallback: "Sets the width the site lays out its pages for on phones and tablets, which your device normally picks from its screen density. At a thumbnail scale of 100%%, 640 to 1400 works well.")
      }
      internal enum Promt {
        /// RRGGB
        internal static let ratingsColor = L10n.tr("Localizable", "eh_setting_view.promt.ratings_color", fallback: "RRGGB")
      }
      internal enum Section {
        internal enum Title {
          /// Archiver
          internal static let archiverSettings = L10n.tr("Localizable", "eh_setting_view.section.title.archiver_settings", fallback: "Archiver")
          /// Cover size
          internal static let coverScaling = L10n.tr("Localizable", "eh_setting_view.section.title.cover_scaling", fallback: "Cover size")
          /// Hidden languages
          internal static let excludedLanguages = L10n.tr("Localizable", "eh_setting_view.section.title.excluded_languages", fallback: "Hidden languages")
          /// Hidden uploaders
          internal static let excludedUploaders = L10n.tr("Localizable", "eh_setting_view.section.title.excluded_uploaders", fallback: "Hidden uploaders")
          /// Favorites
          internal static let favorites = L10n.tr("Localizable", "eh_setting_view.section.title.favorites", fallback: "Favorites")
          /// Filtered count
          internal static let filteredRemovalCount = L10n.tr("Localizable", "eh_setting_view.section.title.filtered_removal_count", fallback: "Filtered count")
          /// Frontpage and search
          internal static let frontPageSettings = L10n.tr("Localizable", "eh_setting_view.section.title.front_page_settings", fallback: "Frontpage and search")
          /// Comments
          internal static let galleryComments = L10n.tr("Localizable", "eh_setting_view.section.title.gallery_comments", fallback: "Comments")
          /// Gallery titles
          internal static let galleryNameDisplay = L10n.tr("Localizable", "eh_setting_view.section.title.gallery_name_display", fallback: "Gallery titles")
          /// Thumbnail labels
          internal static let galleryPageThumbnailLabeling = L10n.tr("Localizable", "eh_setting_view.section.title.gallery_page_thumbnail_labeling", fallback: "Thumbnail labels")
          /// Tags
          internal static let galleryTags = L10n.tr("Localizable", "eh_setting_view.section.title.gallery_tags", fallback: "Tags")
          /// H@H client on your network
          internal static let hathLocalNetworkHost = L10n.tr("Localizable", "eh_setting_view.section.title.hath_local_network_host", fallback: "H@H client on your network")
          /// Image loading
          internal static let imageLoadSettings = L10n.tr("Localizable", "eh_setting_view.section.title.image_load_settings", fallback: "Image loading")
          /// Image size
          internal static let imageSizeSettings = L10n.tr("Localizable", "eh_setting_view.section.title.image_size_settings", fallback: "Image size")
          /// Multi-page viewer
          internal static let multiPageViewer = L10n.tr("Localizable", "eh_setting_view.section.title.multi_page_viewer", fallback: "Multi-page viewer")
          /// Optional elements
          internal static let optionalUIElements = L10n.tr("Localizable", "eh_setting_view.section.title.optional_UI_elements", fallback: "Optional elements")
          /// Load the original files instead of resampled copies. A resampled copy is still used when you've chosen a width other than Automatic above and the image is wider, or when the original is over 10 MiB (4 MiB in galleries older than a year).
          internal static let originalImages = L10n.tr("Localizable", "eh_setting_view.section.title.original_images", fallback: "Load the original files instead of resampled copies. A resampled copy is still used when you've chosen a width other than Automatic above and the image is wider, or when the original is over 10 MiB (4 MiB in galleries older than a year).")
          /// Profiles
          internal static let profileSettings = L10n.tr("Localizable", "eh_setting_view.section.title.profile_settings", fallback: "Profiles")
          /// Ratings
          internal static let ratings = L10n.tr("Localizable", "eh_setting_view.section.title.ratings", fallback: "Ratings")
          /// Results per page
          internal static let searchResultCount = L10n.tr("Localizable", "eh_setting_view.section.title.search_result_count", fallback: "Results per page")
          /// Result range
          internal static let showSearchRangeIndicator = L10n.tr("Localizable", "eh_setting_view.section.title.show_search_range_indicator", fallback: "Result range")
          /// Tag filter threshold
          internal static let tagFilteringThreshold = L10n.tr("Localizable", "eh_setting_view.section.title.tag_filtering_threshold", fallback: "Tag filter threshold")
          /// Tag watch threshold
          internal static let tagWatchingThreshold = L10n.tr("Localizable", "eh_setting_view.section.title.tag_watching_threshold", fallback: "Tag watch threshold")
          /// Thumbnails
          internal static let thumbnailSettings = L10n.tr("Localizable", "eh_setting_view.section.title.thumbnail_settings", fallback: "Thumbnails")
          /// Page width
          internal static let viewportOverride = L10n.tr("Localizable", "eh_setting_view.section.title.viewport_override", fallback: "Page width")
        }
      }
      internal enum Title {
        /// Behavior
        internal static let archiverBehavior = L10n.tr("Localizable", "eh_setting_view.title.archiver_behavior", fallback: "Behavior")
        /// Country or region
        internal static let browsingCountry = L10n.tr("Localizable", "eh_setting_view.title.browsing_country", fallback: "Country or region")
        /// Sort comments
        internal static let commentsSortOrder = L10n.tr("Localizable", "eh_setting_view.title.comments_sort_order", fallback: "Sort comments")
        /// Show votes
        internal static let commentsVotesShowTiming = L10n.tr("Localizable", "eh_setting_view.title.comments_votes_show_timing", fallback: "Show votes")
        /// Layout
        internal static let displayMode = L10n.tr("Localizable", "eh_setting_view.title.display_mode", fallback: "Layout")
        /// Layout
        internal static let displayStyle = L10n.tr("Localizable", "eh_setting_view.title.display_style", fallback: "Layout")
        /// Show the thumbnail selector on gallery pages
        internal static let enableGalleryThumbnailSelector = L10n.tr("Localizable", "eh_setting_view.title.enable_gallery_thumbnail_selector", fallback: "Show the thumbnail selector on gallery pages")
        /// Sort order
        internal static let favoritesSortOrder = L10n.tr("Localizable", "eh_setting_view.title.favorites_sort_order", fallback: "Sort order")
        /// Title
        internal static let galleryName = L10n.tr("Localizable", "eh_setting_view.title.gallery_name", fallback: "Title")
        /// Width
        internal static let horizontal = L10n.tr("Localizable", "eh_setting_view.title.horizontal", fallback: "Width")
        /// Settings on %@
        internal static func hostSettings(_ p1: Any) -> String {
          return L10n.tr("Localizable", "eh_setting_view.title.host_settings", String(describing: p1), fallback: "Settings on %@")
        }
        /// Resolution
        internal static let imageResolution = L10n.tr("Localizable", "eh_setting_view.title.image_resolution", fallback: "Resolution")
        /// Maximum size
        internal static let imageSize = L10n.tr("Localizable", "eh_setting_view.title.image_size", fallback: "Maximum size")
        /// IP address and port
        internal static let ipAddressPort = L10n.tr("Localizable", "eh_setting_view.title.ip_address_port", fallback: "IP address and port")
        /// Load images through H@H
        internal static let loadImagesThroughTheHathNetwork = L10n.tr("Localizable", "eh_setting_view.title.load_images_through_the_hath_network", fallback: "Load images through H@H")
        /// Star colors
        internal static let ratingsColor = L10n.tr("Localizable", "eh_setting_view.title.ratings_color", fallback: "Star colors")
        /// Results
        internal static let resultCount = L10n.tr("Localizable", "eh_setting_view.title.result_count", fallback: "Results")
        /// Scale
        internal static let scaleFactor = L10n.tr("Localizable", "eh_setting_view.title.scale_factor", fallback: "Scale")
        /// Profile in use
        internal static let selectedProfile = L10n.tr("Localizable", "eh_setting_view.title.selected_profile", fallback: "Profile in use")
        /// Show filtered count
        internal static let showFilteredRemovalCount = L10n.tr("Localizable", "eh_setting_view.title.show_filtered_removal_count", fallback: "Show filtered count")
        /// Labels
        internal static let showLabelBelowGalleryThumbnails = L10n.tr("Localizable", "eh_setting_view.title.show_label_below_gallery_thumbnails", fallback: "Labels")
        /// Show the result range
        internal static let showSearchRangeIndicator = L10n.tr("Localizable", "eh_setting_view.title.show_search_range_indicator", fallback: "Show the result range")
        /// Show the thumbnail pane
        internal static let showThumbnailPane = L10n.tr("Localizable", "eh_setting_view.title.show_thumbnail_pane", fallback: "Show the thumbnail pane")
        /// Threshold
        internal static let tagFilteringThreshold = L10n.tr("Localizable", "eh_setting_view.title.tag_filtering_threshold", fallback: "Threshold")
        /// Threshold
        internal static let tagWatchingThreshold = L10n.tr("Localizable", "eh_setting_view.title.tag_watching_threshold", fallback: "Threshold")
        /// Sort tags
        internal static let tagsSortOrder = L10n.tr("Localizable", "eh_setting_view.title.tags_sort_order", fallback: "Sort tags")
        /// Load thumbnails
        internal static let thumbnailLoadTiming = L10n.tr("Localizable", "eh_setting_view.title.thumbnail_load_timing", fallback: "Load thumbnails")
        /// Rows
        internal static let thumbnailRowCount = L10n.tr("Localizable", "eh_setting_view.title.thumbnail_row_count", fallback: "Rows")
        /// Size
        internal static let thumbnailSize = L10n.tr("Localizable", "eh_setting_view.title.thumbnail_size", fallback: "Size")
        /// Use the multi-page viewer
        internal static let useMultiPageViewer = L10n.tr("Localizable", "eh_setting_view.title.use_multi_page_viewer", fallback: "Use the multi-page viewer")
        /// Use original images
        internal static let useOriginalImages = L10n.tr("Localizable", "eh_setting_view.title.use_original_images", fallback: "Use original images")
        /// Height
        internal static let vertical = L10n.tr("Localizable", "eh_setting_view.title.vertical", fallback: "Height")
        /// Width
        internal static let virtualWidth = L10n.tr("Localizable", "eh_setting_view.title.virtual_width", fallback: "Width")
      }
      internal enum ToolbarItem {
        internal enum Button {
          /// Done
          internal static let done = L10n.tr("Localizable", "eh_setting_view.toolbar_item.button.done", fallback: "Done")
        }
      }
    }
    internal enum Enum {
      internal enum AppIconType {
        internal enum Value {
          /// Default
          internal static let `default` = L10n.tr("Localizable", "enum.app_icon_type.value.default", fallback: "Default")
          /// Developer
          internal static let developer = L10n.tr("Localizable", "enum.app_icon_type.value.developer", fallback: "Developer")
          /// NOT MY PRESIDENT
          internal static let notMyPresident = L10n.tr("Localizable", "enum.app_icon_type.value.not_my_president", fallback: "NOT MY PRESIDENT")
          /// Stand with Ukraine (2022)
          internal static let standWithUkraine2022 = L10n.tr("Localizable", "enum.app_icon_type.value.stand_with_ukraine_2022", fallback: "Stand with Ukraine (2022)")
          /// Ukiyo-e
          internal static let ukiyoe = L10n.tr("Localizable", "enum.app_icon_type.value.ukiyoe", fallback: "Ukiyo-e")
        }
      }
      internal enum ArchiveResolution {
        internal enum Value {
          /// Original
          internal static let original = L10n.tr("Localizable", "enum.archive_resolution.value.original", fallback: "Original")
        }
      }
      internal enum AutoLockPolicy {
        internal enum Value {
          /// Immediately
          internal static let instantly = L10n.tr("Localizable", "enum.auto_lock_policy.value.instantly", fallback: "Immediately")
          /// Never
          internal static let never = L10n.tr("Localizable", "enum.auto_lock_policy.value.never", fallback: "Never")
        }
      }
      internal enum AutoPlayPolicy {
        internal enum Value {
          /// Off
          internal static let off = L10n.tr("Localizable", "enum.auto_play_policy.value.off", fallback: "Off")
        }
      }
      internal enum BanInterval {
        internal enum Description {
          /// Localizable.strings
          ///   EhShoko
          internal static let and = L10n.tr("Localizable", "enum.ban_interval.description.and", fallback: "and")
        }
      }
      internal enum BrowsingCountry {
        internal enum Name {
          /// Afghanistan
          internal static let afghanistan = L10n.tr("Localizable", "enum.browsing_country.name.afghanistan", fallback: "Afghanistan")
          /// Åland Islands
          internal static let alandIslands = L10n.tr("Localizable", "enum.browsing_country.name.aland_islands", fallback: "Åland Islands")
          /// Albania
          internal static let albania = L10n.tr("Localizable", "enum.browsing_country.name.albania", fallback: "Albania")
          /// Algeria
          internal static let algeria = L10n.tr("Localizable", "enum.browsing_country.name.algeria", fallback: "Algeria")
          /// American Samoa
          internal static let americanSamoa = L10n.tr("Localizable", "enum.browsing_country.name.american_samoa", fallback: "American Samoa")
          /// Andorra
          internal static let andorra = L10n.tr("Localizable", "enum.browsing_country.name.andorra", fallback: "Andorra")
          /// Angola
          internal static let angola = L10n.tr("Localizable", "enum.browsing_country.name.angola", fallback: "Angola")
          /// Anguilla
          internal static let anguilla = L10n.tr("Localizable", "enum.browsing_country.name.anguilla", fallback: "Anguilla")
          /// Antarctica
          internal static let antarctica = L10n.tr("Localizable", "enum.browsing_country.name.antarctica", fallback: "Antarctica")
          /// Antigua & Barbuda
          internal static let antiguaAndBarbuda = L10n.tr("Localizable", "enum.browsing_country.name.antigua_and_barbuda", fallback: "Antigua & Barbuda")
          /// Argentina
          internal static let argentina = L10n.tr("Localizable", "enum.browsing_country.name.argentina", fallback: "Argentina")
          /// Armenia
          internal static let armenia = L10n.tr("Localizable", "enum.browsing_country.name.armenia", fallback: "Armenia")
          /// Aruba
          internal static let aruba = L10n.tr("Localizable", "enum.browsing_country.name.aruba", fallback: "Aruba")
          /// Asia-Pacific
          internal static let asiaPacificRegion = L10n.tr("Localizable", "enum.browsing_country.name.asia_pacific_region", fallback: "Asia-Pacific")
          /// Australia
          internal static let australia = L10n.tr("Localizable", "enum.browsing_country.name.australia", fallback: "Australia")
          /// Austria
          internal static let austria = L10n.tr("Localizable", "enum.browsing_country.name.austria", fallback: "Austria")
          /// Automatic
          internal static let autoDetect = L10n.tr("Localizable", "enum.browsing_country.name.auto_detect", fallback: "Automatic")
          /// Azerbaijan
          internal static let azerbaijan = L10n.tr("Localizable", "enum.browsing_country.name.azerbaijan", fallback: "Azerbaijan")
          /// Bahamas
          internal static let bahamas = L10n.tr("Localizable", "enum.browsing_country.name.bahamas", fallback: "Bahamas")
          /// Bahrain
          internal static let bahrain = L10n.tr("Localizable", "enum.browsing_country.name.bahrain", fallback: "Bahrain")
          /// Bangladesh
          internal static let bangladesh = L10n.tr("Localizable", "enum.browsing_country.name.bangladesh", fallback: "Bangladesh")
          /// Barbados
          internal static let barbados = L10n.tr("Localizable", "enum.browsing_country.name.barbados", fallback: "Barbados")
          /// Belarus
          internal static let belarus = L10n.tr("Localizable", "enum.browsing_country.name.belarus", fallback: "Belarus")
          /// Belgium
          internal static let belgium = L10n.tr("Localizable", "enum.browsing_country.name.belgium", fallback: "Belgium")
          /// Belize
          internal static let belize = L10n.tr("Localizable", "enum.browsing_country.name.belize", fallback: "Belize")
          /// Benin
          internal static let benin = L10n.tr("Localizable", "enum.browsing_country.name.benin", fallback: "Benin")
          /// Bermuda
          internal static let bermuda = L10n.tr("Localizable", "enum.browsing_country.name.bermuda", fallback: "Bermuda")
          /// Bhutan
          internal static let bhutan = L10n.tr("Localizable", "enum.browsing_country.name.bhutan", fallback: "Bhutan")
          /// Bolivia
          internal static let bolivia = L10n.tr("Localizable", "enum.browsing_country.name.bolivia", fallback: "Bolivia")
          /// Caribbean Netherlands
          internal static let bonaireSaintEustatiusAndSaba = L10n.tr("Localizable", "enum.browsing_country.name.bonaire_saint_eustatius_and_saba", fallback: "Caribbean Netherlands")
          /// Bosnia & Herzegovina
          internal static let bosniaAndHerzegovina = L10n.tr("Localizable", "enum.browsing_country.name.bosnia_and_herzegovina", fallback: "Bosnia & Herzegovina")
          /// Botswana
          internal static let botswana = L10n.tr("Localizable", "enum.browsing_country.name.botswana", fallback: "Botswana")
          /// Bouvet Island
          internal static let bouvetIsland = L10n.tr("Localizable", "enum.browsing_country.name.bouvet_island", fallback: "Bouvet Island")
          /// Brazil
          internal static let brazil = L10n.tr("Localizable", "enum.browsing_country.name.brazil", fallback: "Brazil")
          /// Chagos Archipelago
          internal static let britishIndianOceanTerritory = L10n.tr("Localizable", "enum.browsing_country.name.british_indian_ocean_territory", fallback: "Chagos Archipelago")
          /// Brunei
          internal static let bruneiDarussalam = L10n.tr("Localizable", "enum.browsing_country.name.brunei_darussalam", fallback: "Brunei")
          /// Bulgaria
          internal static let bulgaria = L10n.tr("Localizable", "enum.browsing_country.name.bulgaria", fallback: "Bulgaria")
          /// Burkina Faso
          internal static let burkinaFaso = L10n.tr("Localizable", "enum.browsing_country.name.burkina_faso", fallback: "Burkina Faso")
          /// Burundi
          internal static let burundi = L10n.tr("Localizable", "enum.browsing_country.name.burundi", fallback: "Burundi")
          /// Cambodia
          internal static let cambodia = L10n.tr("Localizable", "enum.browsing_country.name.cambodia", fallback: "Cambodia")
          /// Cameroon
          internal static let cameroon = L10n.tr("Localizable", "enum.browsing_country.name.cameroon", fallback: "Cameroon")
          /// Canada
          internal static let canada = L10n.tr("Localizable", "enum.browsing_country.name.canada", fallback: "Canada")
          /// Cape Verde
          internal static let capeVerde = L10n.tr("Localizable", "enum.browsing_country.name.cape_verde", fallback: "Cape Verde")
          /// Cayman Islands
          internal static let caymanIslands = L10n.tr("Localizable", "enum.browsing_country.name.cayman_islands", fallback: "Cayman Islands")
          /// Central African Republic
          internal static let centralAfricanRepublic = L10n.tr("Localizable", "enum.browsing_country.name.central_african_republic", fallback: "Central African Republic")
          /// Chad
          internal static let chad = L10n.tr("Localizable", "enum.browsing_country.name.chad", fallback: "Chad")
          /// Chile
          internal static let chile = L10n.tr("Localizable", "enum.browsing_country.name.chile", fallback: "Chile")
          /// China mainland
          internal static let china = L10n.tr("Localizable", "enum.browsing_country.name.china", fallback: "China mainland")
          /// Christmas Island
          internal static let christmasIsland = L10n.tr("Localizable", "enum.browsing_country.name.christmas_island", fallback: "Christmas Island")
          /// Cocos (Keeling) Islands
          internal static let cocosIslands = L10n.tr("Localizable", "enum.browsing_country.name.cocos_islands", fallback: "Cocos (Keeling) Islands")
          /// Colombia
          internal static let colombia = L10n.tr("Localizable", "enum.browsing_country.name.colombia", fallback: "Colombia")
          /// Comoros
          internal static let comoros = L10n.tr("Localizable", "enum.browsing_country.name.comoros", fallback: "Comoros")
          /// Congo - Brazzaville
          internal static let congo = L10n.tr("Localizable", "enum.browsing_country.name.congo", fallback: "Congo - Brazzaville")
          /// Cook Islands
          internal static let cookIslands = L10n.tr("Localizable", "enum.browsing_country.name.cook_islands", fallback: "Cook Islands")
          /// Costa Rica
          internal static let costaRica = L10n.tr("Localizable", "enum.browsing_country.name.costa_rica", fallback: "Costa Rica")
          /// Côte d’Ivoire
          internal static let coteDIvoire = L10n.tr("Localizable", "enum.browsing_country.name.cote_d_ivoire", fallback: "Côte d’Ivoire")
          /// Croatia
          internal static let croatia = L10n.tr("Localizable", "enum.browsing_country.name.croatia", fallback: "Croatia")
          /// Cuba
          internal static let cuba = L10n.tr("Localizable", "enum.browsing_country.name.cuba", fallback: "Cuba")
          /// Curaçao
          internal static let curacao = L10n.tr("Localizable", "enum.browsing_country.name.curacao", fallback: "Curaçao")
          /// Cyprus
          internal static let cyprus = L10n.tr("Localizable", "enum.browsing_country.name.cyprus", fallback: "Cyprus")
          /// Czechia
          internal static let czechRepublic = L10n.tr("Localizable", "enum.browsing_country.name.czech_republic", fallback: "Czechia")
          /// Denmark
          internal static let denmark = L10n.tr("Localizable", "enum.browsing_country.name.denmark", fallback: "Denmark")
          /// Djibouti
          internal static let djibouti = L10n.tr("Localizable", "enum.browsing_country.name.djibouti", fallback: "Djibouti")
          /// Dominica
          internal static let dominica = L10n.tr("Localizable", "enum.browsing_country.name.dominica", fallback: "Dominica")
          /// Dominican Republic
          internal static let dominicanRepublic = L10n.tr("Localizable", "enum.browsing_country.name.dominican_republic", fallback: "Dominican Republic")
          /// Ecuador
          internal static let ecuador = L10n.tr("Localizable", "enum.browsing_country.name.ecuador", fallback: "Ecuador")
          /// Egypt
          internal static let egypt = L10n.tr("Localizable", "enum.browsing_country.name.egypt", fallback: "Egypt")
          /// El Salvador
          internal static let elSalvador = L10n.tr("Localizable", "enum.browsing_country.name.el_salvador", fallback: "El Salvador")
          /// Equatorial Guinea
          internal static let equatorialGuinea = L10n.tr("Localizable", "enum.browsing_country.name.equatorial_guinea", fallback: "Equatorial Guinea")
          /// Eritrea
          internal static let eritrea = L10n.tr("Localizable", "enum.browsing_country.name.eritrea", fallback: "Eritrea")
          /// Estonia
          internal static let estonia = L10n.tr("Localizable", "enum.browsing_country.name.estonia", fallback: "Estonia")
          /// Ethiopia
          internal static let ethiopia = L10n.tr("Localizable", "enum.browsing_country.name.ethiopia", fallback: "Ethiopia")
          /// Europe
          internal static let europe = L10n.tr("Localizable", "enum.browsing_country.name.europe", fallback: "Europe")
          /// Falkland Islands
          internal static let falklandIslands = L10n.tr("Localizable", "enum.browsing_country.name.falkland_islands", fallback: "Falkland Islands")
          /// Faroe Islands
          internal static let faroeIslands = L10n.tr("Localizable", "enum.browsing_country.name.faroe_islands", fallback: "Faroe Islands")
          /// Fiji
          internal static let fiji = L10n.tr("Localizable", "enum.browsing_country.name.fiji", fallback: "Fiji")
          /// Finland
          internal static let finland = L10n.tr("Localizable", "enum.browsing_country.name.finland", fallback: "Finland")
          /// France
          internal static let france = L10n.tr("Localizable", "enum.browsing_country.name.france", fallback: "France")
          /// French Guiana
          internal static let frenchGuiana = L10n.tr("Localizable", "enum.browsing_country.name.french_guiana", fallback: "French Guiana")
          /// French Polynesia
          internal static let frenchPolynesia = L10n.tr("Localizable", "enum.browsing_country.name.french_polynesia", fallback: "French Polynesia")
          /// French Southern Territories
          internal static let frenchSouthernTerritories = L10n.tr("Localizable", "enum.browsing_country.name.french_southern_territories", fallback: "French Southern Territories")
          /// Gabon
          internal static let gabon = L10n.tr("Localizable", "enum.browsing_country.name.gabon", fallback: "Gabon")
          /// Gambia
          internal static let gambia = L10n.tr("Localizable", "enum.browsing_country.name.gambia", fallback: "Gambia")
          /// Georgia
          internal static let georgia = L10n.tr("Localizable", "enum.browsing_country.name.georgia", fallback: "Georgia")
          /// Germany
          internal static let germany = L10n.tr("Localizable", "enum.browsing_country.name.germany", fallback: "Germany")
          /// Ghana
          internal static let ghana = L10n.tr("Localizable", "enum.browsing_country.name.ghana", fallback: "Ghana")
          /// Gibraltar
          internal static let gibraltar = L10n.tr("Localizable", "enum.browsing_country.name.gibraltar", fallback: "Gibraltar")
          /// Greece
          internal static let greece = L10n.tr("Localizable", "enum.browsing_country.name.greece", fallback: "Greece")
          /// Greenland
          internal static let greenland = L10n.tr("Localizable", "enum.browsing_country.name.greenland", fallback: "Greenland")
          /// Grenada
          internal static let grenada = L10n.tr("Localizable", "enum.browsing_country.name.grenada", fallback: "Grenada")
          /// Guadeloupe
          internal static let guadeloupe = L10n.tr("Localizable", "enum.browsing_country.name.guadeloupe", fallback: "Guadeloupe")
          /// Guam
          internal static let guam = L10n.tr("Localizable", "enum.browsing_country.name.guam", fallback: "Guam")
          /// Guatemala
          internal static let guatemala = L10n.tr("Localizable", "enum.browsing_country.name.guatemala", fallback: "Guatemala")
          /// Guernsey
          internal static let guernsey = L10n.tr("Localizable", "enum.browsing_country.name.guernsey", fallback: "Guernsey")
          /// Guinea
          internal static let guinea = L10n.tr("Localizable", "enum.browsing_country.name.guinea", fallback: "Guinea")
          /// Guinea-Bissau
          internal static let guineaBissau = L10n.tr("Localizable", "enum.browsing_country.name.guinea_bissau", fallback: "Guinea-Bissau")
          /// Guyana
          internal static let guyana = L10n.tr("Localizable", "enum.browsing_country.name.guyana", fallback: "Guyana")
          /// Haiti
          internal static let haiti = L10n.tr("Localizable", "enum.browsing_country.name.haiti", fallback: "Haiti")
          /// Heard & McDonald Islands
          internal static let heardIslandAndMcDonaldIslands = L10n.tr("Localizable", "enum.browsing_country.name.heard_island_and_mc_donald_islands", fallback: "Heard & McDonald Islands")
          /// Honduras
          internal static let honduras = L10n.tr("Localizable", "enum.browsing_country.name.honduras", fallback: "Honduras")
          /// Hong Kong
          internal static let hongKong = L10n.tr("Localizable", "enum.browsing_country.name.hong_kong", fallback: "Hong Kong")
          /// Hungary
          internal static let hungary = L10n.tr("Localizable", "enum.browsing_country.name.hungary", fallback: "Hungary")
          /// Iceland
          internal static let iceland = L10n.tr("Localizable", "enum.browsing_country.name.iceland", fallback: "Iceland")
          /// India
          internal static let india = L10n.tr("Localizable", "enum.browsing_country.name.india", fallback: "India")
          /// Indonesia
          internal static let indonesia = L10n.tr("Localizable", "enum.browsing_country.name.indonesia", fallback: "Indonesia")
          /// Iran
          internal static let iran = L10n.tr("Localizable", "enum.browsing_country.name.iran", fallback: "Iran")
          /// Iraq
          internal static let iraq = L10n.tr("Localizable", "enum.browsing_country.name.iraq", fallback: "Iraq")
          /// Ireland
          internal static let ireland = L10n.tr("Localizable", "enum.browsing_country.name.ireland", fallback: "Ireland")
          /// Isle of Man
          internal static let isleOfMan = L10n.tr("Localizable", "enum.browsing_country.name.isle_of_man", fallback: "Isle of Man")
          /// Israel
          internal static let israel = L10n.tr("Localizable", "enum.browsing_country.name.israel", fallback: "Israel")
          /// Italy
          internal static let italy = L10n.tr("Localizable", "enum.browsing_country.name.italy", fallback: "Italy")
          /// Jamaica
          internal static let jamaica = L10n.tr("Localizable", "enum.browsing_country.name.jamaica", fallback: "Jamaica")
          /// Japan
          internal static let japan = L10n.tr("Localizable", "enum.browsing_country.name.japan", fallback: "Japan")
          /// Jersey
          internal static let jersey = L10n.tr("Localizable", "enum.browsing_country.name.jersey", fallback: "Jersey")
          /// Jordan
          internal static let jordan = L10n.tr("Localizable", "enum.browsing_country.name.jordan", fallback: "Jordan")
          /// Kazakhstan
          internal static let kazakhstan = L10n.tr("Localizable", "enum.browsing_country.name.kazakhstan", fallback: "Kazakhstan")
          /// Kenya
          internal static let kenya = L10n.tr("Localizable", "enum.browsing_country.name.kenya", fallback: "Kenya")
          /// Kiribati
          internal static let kiribati = L10n.tr("Localizable", "enum.browsing_country.name.kiribati", fallback: "Kiribati")
          /// Kuwait
          internal static let kuwait = L10n.tr("Localizable", "enum.browsing_country.name.kuwait", fallback: "Kuwait")
          /// Kyrgyzstan
          internal static let kyrgyzstan = L10n.tr("Localizable", "enum.browsing_country.name.kyrgyzstan", fallback: "Kyrgyzstan")
          /// Laos
          internal static let laoPeoplesDemocraticRepublic = L10n.tr("Localizable", "enum.browsing_country.name.lao_peoples_democratic_republic", fallback: "Laos")
          /// Latvia
          internal static let latvia = L10n.tr("Localizable", "enum.browsing_country.name.latvia", fallback: "Latvia")
          /// Lebanon
          internal static let lebanon = L10n.tr("Localizable", "enum.browsing_country.name.lebanon", fallback: "Lebanon")
          /// Lesotho
          internal static let lesotho = L10n.tr("Localizable", "enum.browsing_country.name.lesotho", fallback: "Lesotho")
          /// Liberia
          internal static let liberia = L10n.tr("Localizable", "enum.browsing_country.name.liberia", fallback: "Liberia")
          /// Libya
          internal static let libya = L10n.tr("Localizable", "enum.browsing_country.name.libya", fallback: "Libya")
          /// Liechtenstein
          internal static let liechtenstein = L10n.tr("Localizable", "enum.browsing_country.name.liechtenstein", fallback: "Liechtenstein")
          /// Lithuania
          internal static let lithuania = L10n.tr("Localizable", "enum.browsing_country.name.lithuania", fallback: "Lithuania")
          /// Luxembourg
          internal static let luxembourg = L10n.tr("Localizable", "enum.browsing_country.name.luxembourg", fallback: "Luxembourg")
          /// Macao
          internal static let macau = L10n.tr("Localizable", "enum.browsing_country.name.macau", fallback: "Macao")
          /// North Macedonia
          internal static let macedonia = L10n.tr("Localizable", "enum.browsing_country.name.macedonia", fallback: "North Macedonia")
          /// Madagascar
          internal static let madagascar = L10n.tr("Localizable", "enum.browsing_country.name.madagascar", fallback: "Madagascar")
          /// Malawi
          internal static let malawi = L10n.tr("Localizable", "enum.browsing_country.name.malawi", fallback: "Malawi")
          /// Malaysia
          internal static let malaysia = L10n.tr("Localizable", "enum.browsing_country.name.malaysia", fallback: "Malaysia")
          /// Maldives
          internal static let maldives = L10n.tr("Localizable", "enum.browsing_country.name.maldives", fallback: "Maldives")
          /// Mali
          internal static let mali = L10n.tr("Localizable", "enum.browsing_country.name.mali", fallback: "Mali")
          /// Malta
          internal static let malta = L10n.tr("Localizable", "enum.browsing_country.name.malta", fallback: "Malta")
          /// Marshall Islands
          internal static let marshallIslands = L10n.tr("Localizable", "enum.browsing_country.name.marshall_islands", fallback: "Marshall Islands")
          /// Martinique
          internal static let martinique = L10n.tr("Localizable", "enum.browsing_country.name.martinique", fallback: "Martinique")
          /// Mauritania
          internal static let mauritania = L10n.tr("Localizable", "enum.browsing_country.name.mauritania", fallback: "Mauritania")
          /// Mauritius
          internal static let mauritius = L10n.tr("Localizable", "enum.browsing_country.name.mauritius", fallback: "Mauritius")
          /// Mayotte
          internal static let mayotte = L10n.tr("Localizable", "enum.browsing_country.name.mayotte", fallback: "Mayotte")
          /// Mexico
          internal static let mexico = L10n.tr("Localizable", "enum.browsing_country.name.mexico", fallback: "Mexico")
          /// Micronesia
          internal static let micronesia = L10n.tr("Localizable", "enum.browsing_country.name.micronesia", fallback: "Micronesia")
          /// Moldova
          internal static let moldova = L10n.tr("Localizable", "enum.browsing_country.name.moldova", fallback: "Moldova")
          /// Monaco
          internal static let monaco = L10n.tr("Localizable", "enum.browsing_country.name.monaco", fallback: "Monaco")
          /// Mongolia
          internal static let mongolia = L10n.tr("Localizable", "enum.browsing_country.name.mongolia", fallback: "Mongolia")
          /// Montenegro
          internal static let montenegro = L10n.tr("Localizable", "enum.browsing_country.name.montenegro", fallback: "Montenegro")
          /// Montserrat
          internal static let montserrat = L10n.tr("Localizable", "enum.browsing_country.name.montserrat", fallback: "Montserrat")
          /// Morocco
          internal static let morocco = L10n.tr("Localizable", "enum.browsing_country.name.morocco", fallback: "Morocco")
          /// Mozambique
          internal static let mozambique = L10n.tr("Localizable", "enum.browsing_country.name.mozambique", fallback: "Mozambique")
          /// Myanmar (Burma)
          internal static let myanmar = L10n.tr("Localizable", "enum.browsing_country.name.myanmar", fallback: "Myanmar (Burma)")
          /// Namibia
          internal static let namibia = L10n.tr("Localizable", "enum.browsing_country.name.namibia", fallback: "Namibia")
          /// Nauru
          internal static let nauru = L10n.tr("Localizable", "enum.browsing_country.name.nauru", fallback: "Nauru")
          /// Nepal
          internal static let nepal = L10n.tr("Localizable", "enum.browsing_country.name.nepal", fallback: "Nepal")
          /// Netherlands
          internal static let netherlands = L10n.tr("Localizable", "enum.browsing_country.name.netherlands", fallback: "Netherlands")
          /// New Caledonia
          internal static let newCaledonia = L10n.tr("Localizable", "enum.browsing_country.name.new_caledonia", fallback: "New Caledonia")
          /// New Zealand
          internal static let newZealand = L10n.tr("Localizable", "enum.browsing_country.name.new_zealand", fallback: "New Zealand")
          /// Nicaragua
          internal static let nicaragua = L10n.tr("Localizable", "enum.browsing_country.name.nicaragua", fallback: "Nicaragua")
          /// Niger
          internal static let niger = L10n.tr("Localizable", "enum.browsing_country.name.niger", fallback: "Niger")
          /// Nigeria
          internal static let nigeria = L10n.tr("Localizable", "enum.browsing_country.name.nigeria", fallback: "Nigeria")
          /// Niue
          internal static let niue = L10n.tr("Localizable", "enum.browsing_country.name.niue", fallback: "Niue")
          /// Norfolk Island
          internal static let norfolkIsland = L10n.tr("Localizable", "enum.browsing_country.name.norfolk_island", fallback: "Norfolk Island")
          /// North Korea
          internal static let northKorea = L10n.tr("Localizable", "enum.browsing_country.name.north_korea", fallback: "North Korea")
          /// Northern Mariana Islands
          internal static let northernMarianaIslands = L10n.tr("Localizable", "enum.browsing_country.name.northern_mariana_islands", fallback: "Northern Mariana Islands")
          /// Norway
          internal static let norway = L10n.tr("Localizable", "enum.browsing_country.name.norway", fallback: "Norway")
          /// Oman
          internal static let oman = L10n.tr("Localizable", "enum.browsing_country.name.oman", fallback: "Oman")
          /// Pakistan
          internal static let pakistan = L10n.tr("Localizable", "enum.browsing_country.name.pakistan", fallback: "Pakistan")
          /// Palau
          internal static let palau = L10n.tr("Localizable", "enum.browsing_country.name.palau", fallback: "Palau")
          /// Palestinian Territories
          internal static let palestinianTerritory = L10n.tr("Localizable", "enum.browsing_country.name.palestinian_territory", fallback: "Palestinian Territories")
          /// Panama
          internal static let panama = L10n.tr("Localizable", "enum.browsing_country.name.panama", fallback: "Panama")
          /// Papua New Guinea
          internal static let papuaNewGuinea = L10n.tr("Localizable", "enum.browsing_country.name.papua_new_guinea", fallback: "Papua New Guinea")
          /// Paraguay
          internal static let paraguay = L10n.tr("Localizable", "enum.browsing_country.name.paraguay", fallback: "Paraguay")
          /// Peru
          internal static let peru = L10n.tr("Localizable", "enum.browsing_country.name.peru", fallback: "Peru")
          /// Philippines
          internal static let philippines = L10n.tr("Localizable", "enum.browsing_country.name.philippines", fallback: "Philippines")
          /// Pitcairn Islands
          internal static let pitcairnIslands = L10n.tr("Localizable", "enum.browsing_country.name.pitcairn_islands", fallback: "Pitcairn Islands")
          /// Poland
          internal static let poland = L10n.tr("Localizable", "enum.browsing_country.name.poland", fallback: "Poland")
          /// Portugal
          internal static let portugal = L10n.tr("Localizable", "enum.browsing_country.name.portugal", fallback: "Portugal")
          /// Puerto Rico
          internal static let puertoRico = L10n.tr("Localizable", "enum.browsing_country.name.puerto_rico", fallback: "Puerto Rico")
          /// Qatar
          internal static let qatar = L10n.tr("Localizable", "enum.browsing_country.name.qatar", fallback: "Qatar")
          /// Réunion
          internal static let reunion = L10n.tr("Localizable", "enum.browsing_country.name.reunion", fallback: "Réunion")
          /// Romania
          internal static let romania = L10n.tr("Localizable", "enum.browsing_country.name.romania", fallback: "Romania")
          /// Russia
          internal static let russianFederation = L10n.tr("Localizable", "enum.browsing_country.name.russian_federation", fallback: "Russia")
          /// Rwanda
          internal static let rwanda = L10n.tr("Localizable", "enum.browsing_country.name.rwanda", fallback: "Rwanda")
          /// St. Barthélemy
          internal static let saintBarthelemy = L10n.tr("Localizable", "enum.browsing_country.name.saint_barthelemy", fallback: "St. Barthélemy")
          /// St. Helena
          internal static let saintHelena = L10n.tr("Localizable", "enum.browsing_country.name.saint_helena", fallback: "St. Helena")
          /// St. Kitts & Nevis
          internal static let saintKittsAndNevis = L10n.tr("Localizable", "enum.browsing_country.name.saint_kitts_and_nevis", fallback: "St. Kitts & Nevis")
          /// St. Lucia
          internal static let saintLucia = L10n.tr("Localizable", "enum.browsing_country.name.saint_lucia", fallback: "St. Lucia")
          /// St. Martin
          internal static let saintMartin = L10n.tr("Localizable", "enum.browsing_country.name.saint_martin", fallback: "St. Martin")
          /// St. Pierre & Miquelon
          internal static let saintPierreAndMiquelon = L10n.tr("Localizable", "enum.browsing_country.name.saint_pierre_and_miquelon", fallback: "St. Pierre & Miquelon")
          /// St. Vincent & Grenadines
          internal static let saintVincentAndTheGrenadines = L10n.tr("Localizable", "enum.browsing_country.name.saint_vincent_and_the_grenadines", fallback: "St. Vincent & Grenadines")
          /// Samoa
          internal static let samoa = L10n.tr("Localizable", "enum.browsing_country.name.samoa", fallback: "Samoa")
          /// San Marino
          internal static let sanMarino = L10n.tr("Localizable", "enum.browsing_country.name.san_marino", fallback: "San Marino")
          /// São Tomé & Príncipe
          internal static let saoTomeAndPrincipe = L10n.tr("Localizable", "enum.browsing_country.name.sao_tome_and_principe", fallback: "São Tomé & Príncipe")
          /// Saudi Arabia
          internal static let saudiArabia = L10n.tr("Localizable", "enum.browsing_country.name.saudi_arabia", fallback: "Saudi Arabia")
          /// Senegal
          internal static let senegal = L10n.tr("Localizable", "enum.browsing_country.name.senegal", fallback: "Senegal")
          /// Serbia
          internal static let serbia = L10n.tr("Localizable", "enum.browsing_country.name.serbia", fallback: "Serbia")
          /// Seychelles
          internal static let seychelles = L10n.tr("Localizable", "enum.browsing_country.name.seychelles", fallback: "Seychelles")
          /// Sierra Leone
          internal static let sierraLeone = L10n.tr("Localizable", "enum.browsing_country.name.sierra_leone", fallback: "Sierra Leone")
          /// Singapore
          internal static let singapore = L10n.tr("Localizable", "enum.browsing_country.name.singapore", fallback: "Singapore")
          /// Sint Maarten
          internal static let sintMaarten = L10n.tr("Localizable", "enum.browsing_country.name.sint_maarten", fallback: "Sint Maarten")
          /// Slovakia
          internal static let slovakia = L10n.tr("Localizable", "enum.browsing_country.name.slovakia", fallback: "Slovakia")
          /// Slovenia
          internal static let slovenia = L10n.tr("Localizable", "enum.browsing_country.name.slovenia", fallback: "Slovenia")
          /// Solomon Islands
          internal static let solomonIslands = L10n.tr("Localizable", "enum.browsing_country.name.solomon_islands", fallback: "Solomon Islands")
          /// Somalia
          internal static let somalia = L10n.tr("Localizable", "enum.browsing_country.name.somalia", fallback: "Somalia")
          /// South Africa
          internal static let southAfrica = L10n.tr("Localizable", "enum.browsing_country.name.south_africa", fallback: "South Africa")
          /// So. Georgia & So. Sandwich Isl.
          internal static let southGeorgiaAndTheSouthSandwichIslands = L10n.tr("Localizable", "enum.browsing_country.name.south_georgia_and_the_south_sandwich_islands", fallback: "So. Georgia & So. Sandwich Isl.")
          /// South Korea
          internal static let southKorea = L10n.tr("Localizable", "enum.browsing_country.name.south_korea", fallback: "South Korea")
          /// South Sudan
          internal static let southSudan = L10n.tr("Localizable", "enum.browsing_country.name.south_sudan", fallback: "South Sudan")
          /// Spain
          internal static let spain = L10n.tr("Localizable", "enum.browsing_country.name.spain", fallback: "Spain")
          /// Sri Lanka
          internal static let sriLanka = L10n.tr("Localizable", "enum.browsing_country.name.sri_lanka", fallback: "Sri Lanka")
          /// Sudan
          internal static let sudan = L10n.tr("Localizable", "enum.browsing_country.name.sudan", fallback: "Sudan")
          /// Suriname
          internal static let suriname = L10n.tr("Localizable", "enum.browsing_country.name.suriname", fallback: "Suriname")
          /// Svalbard & Jan Mayen
          internal static let svalbardAndJanMayen = L10n.tr("Localizable", "enum.browsing_country.name.svalbard_and_jan_mayen", fallback: "Svalbard & Jan Mayen")
          /// Eswatini
          internal static let swaziland = L10n.tr("Localizable", "enum.browsing_country.name.swaziland", fallback: "Eswatini")
          /// Sweden
          internal static let sweden = L10n.tr("Localizable", "enum.browsing_country.name.sweden", fallback: "Sweden")
          /// Switzerland
          internal static let switzerland = L10n.tr("Localizable", "enum.browsing_country.name.switzerland", fallback: "Switzerland")
          /// Syria
          internal static let syrianArabRepublic = L10n.tr("Localizable", "enum.browsing_country.name.syrian_arab_republic", fallback: "Syria")
          /// Taiwan
          internal static let taiwan = L10n.tr("Localizable", "enum.browsing_country.name.taiwan", fallback: "Taiwan")
          /// Tajikistan
          internal static let tajikistan = L10n.tr("Localizable", "enum.browsing_country.name.tajikistan", fallback: "Tajikistan")
          /// Tanzania
          internal static let tanzania = L10n.tr("Localizable", "enum.browsing_country.name.tanzania", fallback: "Tanzania")
          /// Thailand
          internal static let thailand = L10n.tr("Localizable", "enum.browsing_country.name.thailand", fallback: "Thailand")
          /// Congo - Kinshasa
          internal static let theDemocraticRepublicOfTheCongo = L10n.tr("Localizable", "enum.browsing_country.name.the_democratic_republic_of_the_congo", fallback: "Congo - Kinshasa")
          /// Timor-Leste
          internal static let timorLeste = L10n.tr("Localizable", "enum.browsing_country.name.timor_leste", fallback: "Timor-Leste")
          /// Togo
          internal static let togo = L10n.tr("Localizable", "enum.browsing_country.name.togo", fallback: "Togo")
          /// Tokelau
          internal static let tokelau = L10n.tr("Localizable", "enum.browsing_country.name.tokelau", fallback: "Tokelau")
          /// Tonga
          internal static let tonga = L10n.tr("Localizable", "enum.browsing_country.name.tonga", fallback: "Tonga")
          /// Trinidad & Tobago
          internal static let trinidadAndTobago = L10n.tr("Localizable", "enum.browsing_country.name.trinidad_and_tobago", fallback: "Trinidad & Tobago")
          /// Tunisia
          internal static let tunisia = L10n.tr("Localizable", "enum.browsing_country.name.tunisia", fallback: "Tunisia")
          /// Türkiye
          internal static let turkey = L10n.tr("Localizable", "enum.browsing_country.name.turkey", fallback: "Türkiye")
          /// Turkmenistan
          internal static let turkmenistan = L10n.tr("Localizable", "enum.browsing_country.name.turkmenistan", fallback: "Turkmenistan")
          /// Turks & Caicos Islands
          internal static let turksAndCaicosIslands = L10n.tr("Localizable", "enum.browsing_country.name.turks_and_caicos_islands", fallback: "Turks & Caicos Islands")
          /// Tuvalu
          internal static let tuvalu = L10n.tr("Localizable", "enum.browsing_country.name.tuvalu", fallback: "Tuvalu")
          /// Uganda
          internal static let uganda = L10n.tr("Localizable", "enum.browsing_country.name.uganda", fallback: "Uganda")
          /// Ukraine
          internal static let ukraine = L10n.tr("Localizable", "enum.browsing_country.name.ukraine", fallback: "Ukraine")
          /// United Arab Emirates
          internal static let unitedArabEmirates = L10n.tr("Localizable", "enum.browsing_country.name.united_arab_emirates", fallback: "United Arab Emirates")
          /// United Kingdom
          internal static let unitedKingdom = L10n.tr("Localizable", "enum.browsing_country.name.united_kingdom", fallback: "United Kingdom")
          /// United States
          internal static let unitedStates = L10n.tr("Localizable", "enum.browsing_country.name.united_states", fallback: "United States")
          /// U.S. Outlying Islands
          internal static let unitedStatesMinorOutlyingIslands = L10n.tr("Localizable", "enum.browsing_country.name.united_states_minor_outlying_islands", fallback: "U.S. Outlying Islands")
          /// Uruguay
          internal static let uruguay = L10n.tr("Localizable", "enum.browsing_country.name.uruguay", fallback: "Uruguay")
          /// Uzbekistan
          internal static let uzbekistan = L10n.tr("Localizable", "enum.browsing_country.name.uzbekistan", fallback: "Uzbekistan")
          /// Vanuatu
          internal static let vanuatu = L10n.tr("Localizable", "enum.browsing_country.name.vanuatu", fallback: "Vanuatu")
          /// Vatican City
          internal static let vaticanCityState = L10n.tr("Localizable", "enum.browsing_country.name.vatican_city_state", fallback: "Vatican City")
          /// Venezuela
          internal static let venezuela = L10n.tr("Localizable", "enum.browsing_country.name.venezuela", fallback: "Venezuela")
          /// Vietnam
          internal static let vietnam = L10n.tr("Localizable", "enum.browsing_country.name.vietnam", fallback: "Vietnam")
          /// British Virgin Islands
          internal static let virginIslandsBritish = L10n.tr("Localizable", "enum.browsing_country.name.virgin_islands_british", fallback: "British Virgin Islands")
          /// U.S. Virgin Islands
          internal static let virginIslandsUS = L10n.tr("Localizable", "enum.browsing_country.name.virgin_islands_US", fallback: "U.S. Virgin Islands")
          /// Wallis & Futuna
          internal static let wallisAndFutuna = L10n.tr("Localizable", "enum.browsing_country.name.wallis_and_futuna", fallback: "Wallis & Futuna")
          /// Western Sahara
          internal static let westernSahara = L10n.tr("Localizable", "enum.browsing_country.name.western_sahara", fallback: "Western Sahara")
          /// Yemen
          internal static let yemen = L10n.tr("Localizable", "enum.browsing_country.name.yemen", fallback: "Yemen")
          /// Zambia
          internal static let zambia = L10n.tr("Localizable", "enum.browsing_country.name.zambia", fallback: "Zambia")
          /// Zimbabwe
          internal static let zimbabwe = L10n.tr("Localizable", "enum.browsing_country.name.zimbabwe", fallback: "Zimbabwe")
        }
      }
      internal enum Category {
        internal enum Value {
          /// Artist CG
          internal static let artistCG = L10n.tr("Localizable", "enum.category.value.artist_CG", fallback: "Artist CG")
          /// Asian Porn
          internal static let asianPorn = L10n.tr("Localizable", "enum.category.value.asian_porn", fallback: "Asian Porn")
          /// Cosplay
          internal static let cosplay = L10n.tr("Localizable", "enum.category.value.cosplay", fallback: "Cosplay")
          /// Doujinshi
          internal static let doujinshi = L10n.tr("Localizable", "enum.category.value.doujinshi", fallback: "Doujinshi")
          /// Game CG
          internal static let gameCG = L10n.tr("Localizable", "enum.category.value.game_CG", fallback: "Game CG")
          /// Image Set
          internal static let imageSet = L10n.tr("Localizable", "enum.category.value.image_set", fallback: "Image Set")
          /// Manga
          internal static let manga = L10n.tr("Localizable", "enum.category.value.manga", fallback: "Manga")
          /// Misc
          internal static let misc = L10n.tr("Localizable", "enum.category.value.misc", fallback: "Misc")
          /// Non-H
          internal static let nonH = L10n.tr("Localizable", "enum.category.value.non_h", fallback: "Non-H")
          /// Private
          internal static let `private` = L10n.tr("Localizable", "enum.category.value.private", fallback: "Private")
          /// Western
          internal static let western = L10n.tr("Localizable", "enum.category.value.western", fallback: "Western")
        }
      }
      internal enum EhSetting {
        internal enum ArchiverBehavior {
          internal enum Value {
            /// Original, start automatically
            internal static let autoSelectOriginalAutoStart = L10n.tr("Localizable", "enum.eh_setting.archiver_behavior.value.auto_select_original_auto_start", fallback: "Original, start automatically")
            /// Original, start manually
            internal static let autoSelectOriginalManualStart = L10n.tr("Localizable", "enum.eh_setting.archiver_behavior.value.auto_select_original_manual_start", fallback: "Original, start manually")
            /// Resampled, start automatically
            internal static let autoSelectResampleAutoStart = L10n.tr("Localizable", "enum.eh_setting.archiver_behavior.value.auto_select_resample_auto_start", fallback: "Resampled, start automatically")
            /// Resampled, start manually
            internal static let autoSelectResampleManualStart = L10n.tr("Localizable", "enum.eh_setting.archiver_behavior.value.auto_select_resample_manual_start", fallback: "Resampled, start manually")
            /// Choose manually, start automatically
            internal static let manualSelectAutoStart = L10n.tr("Localizable", "enum.eh_setting.archiver_behavior.value.manual_select_auto_start", fallback: "Choose manually, start automatically")
            /// Choose and start manually (default)
            internal static let manualSelectManualStart = L10n.tr("Localizable", "enum.eh_setting.archiver_behavior.value.manual_select_manual_start", fallback: "Choose and start manually (default)")
          }
        }
        internal enum CommentsSortOrder {
          internal enum Value {
            /// Highest score first
            internal static let highestScore = L10n.tr("Localizable", "enum.eh_setting.comments_sort_order.value.highest_score", fallback: "Highest score first")
            /// Oldest first
            internal static let oldest = L10n.tr("Localizable", "enum.eh_setting.comments_sort_order.value.oldest", fallback: "Oldest first")
            /// Newest first
            internal static let recent = L10n.tr("Localizable", "enum.eh_setting.comments_sort_order.value.recent", fallback: "Newest first")
          }
        }
        internal enum CommentsVotesShowTiming {
          internal enum Value {
            /// Always
            internal static let always = L10n.tr("Localizable", "enum.eh_setting.comments_votes_show_timing.value.always", fallback: "Always")
            /// On hover or click
            internal static let onHoverOrClick = L10n.tr("Localizable", "enum.eh_setting.comments_votes_show_timing.value.on_hover_or_click", fallback: "On hover or click")
          }
        }
        internal enum DisplayMode {
          internal enum Value {
            /// Compact
            internal static let compact = L10n.tr("Localizable", "enum.eh_setting.display_mode.value.compact", fallback: "Compact")
            /// Extended
            internal static let extended = L10n.tr("Localizable", "enum.eh_setting.display_mode.value.extended", fallback: "Extended")
            /// Minimal
            internal static let minimal = L10n.tr("Localizable", "enum.eh_setting.display_mode.value.minimal", fallback: "Minimal")
            /// Minimal+
            internal static let minimalPlus = L10n.tr("Localizable", "enum.eh_setting.display_mode.value.minimalPlus", fallback: "Minimal+")
            /// Thumbnail
            internal static let thumbnail = L10n.tr("Localizable", "enum.eh_setting.display_mode.value.thumbnail", fallback: "Thumbnail")
          }
        }
        internal enum ExcludedLanguagesCategory {
          internal enum Value {
            /// Original
            internal static let original = L10n.tr("Localizable", "enum.eh_setting.excluded_languages_category.value.original", fallback: "Original")
            /// Rewrite
            internal static let rewrite = L10n.tr("Localizable", "enum.eh_setting.excluded_languages_category.value.rewrite", fallback: "Rewrite")
            /// Translated
            internal static let translated = L10n.tr("Localizable", "enum.eh_setting.excluded_languages_category.value.translated", fallback: "Translated")
          }
        }
        internal enum FavoritesSortOrder {
          internal enum Value {
            /// Date favorited
            internal static let favoritedTime = L10n.tr("Localizable", "enum.eh_setting.favorites_sort_order.value.favorited_time", fallback: "Date favorited")
            /// Date updated
            internal static let lastUpdateTime = L10n.tr("Localizable", "enum.eh_setting.favorites_sort_order.value.last_update_time", fallback: "Date updated")
          }
        }
        internal enum GalleryName {
          internal enum Value {
            /// Default title
            internal static let `default` = L10n.tr("Localizable", "enum.eh_setting.gallery_name.value.default", fallback: "Default title")
            /// Japanese title, when there is one
            internal static let japanese = L10n.tr("Localizable", "enum.eh_setting.gallery_name.value.japanese", fallback: "Japanese title, when there is one")
          }
        }
        internal enum GalleryPageNumbering {
          internal enum Value {
            /// None
            internal static let `none` = L10n.tr("Localizable", "enum.eh_setting.gallery_page_numbering.value.none", fallback: "None")
            /// Page number and file name
            internal static let pageNumberAndName = L10n.tr("Localizable", "enum.eh_setting.gallery_page_numbering.value.page_number_and_name", fallback: "Page number and file name")
            /// Page number
            internal static let pageNumberOnly = L10n.tr("Localizable", "enum.eh_setting.gallery_page_numbering.value.page_number_only", fallback: "Page number")
          }
        }
        internal enum ImageResolution {
          internal enum Value {
            /// Automatic
            internal static let auto = L10n.tr("Localizable", "enum.eh_setting.image_resolution.value.auto", fallback: "Automatic")
          }
        }
        internal enum LoadThroughHathSetting {
          internal enum Description {
            /// The recommended choice.
            internal static let anyClient = L10n.tr("Localizable", "enum.eh_setting.load_through_hath_setting.description.any_client", fallback: "The recommended choice.")
            /// May be slower. Choose this if a firewall or proxy blocks outgoing traffic on unusual ports.
            internal static let defaultPortOnly = L10n.tr("Localizable", "enum.eh_setting.load_through_hath_setting.description.default_port_only", fallback: "May be slower. Choose this if a firewall or proxy blocks outgoing traffic on unusual ports.")
            /// Donors only. Current browsers may not support it by default; meant for old browsers.
            internal static let legacyNo = L10n.tr("Localizable", "enum.eh_setting.load_through_hath_setting.description.legacy_no", fallback: "Donors only. Current browsers may not support it by default; meant for old browsers.")
            /// Donors only. You can view fewer pages. Use it only if you have serious problems.
            internal static let modernNo = L10n.tr("Localizable", "enum.eh_setting.load_through_hath_setting.description.modern_no", fallback: "Donors only. You can view fewer pages. Use it only if you have serious problems.")
          }
          internal enum Value {
            /// Any client
            internal static let anyClient = L10n.tr("Localizable", "enum.eh_setting.load_through_hath_setting.value.any_client", fallback: "Any client")
            /// Clients on the default port only
            internal static let defaultPortOnly = L10n.tr("Localizable", "enum.eh_setting.load_through_hath_setting.value.default_port_only", fallback: "Clients on the default port only")
            /// No (legacy, HTTP)
            internal static let legacyNo = L10n.tr("Localizable", "enum.eh_setting.load_through_hath_setting.value.legacy_no", fallback: "No (legacy, HTTP)")
            /// No (modern, HTTPS)
            internal static let modernNo = L10n.tr("Localizable", "enum.eh_setting.load_through_hath_setting.value.modern_no", fallback: "No (modern, HTTPS)")
          }
        }
        internal enum MultiplePageViewerStyle {
          internal enum Value {
            /// Center; always scale
            internal static let alignCenterAlwaysScale = L10n.tr("Localizable", "enum.eh_setting.multiple_page_viewer_style.value.align_center_always_scale", fallback: "Center; always scale")
            /// Center; shrink if too wide
            internal static let alignCenterScaleIfOverWidth = L10n.tr("Localizable", "enum.eh_setting.multiple_page_viewer_style.value.align_center_scale_if_over_width", fallback: "Center; shrink if too wide")
            /// Align left; shrink if too wide
            internal static let alignLeftScaleIfOverWidth = L10n.tr("Localizable", "enum.eh_setting.multiple_page_viewer_style.value.align_left_scale_if_over_width", fallback: "Align left; shrink if too wide")
          }
        }
        internal enum TagsSortOrder {
          internal enum Value {
            /// Alphabetically
            internal static let alphabetical = L10n.tr("Localizable", "enum.eh_setting.tags_sort_order.value.alphabetical", fallback: "Alphabetically")
            /// By tag power
            internal static let tagPower = L10n.tr("Localizable", "enum.eh_setting.tags_sort_order.value.tag_power", fallback: "By tag power")
          }
        }
        internal enum ThumbnailLoadTiming {
          internal enum Description {
            /// Pages load faster, but a thumbnail can take a moment to appear.
            internal static let onMouseOver = L10n.tr("Localizable", "enum.eh_setting.thumbnail_load_timing.description.on_mouse_over", fallback: "Pages load faster, but a thumbnail can take a moment to appear.")
            /// Pages load more slowly, but thumbnails appear right away.
            internal static let onPageLoad = L10n.tr("Localizable", "enum.eh_setting.thumbnail_load_timing.description.on_page_load", fallback: "Pages load more slowly, but thumbnails appear right away.")
          }
          internal enum Value {
            /// On hover
            internal static let onMouseOver = L10n.tr("Localizable", "enum.eh_setting.thumbnail_load_timing.value.on_mouse_over", fallback: "On hover")
            /// With the page
            internal static let onPageLoad = L10n.tr("Localizable", "enum.eh_setting.thumbnail_load_timing.value.on_page_load", fallback: "With the page")
          }
        }
        internal enum ThumbnailSize {
          internal enum Value {
            /// Automatic
            internal static let auto = L10n.tr("Localizable", "enum.eh_setting.thumbnail_size.value.auto", fallback: "Automatic")
            /// Large
            internal static let large = L10n.tr("Localizable", "enum.eh_setting.thumbnail_size.value.large", fallback: "Large")
            /// Normal
            internal static let normal = L10n.tr("Localizable", "enum.eh_setting.thumbnail_size.value.normal", fallback: "Normal")
            /// Small
            internal static let small = L10n.tr("Localizable", "enum.eh_setting.thumbnail_size.value.small", fallback: "Small")
          }
        }
      }
      internal enum FilterRange {
        internal enum Value {
          /// Lists
          internal static let global = L10n.tr("Localizable", "enum.filter_range.value.global", fallback: "Lists")
          /// Search
          internal static let search = L10n.tr("Localizable", "enum.filter_range.value.search", fallback: "Search")
          /// Watched
          internal static let watched = L10n.tr("Localizable", "enum.filter_range.value.watched", fallback: "Watched")
        }
      }
      internal enum GalleryVisibility {
        internal enum Value {
          /// No (%@)
          internal static func no(_ p1: Any) -> String {
            return L10n.tr("Localizable", "enum.gallery_visibility.value.no", String(describing: p1), fallback: "No (%@)")
          }
          /// Yes
          internal static let yes = L10n.tr("Localizable", "enum.gallery_visibility.value.yes", fallback: "Yes")
          internal enum No {
            internal enum Reason {
              /// Expunged
              internal static let expunged = L10n.tr("Localizable", "enum.gallery_visibility.value.no.reason.expunged", fallback: "Expunged")
            }
          }
        }
      }
      internal enum Language {
        internal enum Value {
          /// Afrikaans
          internal static let afrikaans = L10n.tr("Localizable", "enum.language.value.afrikaans", fallback: "Afrikaans")
          /// Albanian
          internal static let albanian = L10n.tr("Localizable", "enum.language.value.albanian", fallback: "Albanian")
          /// Arabic
          internal static let arabic = L10n.tr("Localizable", "enum.language.value.arabic", fallback: "Arabic")
          /// Bengali
          internal static let bengali = L10n.tr("Localizable", "enum.language.value.bengali", fallback: "Bengali")
          /// Bosnian
          internal static let bosnian = L10n.tr("Localizable", "enum.language.value.bosnian", fallback: "Bosnian")
          /// Bulgarian
          internal static let bulgarian = L10n.tr("Localizable", "enum.language.value.bulgarian", fallback: "Bulgarian")
          /// Burmese
          internal static let burmese = L10n.tr("Localizable", "enum.language.value.burmese", fallback: "Burmese")
          /// Catalan
          internal static let catalan = L10n.tr("Localizable", "enum.language.value.catalan", fallback: "Catalan")
          /// Cebuano
          internal static let cebuano = L10n.tr("Localizable", "enum.language.value.cebuano", fallback: "Cebuano")
          /// Chinese
          internal static let chinese = L10n.tr("Localizable", "enum.language.value.chinese", fallback: "Chinese")
          /// Croatian
          internal static let croatian = L10n.tr("Localizable", "enum.language.value.croatian", fallback: "Croatian")
          /// Czech
          internal static let czech = L10n.tr("Localizable", "enum.language.value.czech", fallback: "Czech")
          /// Danish
          internal static let danish = L10n.tr("Localizable", "enum.language.value.danish", fallback: "Danish")
          /// Dutch
          internal static let dutch = L10n.tr("Localizable", "enum.language.value.dutch", fallback: "Dutch")
          /// English
          internal static let english = L10n.tr("Localizable", "enum.language.value.english", fallback: "English")
          /// Esperanto
          internal static let esperanto = L10n.tr("Localizable", "enum.language.value.esperanto", fallback: "Esperanto")
          /// Estonian
          internal static let estonian = L10n.tr("Localizable", "enum.language.value.estonian", fallback: "Estonian")
          /// Finnish
          internal static let finnish = L10n.tr("Localizable", "enum.language.value.finnish", fallback: "Finnish")
          /// French
          internal static let french = L10n.tr("Localizable", "enum.language.value.french", fallback: "French")
          /// Georgian
          internal static let georgian = L10n.tr("Localizable", "enum.language.value.georgian", fallback: "Georgian")
          /// German
          internal static let german = L10n.tr("Localizable", "enum.language.value.german", fallback: "German")
          /// Greek
          internal static let greek = L10n.tr("Localizable", "enum.language.value.greek", fallback: "Greek")
          /// Hebrew
          internal static let hebrew = L10n.tr("Localizable", "enum.language.value.hebrew", fallback: "Hebrew")
          /// Hindi
          internal static let hindi = L10n.tr("Localizable", "enum.language.value.hindi", fallback: "Hindi")
          /// Hmong
          internal static let hmong = L10n.tr("Localizable", "enum.language.value.hmong", fallback: "Hmong")
          /// Hungarian
          internal static let hungarian = L10n.tr("Localizable", "enum.language.value.hungarian", fallback: "Hungarian")
          /// Indonesian
          internal static let indonesian = L10n.tr("Localizable", "enum.language.value.indonesian", fallback: "Indonesian")
          /// Unknown
          internal static let invalid = L10n.tr("Localizable", "enum.language.value.invalid", fallback: "Unknown")
          /// Italian
          internal static let italian = L10n.tr("Localizable", "enum.language.value.italian", fallback: "Italian")
          /// Japanese
          internal static let japanese = L10n.tr("Localizable", "enum.language.value.japanese", fallback: "Japanese")
          /// Kazakh
          internal static let kazakh = L10n.tr("Localizable", "enum.language.value.kazakh", fallback: "Kazakh")
          /// Khmer
          internal static let khmer = L10n.tr("Localizable", "enum.language.value.khmer", fallback: "Khmer")
          /// Korean
          internal static let korean = L10n.tr("Localizable", "enum.language.value.korean", fallback: "Korean")
          /// Kurdish
          internal static let kurdish = L10n.tr("Localizable", "enum.language.value.kurdish", fallback: "Kurdish")
          /// Lao
          internal static let lao = L10n.tr("Localizable", "enum.language.value.lao", fallback: "Lao")
          /// Latin
          internal static let latin = L10n.tr("Localizable", "enum.language.value.latin", fallback: "Latin")
          /// Mongolian
          internal static let mongolian = L10n.tr("Localizable", "enum.language.value.mongolian", fallback: "Mongolian")
          /// Ndebele
          internal static let ndebele = L10n.tr("Localizable", "enum.language.value.ndebele", fallback: "Ndebele")
          /// Nepali
          internal static let nepali = L10n.tr("Localizable", "enum.language.value.nepali", fallback: "Nepali")
          /// Norwegian
          internal static let norwegian = L10n.tr("Localizable", "enum.language.value.norwegian", fallback: "Norwegian")
          /// Oromo
          internal static let oromo = L10n.tr("Localizable", "enum.language.value.oromo", fallback: "Oromo")
          /// Other
          internal static let other = L10n.tr("Localizable", "enum.language.value.other", fallback: "Other")
          /// Pashto
          internal static let pashto = L10n.tr("Localizable", "enum.language.value.pashto", fallback: "Pashto")
          /// Persian
          internal static let persian = L10n.tr("Localizable", "enum.language.value.persian", fallback: "Persian")
          /// Polish
          internal static let polish = L10n.tr("Localizable", "enum.language.value.polish", fallback: "Polish")
          /// Portuguese
          internal static let portuguese = L10n.tr("Localizable", "enum.language.value.portuguese", fallback: "Portuguese")
          /// Punjabi
          internal static let punjabi = L10n.tr("Localizable", "enum.language.value.punjabi", fallback: "Punjabi")
          /// Romanian
          internal static let romanian = L10n.tr("Localizable", "enum.language.value.romanian", fallback: "Romanian")
          /// Russian
          internal static let russian = L10n.tr("Localizable", "enum.language.value.russian", fallback: "Russian")
          /// Sango
          internal static let sango = L10n.tr("Localizable", "enum.language.value.sango", fallback: "Sango")
          /// Serbian
          internal static let serbian = L10n.tr("Localizable", "enum.language.value.serbian", fallback: "Serbian")
          /// Shona
          internal static let shona = L10n.tr("Localizable", "enum.language.value.shona", fallback: "Shona")
          /// Slovak
          internal static let slovak = L10n.tr("Localizable", "enum.language.value.slovak", fallback: "Slovak")
          /// Slovenian
          internal static let slovenian = L10n.tr("Localizable", "enum.language.value.slovenian", fallback: "Slovenian")
          /// Somali
          internal static let somali = L10n.tr("Localizable", "enum.language.value.somali", fallback: "Somali")
          /// Spanish
          internal static let spanish = L10n.tr("Localizable", "enum.language.value.spanish", fallback: "Spanish")
          /// Swahili
          internal static let swahili = L10n.tr("Localizable", "enum.language.value.swahili", fallback: "Swahili")
          /// Swedish
          internal static let swedish = L10n.tr("Localizable", "enum.language.value.swedish", fallback: "Swedish")
          /// Tagalog
          internal static let tagalog = L10n.tr("Localizable", "enum.language.value.tagalog", fallback: "Tagalog")
          /// Thai
          internal static let thai = L10n.tr("Localizable", "enum.language.value.thai", fallback: "Thai")
          /// Tigrinya
          internal static let tigrinya = L10n.tr("Localizable", "enum.language.value.tigrinya", fallback: "Tigrinya")
          /// Turkish
          internal static let turkish = L10n.tr("Localizable", "enum.language.value.turkish", fallback: "Turkish")
          /// Ukrainian
          internal static let ukrainian = L10n.tr("Localizable", "enum.language.value.ukrainian", fallback: "Ukrainian")
          /// Urdu
          internal static let urdu = L10n.tr("Localizable", "enum.language.value.urdu", fallback: "Urdu")
          /// Vietnamese
          internal static let vietnamese = L10n.tr("Localizable", "enum.language.value.vietnamese", fallback: "Vietnamese")
          /// Zulu
          internal static let zulu = L10n.tr("Localizable", "enum.language.value.zulu", fallback: "Zulu")
        }
      }
      internal enum PreferredColorScheme {
        internal enum Value {
          /// Automatic
          internal static let automatic = L10n.tr("Localizable", "enum.preferred_color_scheme.value.automatic", fallback: "Automatic")
          /// Dark
          internal static let dark = L10n.tr("Localizable", "enum.preferred_color_scheme.value.dark", fallback: "Dark")
          /// Light
          internal static let light = L10n.tr("Localizable", "enum.preferred_color_scheme.value.light", fallback: "Light")
        }
      }
      internal enum ReadingDirection {
        internal enum Value {
          /// Left to right
          internal static let leftToRight = L10n.tr("Localizable", "enum.reading_direction.value.left_to_right", fallback: "Left to right")
          /// Right to left
          internal static let rightToLeft = L10n.tr("Localizable", "enum.reading_direction.value.right_to_left", fallback: "Right to left")
          /// Top to bottom
          internal static let vertical = L10n.tr("Localizable", "enum.reading_direction.value.vertical", fallback: "Top to bottom")
        }
      }
      internal enum SettingStateRoute {
        internal enum Value {
          /// About EhShoko
          internal static let about = L10n.tr("Localizable", "enum.setting_state_route.value.about", fallback: "About EhShoko")
          /// General
          internal static let general = L10n.tr("Localizable", "enum.setting_state_route.value.general", fallback: "General")
          /// Laboratory
          internal static let laboratory = L10n.tr("Localizable", "enum.setting_state_route.value.laboratory", fallback: "Laboratory")
          /// Reading
          internal static let reading = L10n.tr("Localizable", "enum.setting_state_route.value.reading", fallback: "Reading")
        }
      }
      internal enum TagNamespace {
        internal enum Value {
          /// Artist
          internal static let artist = L10n.tr("Localizable", "enum.tag_namespace.value.artist", fallback: "Artist")
          /// Character
          internal static let character = L10n.tr("Localizable", "enum.tag_namespace.value.character", fallback: "Character")
          /// Cosplayer
          internal static let cosplayer = L10n.tr("Localizable", "enum.tag_namespace.value.cosplayer", fallback: "Cosplayer")
          /// Female
          internal static let female = L10n.tr("Localizable", "enum.tag_namespace.value.female", fallback: "Female")
          /// Group
          internal static let group = L10n.tr("Localizable", "enum.tag_namespace.value.group", fallback: "Group")
          /// Language
          internal static let language = L10n.tr("Localizable", "enum.tag_namespace.value.language", fallback: "Language")
          /// Male
          internal static let male = L10n.tr("Localizable", "enum.tag_namespace.value.male", fallback: "Male")
          /// Mixed
          internal static let mixed = L10n.tr("Localizable", "enum.tag_namespace.value.mixed", fallback: "Mixed")
          /// Other
          internal static let other = L10n.tr("Localizable", "enum.tag_namespace.value.other", fallback: "Other")
          /// Parody
          internal static let parody = L10n.tr("Localizable", "enum.tag_namespace.value.parody", fallback: "Parody")
          /// Reclass
          internal static let reclass = L10n.tr("Localizable", "enum.tag_namespace.value.reclass", fallback: "Reclass")
          /// Temp
          internal static let temp = L10n.tr("Localizable", "enum.tag_namespace.value.temp", fallback: "Temp")
        }
      }
      internal enum ToplistsType {
        internal enum Value {
          /// All time
          internal static let allTime = L10n.tr("Localizable", "enum.toplists_type.value.all_time", fallback: "All time")
          /// Past month
          internal static let pastMonth = L10n.tr("Localizable", "enum.toplists_type.value.past_month", fallback: "Past month")
          /// Past year
          internal static let pastYear = L10n.tr("Localizable", "enum.toplists_type.value.past_year", fallback: "Past year")
          /// Yesterday
          internal static let yesterday = L10n.tr("Localizable", "enum.toplists_type.value.yesterday", fallback: "Yesterday")
        }
      }
    }
    internal enum ErrorView {
      internal enum Button {
        /// Delete database
        internal static let dropDatabase = L10n.tr("Localizable", "error_view.button.drop_database", fallback: "Delete database")
        /// Try again
        internal static let retry = L10n.tr("Localizable", "error_view.button.retry", fallback: "Try again")
      }
      internal enum Headline {
        /// ExHentai refused the sign-in
        internal static let exhentaiAccessDenied = L10n.tr("Localizable", "error_view.headline.exhentai_access_denied", fallback: "ExHentai refused the sign-in")
        /// Sign-in required
        internal static let loginRequired = L10n.tr("Localizable", "error_view.headline.login_required", fallback: "Sign-in required")
        /// Unreadable page
        internal static let parseFailed = L10n.tr("Localizable", "error_view.headline.parse_failed", fallback: "Unreadable page")
        /// Server error
        internal static let serverError = L10n.tr("Localizable", "error_view.headline.server_error", fallback: "Server error")
      }
      internal enum Title {
        /// This gallery was taken down after a copyright claim by %@.
        internal static func copyrightClaim(_ p1: Any) -> String {
          return L10n.tr("Localizable", "error_view.title.copyright_claim", String(describing: p1), fallback: "This gallery was taken down after a copyright claim by %@.")
        }
        /// EhShoko's database is damaged.
        /// Please report this on GitHub.
        internal static let databaseCorrupted = L10n.tr("Localizable", "error_view.title.database_corrupted", fallback: "EhShoko's database is damaged.\nPlease report this on GitHub.")
        /// ExHentai didn't accept your sign-in. It may have expired, or this account may not have access to ExHentai. Sign in again in Settings › Account, or switch to E-Hentai there.
        internal static let exhentaiAccessDenied = L10n.tr("Localizable", "error_view.title.exhentai_access_denied", fallback: "ExHentai didn't accept your sign-in. It may have expired, or this account may not have access to ExHentai. Sign in again in Settings › Account, or switch to E-Hentai there.")
        /// This gallery was removed or can't be viewed.
        internal static let galleryUnavailable = L10n.tr("Localizable", "error_view.title.gallery_unavailable", fallback: "This gallery was removed or can't be viewed.")
        /// The site has blocked your IP address for a while because it loaded too many pages too quickly, which looks like automated downloading. The block lifts in %@.
        internal static func ipBanned(_ p1: Any) -> String {
          return L10n.tr("Localizable", "error_view.title.ip_banned", String(describing: p1), fallback: "The site has blocked your IP address for a while because it loaded too many pages too quickly, which looks like automated downloading. The block lifts in %@.")
        }
        /// This page needs you to be signed in, and your sign-in is missing or has expired. Sign in again in Settings › Account.
        internal static let loginRequired = L10n.tr("Localizable", "error_view.title.login_required", fallback: "This page needs you to be signed in, and your sign-in is missing or has expired. Sign in again in Settings › Account.")
        /// Couldn't connect to the site.
        internal static let network = L10n.tr("Localizable", "error_view.title.network", fallback: "Couldn't connect to the site.")
        /// There's nothing here.
        internal static let notFound = L10n.tr("Localizable", "error_view.title.not_found", fallback: "There's nothing here.")
        /// The site returned a page that EhShoko could not read. The site may have changed, or it may be temporarily unavailable.
        internal static let parsing = L10n.tr("Localizable", "error_view.title.parsing", fallback: "The site returned a page that EhShoko could not read. The site may have changed, or it may be temporarily unavailable.")
        /// The server answered with error %@ instead of a page. It may be temporarily unavailable.
        internal static func serverError(_ p1: Any) -> String {
          return L10n.tr("Localizable", "error_view.title.server_error", String(describing: p1), fallback: "The server answered with error %@ instead of a page. It may be temporarily unavailable.")
        }
        /// Try again in a little while.
        internal static let tryLater = L10n.tr("Localizable", "error_view.title.try_later", fallback: "Try again in a little while.")
        /// Something went wrong.
        internal static let unknown = L10n.tr("Localizable", "error_view.title.unknown", fallback: "Something went wrong.")
      }
    }
    internal enum FiltersView {
      internal enum Section {
        internal enum Footer {
          /// Lists, Watched and Search each keep their own filters. Changes apply as you make them.
          internal static let separateFilters = L10n.tr("Localizable", "filters_view.section.footer.separate_filters", fallback: "Lists, Watched and Search each keep their own filters. Changes apply as you make them.")
        }
        internal enum Title {
          /// Advanced
          internal static let advanced = L10n.tr("Localizable", "filters_view.section.title.advanced", fallback: "Advanced")
          /// Your default filters
          internal static let defaultFilter = L10n.tr("Localizable", "filters_view.section.title.default_filter", fallback: "Your default filters")
          /// Narrow down
          internal static let narrowDown = L10n.tr("Localizable", "filters_view.section.title.narrow_down", fallback: "Narrow down")
        }
      }
      internal enum Title {
        /// Advanced options
        internal static let advancedSettings = L10n.tr("Localizable", "filters_view.title.advanced_settings", fallback: "Advanced options")
        /// Any
        internal static let any = L10n.tr("Localizable", "filters_view.title.any", fallback: "Any")
        /// Ignore language filter
        internal static let disableLanguageFilter = L10n.tr("Localizable", "filters_view.title.disable_language_filter", fallback: "Ignore language filter")
        /// Ignore tag filter
        internal static let disableTagsFilter = L10n.tr("Localizable", "filters_view.title.disable_tags_filter", fallback: "Ignore tag filter")
        /// Ignore uploader filter
        internal static let disableUploaderFilter = L10n.tr("Localizable", "filters_view.title.disable_uploader_filter", fallback: "Ignore uploader filter")
        /// Filters
        internal static let filters = L10n.tr("Localizable", "filters_view.title.filters", fallback: "Filters")
        /// Minimum rating
        internal static let minimumRating = L10n.tr("Localizable", "filters_view.title.minimum_rating", fallback: "Minimum rating")
        /// Only galleries with torrents
        internal static let onlyShowGalleriesWithTorrents = L10n.tr("Localizable", "filters_view.title.only_show_galleries_with_torrents", fallback: "Only galleries with torrents")
        /// %d on
        internal static func optionsOn(_ p1: Int) -> String {
          return L10n.tr("Localizable", "filters_view.title.options_on", p1, fallback: "%d on")
        }
        /// to
        internal static let pagesSeparator = L10n.tr("Localizable", "filters_view.title.pages_separator", fallback: "to")
        /// Include downvoted tags
        internal static let searchDownvotedTags = L10n.tr("Localizable", "filters_view.title.search_downvoted_tags", fallback: "Include downvoted tags")
        /// Include expunged galleries
        internal static let searchExpungedGalleries = L10n.tr("Localizable", "filters_view.title.search_expunged_galleries", fallback: "Include expunged galleries")
        /// Search descriptions
        internal static let searchGalleryDescription = L10n.tr("Localizable", "filters_view.title.search_gallery_description", fallback: "Search descriptions")
        /// Search titles
        internal static let searchGalleryName = L10n.tr("Localizable", "filters_view.title.search_gallery_name", fallback: "Search titles")
        /// Search tags
        internal static let searchGalleryTags = L10n.tr("Localizable", "filters_view.title.search_gallery_tags", fallback: "Search tags")
        /// Include low-power tags
        internal static let searchLowPowerTags = L10n.tr("Localizable", "filters_view.title.search_low_power_tags", fallback: "Include low-power tags")
        /// Search torrent file names
        internal static let searchTorrentFilenames = L10n.tr("Localizable", "filters_view.title.search_torrent_filenames", fallback: "Search torrent file names")
        /// Limit by rating
        internal static let setMinimumRating = L10n.tr("Localizable", "filters_view.title.set_minimum_rating", fallback: "Limit by rating")
        /// Limit by length
        internal static let setPagesRange = L10n.tr("Localizable", "filters_view.title.set_pages_range", fallback: "Limit by length")
      }
    }
    internal enum FrontpageView {
      internal enum Title {
        /// Frontpage
        internal static let frontpage = L10n.tr("Localizable", "frontpage_view.title.frontpage", fallback: "Frontpage")
      }
    }
    internal enum Gallery {
      /// All %d
      internal static func all(_ p1: Int) -> String {
        return L10n.tr("Localizable", "gallery.all", p1, fallback: "All %d")
      }
      /// Continue
      internal static let `continue` = L10n.tr("Localizable", "gallery.continue", fallback: "Continue")
      /// Offline · showing the saved page
      internal static let offline = L10n.tr("Localizable", "gallery.offline", fallback: "Offline · showing the saved page")
      /// Previews
      internal static let previews = L10n.tr("Localizable", "gallery.previews", fallback: "Previews")
      /// Read
      internal static let read = L10n.tr("Localizable", "gallery.read", fallback: "Read")
      /// Read again
      internal static let readAgain = L10n.tr("Localizable", "gallery.read_again", fallback: "Read again")
      /// Tags
      internal static let tags = L10n.tr("Localizable", "gallery.tags", fallback: "Tags")
      /// Uploaded by %1$@ · %2$@
      internal static func uploadedBy(_ p1: Any, _ p2: Any) -> String {
        return L10n.tr("Localizable", "gallery.uploaded_by", String(describing: p1), String(describing: p2), fallback: "Uploaded by %1$@ · %2$@")
      }
      internal enum Action {
        /// Archive
        internal static let archive = L10n.tr("Localizable", "gallery.action.archive", fallback: "Archive")
        /// Info
        internal static let info = L10n.tr("Localizable", "gallery.action.info", fallback: "Info")
        /// Rate
        internal static let rate = L10n.tr("Localizable", "gallery.action.rate", fallback: "Rate")
        /// Similar galleries
        internal static let similar = L10n.tr("Localizable", "gallery.action.similar", fallback: "Similar galleries")
        /// Torrents
        internal static let torrents = L10n.tr("Localizable", "gallery.action.torrents", fallback: "Torrents")
        internal enum Torrents {
          /// Torrents · %d
          internal static func count(_ p1: Int) -> String {
            return L10n.tr("Localizable", "gallery.action.torrents.count", p1, fallback: "Torrents · %d")
          }
        }
      }
      internal enum Comments {
        /// Uploader
        internal static let uploader = L10n.tr("Localizable", "gallery.comments.uploader", fallback: "Uploader")
        /// Write a comment
        internal static let write = L10n.tr("Localizable", "gallery.comments.write", fallback: "Write a comment")
      }
      internal enum Continue {
        /// page %1$d of %2$d
        internal static func page(_ p1: Int, _ p2: Int) -> String {
          return L10n.tr("Localizable", "gallery.continue.page", p1, p2, fallback: "page %1$d of %2$d")
        }
        /// %1$d / %2$d
        internal static func short(_ p1: Int, _ p2: Int) -> String {
          return L10n.tr("Localizable", "gallery.continue.short", p1, p2, fallback: "%1$d / %2$d")
        }
      }
      internal enum Figure {
        /// Favorited
        internal static let favorited = L10n.tr("Localizable", "gallery.figure.favorited", fallback: "Favorited")
        /// Language
        internal static let language = L10n.tr("Localizable", "gallery.figure.language", fallback: "Language")
        /// Pages
        internal static let pages = L10n.tr("Localizable", "gallery.figure.pages", fallback: "Pages")
        /// Parody
        internal static let parody = L10n.tr("Localizable", "gallery.figure.parody", fallback: "Parody")
        /// people
        internal static let people = L10n.tr("Localizable", "gallery.figure.people", fallback: "people")
        /// person
        internal static let person = L10n.tr("Localizable", "gallery.figure.person", fallback: "person")
        /// Posted
        internal static let posted = L10n.tr("Localizable", "gallery.figure.posted", fallback: "Posted")
        /// Rating
        internal static let rating = L10n.tr("Localizable", "gallery.figure.rating", fallback: "Rating")
        /// Size
        internal static let size = L10n.tr("Localizable", "gallery.figure.size", fallback: "Size")
        /// Translated
        internal static let translated = L10n.tr("Localizable", "gallery.figure.translated", fallback: "Translated")
        /// Uploader
        internal static let uploader = L10n.tr("Localizable", "gallery.figure.uploader", fallback: "Uploader")
        /// %d vote
        internal static func vote(_ p1: Int) -> String {
          return L10n.tr("Localizable", "gallery.figure.vote", p1, fallback: "%d vote")
        }
        /// %d votes
        internal static func votes(_ p1: Int) -> String {
          return L10n.tr("Localizable", "gallery.figure.votes", p1, fallback: "%d votes")
        }
        internal enum Pages {
          /// %d read
          internal static func read(_ p1: Int) -> String {
            return L10n.tr("Localizable", "gallery.figure.pages.read", p1, fallback: "%d read")
          }
        }
      }
      internal enum Previews {
        /// Columns
        internal static let columns = L10n.tr("Localizable", "gallery.previews.columns", fallback: "Columns")
      }
      internal enum Tags {
        /// Tags · %d
        internal static func count(_ p1: Int) -> String {
          return L10n.tr("Localizable", "gallery.tags.count", p1, fallback: "Tags · %d")
        }
        /// +%d
        internal static func more(_ p1: Int) -> String {
          return L10n.tr("Localizable", "gallery.tags.more", p1, fallback: "+%d")
        }
        /// Vote
        internal static let vote = L10n.tr("Localizable", "gallery.tags.vote", fallback: "Vote")
      }
    }
    internal enum GalleryInfosView {
      internal enum Title {
        /// Archive link
        internal static let archiveURL = L10n.tr("Localizable", "gallery_infos_view.title.archive_URL", fallback: "Archive link")
        /// Average rating
        internal static let averageRating = L10n.tr("Localizable", "gallery_infos_view.title.average_rating", fallback: "Average rating")
        /// Category
        internal static let category = L10n.tr("Localizable", "gallery_infos_view.title.category", fallback: "Category")
        /// Cover link
        internal static let coverURL = L10n.tr("Localizable", "gallery_infos_view.title.cover_URL", fallback: "Cover link")
        /// In your favorites
        internal static let favorited = L10n.tr("Localizable", "gallery_infos_view.title.favorited", fallback: "In your favorites")
        /// Times favorited
        internal static let favoritedTimes = L10n.tr("Localizable", "gallery_infos_view.title.favorited_times", fallback: "Times favorited")
        /// Size
        internal static let fileSize = L10n.tr("Localizable", "gallery_infos_view.title.file_size", fallback: "Size")
        /// Gallery details
        internal static let galleryInfos = L10n.tr("Localizable", "gallery_infos_view.title.gallery_infos", fallback: "Gallery details")
        /// Gallery link
        internal static let galleryURL = L10n.tr("Localizable", "gallery_infos_view.title.gallery_URL", fallback: "Gallery link")
        /// ID
        internal static let id = L10n.tr("Localizable", "gallery_infos_view.title.id", fallback: "ID")
        /// Japanese title
        internal static let japaneseTitle = L10n.tr("Localizable", "gallery_infos_view.title.japanese_title", fallback: "Japanese title")
        /// Language
        internal static let language = L10n.tr("Localizable", "gallery_infos_view.title.language", fallback: "Language")
        /// Your rating
        internal static let myRating = L10n.tr("Localizable", "gallery_infos_view.title.my_rating", fallback: "Your rating")
        /// Pages
        internal static let pageCount = L10n.tr("Localizable", "gallery_infos_view.title.page_count", fallback: "Pages")
        /// Parent gallery link
        internal static let parentURL = L10n.tr("Localizable", "gallery_infos_view.title.parent_URL", fallback: "Parent gallery link")
        /// Posted
        internal static let postedDate = L10n.tr("Localizable", "gallery_infos_view.title.posted_date", fallback: "Posted")
        /// Ratings
        internal static let ratingCount = L10n.tr("Localizable", "gallery_infos_view.title.rating_count", fallback: "Ratings")
        /// Title
        internal static let title = L10n.tr("Localizable", "gallery_infos_view.title.title", fallback: "Title")
        /// Token
        internal static let token = L10n.tr("Localizable", "gallery_infos_view.title.token", fallback: "Token")
        /// Torrents
        internal static let torrentCount = L10n.tr("Localizable", "gallery_infos_view.title.torrent_count", fallback: "Torrents")
        /// Torrent link
        internal static let torrentURL = L10n.tr("Localizable", "gallery_infos_view.title.torrent_URL", fallback: "Torrent link")
        /// Uploader
        internal static let uploader = L10n.tr("Localizable", "gallery_infos_view.title.uploader", fallback: "Uploader")
        /// Visible
        internal static let visibility = L10n.tr("Localizable", "gallery_infos_view.title.visibility", fallback: "Visible")
      }
      internal enum Value {
        /// No
        internal static let no = L10n.tr("Localizable", "gallery_infos_view.value.no", fallback: "No")
        /// None
        internal static let `none` = L10n.tr("Localizable", "gallery_infos_view.value.none", fallback: "None")
        /// Yes
        internal static let yes = L10n.tr("Localizable", "gallery_infos_view.value.yes", fallback: "Yes")
      }
    }
    internal enum GeneralSettingView {
      internal enum Button {
        /// Clear image cache
        internal static let clearImageCaches = L10n.tr("Localizable", "general_setting_view.button.clear_image_caches", fallback: "Clear image cache")
        /// Import translation file…
        internal static let importCustomTranslations = L10n.tr("Localizable", "general_setting_view.button.import_custom_translations", fallback: "Import translation file…")
        /// Logs
        internal static let logs = L10n.tr("Localizable", "general_setting_view.button.logs", fallback: "Logs")
        /// Remove imported translations
        internal static let removeCustomTranslations = L10n.tr("Localizable", "general_setting_view.button.remove_custom_translations", fallback: "Remove imported translations")
      }
      internal enum Section {
        internal enum Title {
          /// Storage
          internal static let caches = L10n.tr("Localizable", "general_setting_view.section.title.caches", fallback: "Storage")
          /// Links
          internal static let navigation = L10n.tr("Localizable", "general_setting_view.section.title.navigation", fallback: "Links")
          /// Privacy
          internal static let security = L10n.tr("Localizable", "general_setting_view.section.title.security", fallback: "Privacy")
          /// Tags
          internal static let tags = L10n.tr("Localizable", "general_setting_view.section.title.tags", fallback: "Tags")
        }
      }
      internal enum Title {
        /// Auto-Lock
        internal static let autoLock = L10n.tr("Localizable", "general_setting_view.title.auto_lock", fallback: "Auto-Lock")
        /// Blur in App Switcher
        internal static let backgroundBlurRadius = L10n.tr("Localizable", "general_setting_view.title.background_blur_radius", fallback: "Blur in App Switcher")
        /// Check the clipboard for links
        internal static let detectsLinksFromClipboard = L10n.tr("Localizable", "general_setting_view.title.detects_links_from_clipboard", fallback: "Check the clipboard for links")
        /// Download tag translations
        internal static let enablesTagsExtension = L10n.tr("Localizable", "general_setting_view.title.enables_tags_extension", fallback: "Download tag translations")
        /// General
        internal static let general = L10n.tr("Localizable", "general_setting_view.title.general", fallback: "General")
        /// Language
        internal static let language = L10n.tr("Localizable", "general_setting_view.title.language", fallback: "Language")
        /// Open links on the selected site
        internal static let redirectsLinksToTheSelectedHost = L10n.tr("Localizable", "general_setting_view.title.redirects_links_to_the_selected_host", fallback: "Open links on the selected site")
        /// Show images in tags
        internal static let showsImagesInTags = L10n.tr("Localizable", "general_setting_view.title.shows_images_in_tags", fallback: "Show images in tags")
        /// Suggest tags while searching
        internal static let showsTagsSearchSuggestion = L10n.tr("Localizable", "general_setting_view.title.shows_tags_search_suggestion", fallback: "Suggest tags while searching")
        /// Translate tags
        internal static let translatesTags = L10n.tr("Localizable", "general_setting_view.title.translates_tags", fallback: "Translate tags")
      }
      internal enum Value {
        /// Unknown
        internal static let defaultLanguageDescription = L10n.tr("Localizable", "general_setting_view.value.default_language_description", fallback: "Unknown")
      }
    }
    internal enum HistoryView {
      internal enum Title {
        /// History
        internal static let history = L10n.tr("Localizable", "history_view.title.history", fallback: "History")
      }
    }
    internal enum HomeView {
      internal enum Title {
        /// Home
        internal static let home = L10n.tr("Localizable", "home_view.title.home", fallback: "Home")
      }
    }
    internal enum Hud {
      internal enum Caption {
        /// Copied
        internal static let copiedToClipboard = L10n.tr("Localizable", "hud.caption.copied_to_clipboard", fallback: "Copied")
        /// Saved to Photos
        internal static let savedToPhotoLibrary = L10n.tr("Localizable", "hud.caption.saved_to_photo_library", fallback: "Saved to Photos")
      }
      internal enum Title {
        /// Contacting the site…
        internal static let communicating = L10n.tr("Localizable", "hud.title.communicating", fallback: "Contacting the site…")
        /// Error
        internal static let error = L10n.tr("Localizable", "hud.title.error", fallback: "Error")
        /// Loading…
        internal static let loading = L10n.tr("Localizable", "hud.title.loading", fallback: "Loading…")
        /// Done
        internal static let success = L10n.tr("Localizable", "hud.title.success", fallback: "Done")
      }
    }
    internal enum JumpPageView {
      internal enum Button {
        /// Cancel
        internal static let cancel = L10n.tr("Localizable", "jump_page_view.button.cancel", fallback: "Cancel")
        /// Go
        internal static let confirm = L10n.tr("Localizable", "jump_page_view.button.confirm", fallback: "Go")
      }
      internal enum Title {
        /// Go to page
        internal static let jumpPage = L10n.tr("Localizable", "jump_page_view.title.jump_page", fallback: "Go to page")
      }
    }
    internal enum LaboratorySettingView {
      internal enum Title {
        /// Bypass SNI filtering
        internal static let bypassesSNIFiltering = L10n.tr("Localizable", "laboratory_setting_view.title.bypasses_SNI_filtering", fallback: "Bypass SNI filtering")
        /// Laboratory
        internal static let laboratory = L10n.tr("Localizable", "laboratory_setting_view.title.laboratory", fallback: "Laboratory")
      }
    }
    internal enum Library {
      /// All
      internal static let all = L10n.tr("Localizable", "library.all", fallback: "All")
      /// %1$@ galleries in %2$d folders
      internal static func summary(_ p1: Any, _ p2: Int) -> String {
        return L10n.tr("Localizable", "library.summary", String(describing: p1), p2, fallback: "%1$@ galleries in %2$d folders")
      }
      internal enum All {
        /// All Favorites
        internal static let title = L10n.tr("Localizable", "library.all.title", fallback: "All Favorites")
      }
      internal enum Order {
        /// newest favorited first
        internal static let favorited = L10n.tr("Localizable", "library.order.favorited", fallback: "newest favorited first")
        /// newest posted first
        internal static let posted = L10n.tr("Localizable", "library.order.posted", fallback: "newest posted first")
      }
    }
    internal enum List {
      /// added %@
      internal static func added(_ p1: Any) -> String {
        return L10n.tr("Localizable", "list.added", String(describing: p1), fallback: "added %@")
      }
      /// No galleries
      internal static let empty = L10n.tr("Localizable", "list.empty", fallback: "No galleries")
      /// Find in this list
      internal static let find = L10n.tr("Localizable", "list.find", fallback: "Find in this list")
      /// %d galleries
      internal static func galleries(_ p1: Int) -> String {
        return L10n.tr("Localizable", "list.galleries", p1, fallback: "%d galleries")
      }
      /// %d gallery
      internal static func gallery(_ p1: Int) -> String {
        return L10n.tr("Localizable", "list.gallery", p1, fallback: "%d gallery")
      }
      /// opened %@
      internal static func opened(_ p1: Any) -> String {
        return L10n.tr("Localizable", "list.opened", String(describing: p1), fallback: "opened %@")
      }
      /// %d pages
      internal static func pages(_ p1: Int) -> String {
        return L10n.tr("Localizable", "list.pages", p1, fallback: "%d pages")
      }
      /// No. %d
      internal static func rank(_ p1: Int) -> String {
        return L10n.tr("Localizable", "list.rank", p1, fallback: "No. %d")
      }
      /// Sort
      internal static let sort = L10n.tr("Localizable", "list.sort", fallback: "Sort")
      internal enum Action {
        /// Favorite
        internal static let favorite = L10n.tr("Localizable", "list.action.favorite", fallback: "Favorite")
        /// More
        internal static let more = L10n.tr("Localizable", "list.action.more", fallback: "More")
        /// Move
        internal static let move = L10n.tr("Localizable", "list.action.move", fallback: "Move")
        /// Read
        internal static let read = L10n.tr("Localizable", "list.action.read", fallback: "Read")
        /// Remove
        internal static let remove = L10n.tr("Localizable", "list.action.remove", fallback: "Remove")
        /// Search %@
        internal static func searchArtist(_ p1: Any) -> String {
          return L10n.tr("Localizable", "list.action.search_artist", String(describing: p1), fallback: "Search %@")
        }
        /// Remove from favorites
        internal static let unfavorite = L10n.tr("Localizable", "list.action.unfavorite", fallback: "Remove from favorites")
      }
      internal enum Cover {
        /// Cover not saved
        internal static let missing = L10n.tr("Localizable", "list.cover.missing", fallback: "Cover not saved")
      }
      internal enum Covers {
        /// Hide covers
        internal static let hide = L10n.tr("Localizable", "list.covers.hide", fallback: "Hide covers")
        /// Show covers
        internal static let show = L10n.tr("Localizable", "list.covers.show", fallback: "Show covers")
      }
      internal enum Day {
        /// Today
        internal static let today = L10n.tr("Localizable", "list.day.today", fallback: "Today")
        /// Yesterday
        internal static let yesterday = L10n.tr("Localizable", "list.day.yesterday", fallback: "Yesterday")
      }
      internal enum Density {
        /// %d columns
        internal static func columns(_ p1: Int) -> String {
          return L10n.tr("Localizable", "list.density.columns", p1, fallback: "%d columns")
        }
        /// pinch for %1$d or %2$d
        internal static func hint(_ p1: Int, _ p2: Int) -> String {
          return L10n.tr("Localizable", "list.density.hint", p1, p2, fallback: "pinch for %1$d or %2$d")
        }
        /// Large covers
        internal static let large = L10n.tr("Localizable", "list.density.large", fallback: "Large covers")
        /// Medium covers
        internal static let medium = L10n.tr("Localizable", "list.density.medium", fallback: "Medium covers")
        /// Small covers
        internal static let small = L10n.tr("Localizable", "list.density.small", fallback: "Small covers")
      }
      internal enum Empty {
        /// Nothing here yet
        internal static let ledger = L10n.tr("Localizable", "list.empty.ledger", fallback: "Nothing here yet")
      }
      internal enum Favorited {
        /// Added to %@
        internal static func hud(_ p1: Any) -> String {
          return L10n.tr("Localizable", "list.favorited.hud", String(describing: p1), fallback: "Added to %@")
        }
      }
      internal enum Filter {
        /// ★ %d+
        internal static func minRating(_ p1: Int) -> String {
          return L10n.tr("Localizable", "list.filter.min_rating", p1, fallback: "★ %d+")
        }
        /// %1$d of %2$d
        internal static func summary(_ p1: Int, _ p2: Int) -> String {
          return L10n.tr("Localizable", "list.filter.summary", p1, p2, fallback: "%1$d of %2$d")
        }
        internal enum Pages {
          /// %d pages or more
          internal static func atLeast(_ p1: Int) -> String {
            return L10n.tr("Localizable", "list.filter.pages.at_least", p1, fallback: "%d pages or more")
          }
          /// %1$d–%2$d pages
          internal static func range(_ p1: Int, _ p2: Int) -> String {
            return L10n.tr("Localizable", "list.filter.pages.range", p1, p2, fallback: "%1$d–%2$d pages")
          }
        }
        internal enum Summary {
          /// %1$d of %2$d categories
          internal static func categories(_ p1: Int, _ p2: Int) -> String {
            return L10n.tr("Localizable", "list.filter.summary.categories", p1, p2, fallback: "%1$d of %2$d categories")
          }
        }
      }
      internal enum More {
        /// Couldn't load more
        internal static let failed = L10n.tr("Localizable", "list.more.failed", fallback: "Couldn't load more")
      }
      internal enum Offline {
        /// Showing what was already loaded. History and pages you've read still open.
        internal static let body = L10n.tr("Localizable", "list.offline.body", fallback: "Showing what was already loaded. History and pages you've read still open.")
        /// Open History
        internal static let history = L10n.tr("Localizable", "list.offline.history", fallback: "Open History")
        /// Offline · showing what was loaded
        internal static let short = L10n.tr("Localizable", "list.offline.short", fallback: "Offline · showing what was loaded")
        /// You're offline
        internal static let title = L10n.tr("Localizable", "list.offline.title", fallback: "You're offline")
      }
      internal enum Page {
        /// Page %d
        internal static func divider(_ p1: Int) -> String {
          return L10n.tr("Localizable", "list.page.divider", p1, fallback: "Page %d")
        }
        /// Go to page…
        internal static let jump = L10n.tr("Localizable", "list.page.jump", fallback: "Go to page…")
        /// %1$@ · page %2$d of %3$d
        internal static func menu(_ p1: Any, _ p2: Int, _ p3: Int) -> String {
          return L10n.tr("Localizable", "list.page.menu", String(describing: p1), p2, p3, fallback: "%1$@ · page %2$d of %3$d")
        }
        /// Next page
        internal static let next = L10n.tr("Localizable", "list.page.next", fallback: "Next page")
        /// Previous page
        internal static let previous = L10n.tr("Localizable", "list.page.previous", fallback: "Previous page")
      }
      internal enum Pages {
        /// %d p
        internal static func short(_ p1: Int) -> String {
          return L10n.tr("Localizable", "list.pages.short", p1, fallback: "%d p")
        }
      }
      internal enum Search {
        internal enum Empty {
          /// Nothing matches every term within the current search filters. Loosen one of them:
          internal static let body = L10n.tr("Localizable", "list.search.empty.body", fallback: "Nothing matches every term within the current search filters. Loosen one of them:")
          /// Search filters: %@
          internal static func filters(_ p1: Any) -> String {
            return L10n.tr("Localizable", "list.search.empty.filters", String(describing: p1), fallback: "Search filters: %@")
          }
          /// Search keeps its own filters, separate from Lists and Watched.
          internal static let note = L10n.tr("Localizable", "list.search.empty.note", fallback: "Search keeps its own filters, separate from Lists and Watched.")
          /// No galleries match
          internal static let title = L10n.tr("Localizable", "list.search.empty.title", fallback: "No galleries match")
        }
        internal enum Loosen {
          /// Include all %d categories
          internal static func categories(_ p1: Int) -> String {
            return L10n.tr("Localizable", "list.search.loosen.categories", p1, fallback: "Include all %d categories")
          }
          /// Drop the ★ %d+ minimum
          internal static func rating(_ p1: Int) -> String {
            return L10n.tr("Localizable", "list.search.loosen.rating", p1, fallback: "Drop the ★ %d+ minimum")
          }
          /// Search without %@
          internal static func term(_ p1: Any) -> String {
            return L10n.tr("Localizable", "list.search.loosen.term", String(describing: p1), fallback: "Search without %@")
          }
        }
      }
      internal enum Signin {
        /// Use cookies instead
        internal static let cookies = L10n.tr("Localizable", "list.signin.cookies", fallback: "Use cookies instead")
        /// Favorites, rating, comments and ExHentai also need an account. Browsing, search and reading work without one.
        internal static let note = L10n.tr("Localizable", "list.signin.note", fallback: "Favorites, rating, comments and ExHentai also need an account. Browsing, search and reading work without one.")
        internal enum Favorites {
          /// Sign in to see your favorites
          internal static let title = L10n.tr("Localizable", "list.signin.favorites.title", fallback: "Sign in to see your favorites")
        }
        internal enum Watched {
          /// Watched collects new galleries that match the tags you follow on your account.
          internal static let body = L10n.tr("Localizable", "list.signin.watched.body", fallback: "Watched collects new galleries that match the tags you follow on your account.")
          /// Sign in to see Watched
          internal static let title = L10n.tr("Localizable", "list.signin.watched.title", fallback: "Sign in to see Watched")
        }
      }
      internal enum Sorted {
        /// Sorted by date favorited
        internal static let favorited = L10n.tr("Localizable", "list.sorted.favorited", fallback: "Sorted by date favorited")
        /// Sorted by date posted
        internal static let posted = L10n.tr("Localizable", "list.sorted.posted", fallback: "Sorted by date posted")
      }
    }
    internal enum LoadingView {
      internal enum Title {
        /// Loading…
        internal static let loading = L10n.tr("Localizable", "loading_view.title.loading", fallback: "Loading…")
        /// Getting your data ready…
        internal static let preparingDatabase = L10n.tr("Localizable", "loading_view.title.preparing_database", fallback: "Getting your data ready…")
      }
    }
    internal enum LocalAuthorization {
      /// Unlock EhShoko to continue.
      internal static let reason = L10n.tr("Localizable", "local_authorization.reason", fallback: "Unlock EhShoko to continue.")
    }
    internal enum LoginView {
      internal enum Title {
        /// Sign in
        internal static let login = L10n.tr("Localizable", "login_view.title.login", fallback: "Sign in")
        /// Password
        internal static let password = L10n.tr("Localizable", "login_view.title.password", fallback: "Password")
        /// Username
        internal static let username = L10n.tr("Localizable", "login_view.title.username", fallback: "Username")
      }
    }
    internal enum LogsView {
      internal enum Title {
        /// Current
        internal static let latest = L10n.tr("Localizable", "logs_view.title.latest", fallback: "Current")
        /// Logs
        internal static let logs = L10n.tr("Localizable", "logs_view.title.logs", fallback: "Logs")
      }
    }
    internal enum NewDawnView {
      internal enum Title {
        /// A new day
        internal static let first = L10n.tr("Localizable", "new_dawn_view.title.first", fallback: "A new day")
        /// Your first visit today earned a reward.
        internal static let second = L10n.tr("Localizable", "new_dawn_view.title.second", fallback: "Your first visit today earned a reward.")
      }
    }
    internal enum NotLoginView {
      internal enum Button {
        /// Sign in
        internal static let login = L10n.tr("Localizable", "not_login_view.button.login", fallback: "Sign in")
      }
      internal enum Title {
        /// Sign in with your E-Hentai account to see this.
        internal static let needLogin = L10n.tr("Localizable", "not_login_view.title.need_login", fallback: "Sign in with your E-Hentai account to see this.")
      }
    }
    internal enum Offer {
      /// EhShoko comes in three. Watch each one, pick it, or mix your own. You can change it any time in Settings.
      internal static let body = L10n.tr("Localizable", "offer.body", fallback: "EhShoko comes in three. Watch each one, pick it, or mix your own. You can change it any time in Settings.")
      /// Not now
      internal static let notNow = L10n.tr("Localizable", "offer.not_now", fallback: "Not now")
      /// Choose your experience
      internal static let title = L10n.tr("Localizable", "offer.title", fallback: "Choose your experience")
      /// Use %@
      internal static func use(_ p1: Any) -> String {
        return L10n.tr("Localizable", "offer.use", String(describing: p1), fallback: "Use %@")
      }
    }
    internal enum PopularView {
      internal enum Title {
        /// Popular
        internal static let popular = L10n.tr("Localizable", "popular_view.title.popular", fallback: "Popular")
      }
    }
    internal enum PostCommentView {
      internal enum Title {
        /// Edit comment
        internal static let editComment = L10n.tr("Localizable", "post_comment_view.title.edit_comment", fallback: "Edit comment")
        /// New comment
        internal static let postComment = L10n.tr("Localizable", "post_comment_view.title.post_comment", fallback: "New comment")
      }
    }
    internal enum PreviewsView {
      internal enum Title {
        /// Previews
        internal static let previews = L10n.tr("Localizable", "previews_view.title.previews", fallback: "Previews")
      }
    }
    internal enum QuickSearchView {
      internal enum Placeholder {
        /// Optional
        internal static let `optional` = L10n.tr("Localizable", "quick_search_view.placeholder.optional", fallback: "Optional")
      }
      internal enum Title {
        /// Search terms
        internal static let content = L10n.tr("Localizable", "quick_search_view.title.content", fallback: "Search terms")
        /// Edit search
        internal static let editWord = L10n.tr("Localizable", "quick_search_view.title.edit_word", fallback: "Edit search")
        /// Name
        internal static let name = L10n.tr("Localizable", "quick_search_view.title.name", fallback: "Name")
        /// New search
        internal static let newWord = L10n.tr("Localizable", "quick_search_view.title.new_word", fallback: "New search")
        /// Quick search
        internal static let quickSearch = L10n.tr("Localizable", "quick_search_view.title.quick_search", fallback: "Quick search")
      }
    }
    internal enum Reader {
      /// Auto-play
      internal static let autoplay = L10n.tr("Localizable", "reader.autoplay", fallback: "Auto-play")
      /// End
      internal static let end = L10n.tr("Localizable", "reader.end", fallback: "End")
      /// Live Text
      internal static let liveText = L10n.tr("Localizable", "reader.live_text", fallback: "Live Text")
      /// Settings
      internal static let settings = L10n.tr("Localizable", "reader.settings", fallback: "Settings")
      internal enum Action {
        /// Save
        internal static let save = L10n.tr("Localizable", "reader.action.save", fallback: "Save")
      }
      internal enum Autoplay {
        /// every %d s
        internal static func every(_ p1: Int) -> String {
          return L10n.tr("Localizable", "reader.autoplay.every", p1, fallback: "every %d s")
        }
      }
      internal enum Closing {
        /// Comments · %d
        internal static func comments(_ p1: Int) -> String {
          return L10n.tr("Localizable", "reader.closing.comments", p1, fallback: "Comments · %d")
        }
        /// Couldn’t load
        internal static let failed = L10n.tr("Localizable", "reader.closing.failed", fallback: "Couldn’t load")
        /// Favorited
        internal static let favorited = L10n.tr("Localizable", "reader.closing.favorited", fallback: "Favorited")
        /// Gallery page
        internal static let gallery = L10n.tr("Localizable", "reader.closing.gallery", fallback: "Gallery page")
        /// The end · %d pages
        internal static func kicker(_ p1: Int) -> String {
          return L10n.tr("Localizable", "reader.closing.kicker", p1, fallback: "The end · %d pages")
        }
        /// More by %@
        internal static func more(_ p1: Any) -> String {
          return L10n.tr("Localizable", "reader.closing.more", String(describing: p1), fallback: "More by %@")
        }
        /// Sign in to rate and favorite
        internal static let signin = L10n.tr("Localizable", "reader.closing.signin", fallback: "Sign in to rate and favorite")
        internal enum Rating {
          /// Rate this gallery · average %1$@ from %2$d
          internal static func `none`(_ p1: Any, _ p2: Int) -> String {
            return L10n.tr("Localizable", "reader.closing.rating.none", String(describing: p1), p2, fallback: "Rate this gallery · average %1$@ from %2$d")
          }
          /// Your rating · average %1$@ from %2$d
          internal static func yours(_ p1: Any, _ p2: Int) -> String {
            return L10n.tr("Localizable", "reader.closing.rating.yours", String(describing: p1), p2, fallback: "Your rating · average %1$@ from %2$d")
          }
        }
      }
      internal enum Page {
        /// This page didn't load
        internal static let failed = L10n.tr("Localizable", "reader.page.failed", fallback: "This page didn't load")
        /// Page %d
        internal static func label(_ p1: Int) -> String {
          return L10n.tr("Localizable", "reader.page.label", p1, fallback: "Page %d")
        }
        /// Loading · %1$@ of %2$@
        internal static func loading(_ p1: Any, _ p2: Any) -> String {
          return L10n.tr("Localizable", "reader.page.loading", String(describing: p1), String(describing: p2), fallback: "Loading · %1$@ of %2$@")
        }
        /// Page %1$d of %2$d
        internal static func of(_ p1: Int, _ p2: Int) -> String {
          return L10n.tr("Localizable", "reader.page.of", p1, p2, fallback: "Page %1$d of %2$d")
        }
        /// Reload all %d failed pages
        internal static func reloadFailed(_ p1: Int) -> String {
          return L10n.tr("Localizable", "reader.page.reload_failed", p1, fallback: "Reload all %d failed pages")
        }
        internal enum Reason {
          /// The image server answered with error %d.
          internal static func status(_ p1: Int) -> String {
            return L10n.tr("Localizable", "reader.page.reason.status", p1, fallback: "The image server answered with error %d.")
          }
          /// The image server timed out.
          internal static let timedOut = L10n.tr("Localizable", "reader.page.reason.timed_out", fallback: "The image server timed out.")
          /// The image couldn't be read.
          internal static let unreadable = L10n.tr("Localizable", "reader.page.reason.unreadable", fallback: "The image couldn't be read.")
        }
      }
      internal enum Pages {
        /// Pages %1$d–%2$d of %3$d
        internal static func of(_ p1: Int, _ p2: Int, _ p3: Int) -> String {
          return L10n.tr("Localizable", "reader.pages.of", p1, p2, p3, fallback: "Pages %1$d–%2$d of %3$d")
        }
      }
    }
    internal enum ReadingSettingView {
      internal enum Section {
        internal enum Title {
          /// Display
          internal static let appearance = L10n.tr("Localizable", "reading_setting_view.section.title.appearance", fallback: "Display")
        }
      }
      internal enum Title {
        /// Reading direction
        internal static let direction = L10n.tr("Localizable", "reading_setting_view.title.direction", fallback: "Reading direction")
        /// Double-tap zoom
        internal static let doubleTapScaleFactor = L10n.tr("Localizable", "reading_setting_view.title.double_tap_scale_factor", fallback: "Double-tap zoom")
        /// Allow landscape
        internal static let enablesLandscape = L10n.tr("Localizable", "reading_setting_view.title.enables_landscape", fallback: "Allow landscape")
        /// Maximum zoom
        internal static let maximumScaleFactor = L10n.tr("Localizable", "reading_setting_view.title.maximum_scale_factor", fallback: "Maximum zoom")
        /// Pages to preload
        internal static let preloadLimit = L10n.tr("Localizable", "reading_setting_view.title.preload_limit", fallback: "Pages to preload")
        /// Reading
        internal static let reading = L10n.tr("Localizable", "reading_setting_view.title.reading", fallback: "Reading")
        /// Gap between pages
        internal static let separatorHeight = L10n.tr("Localizable", "reading_setting_view.title.separator_height", fallback: "Gap between pages")
      }
    }
    internal enum ReadingView {
      internal enum ContextMenu {
        internal enum Button {
          /// Copy
          internal static let copy = L10n.tr("Localizable", "reading_view.context_menu.button.copy", fallback: "Copy")
          /// Reload
          internal static let reload = L10n.tr("Localizable", "reading_view.context_menu.button.reload", fallback: "Reload")
          /// Save to Photos
          internal static let save = L10n.tr("Localizable", "reading_view.context_menu.button.save", fallback: "Save to Photos")
          /// Save original
          internal static let saveOriginal = L10n.tr("Localizable", "reading_view.context_menu.button.save_original", fallback: "Save original")
          /// Share
          internal static let share = L10n.tr("Localizable", "reading_view.context_menu.button.share", fallback: "Share")
        }
      }
      internal enum ToolbarItem {
        internal enum Button {
          /// Reader settings
          internal static let readingSetting = L10n.tr("Localizable", "reading_view.toolbar_item.button.reading_setting", fallback: "Reader settings")
          /// Reload all pages
          internal static let reloadAllImages = L10n.tr("Localizable", "reading_view.toolbar_item.button.reload_all_images", fallback: "Reload all pages")
          /// Retry failed pages
          internal static let retryAllFailedImages = L10n.tr("Localizable", "reading_view.toolbar_item.button.retry_all_failed_images", fallback: "Retry failed pages")
        }
        internal enum Title {
          /// Two pages side by side
          internal static let dualPageMode = L10n.tr("Localizable", "reading_view.toolbar_item.title.dual_page_mode", fallback: "Two pages side by side")
          /// Cover on its own
          internal static let exceptTheCover = L10n.tr("Localizable", "reading_view.toolbar_item.title.except_the_cover", fallback: "Cover on its own")
        }
      }
    }
    internal enum Search {
      /// Search by title or tag
      internal static let hint = L10n.tr("Localizable", "search.hint", fallback: "Search by title or tag")
      /// Scope
      internal static let scope = L10n.tr("Localizable", "search.scope", fallback: "Scope")
      /// Suggestions
      internal static let suggestions = L10n.tr("Localizable", "search.suggestions", fallback: "Suggestions")
      /// Search titles for “%@”
      internal static func titlesFor(_ p1: Any) -> String {
        return L10n.tr("Localizable", "search.titles_for", String(describing: p1), fallback: "Search titles for “%@”")
      }
      internal enum Group {
        /// Recent
        internal static let recent = L10n.tr("Localizable", "search.group.recent", fallback: "Recent")
        /// Saved
        internal static let saved = L10n.tr("Localizable", "search.group.saved", fallback: "Saved")
        /// Tags
        internal static let tags = L10n.tr("Localizable", "search.group.tags", fallback: "Tags")
      }
      internal enum Key {
        /// Exact match
        internal static let exact = L10n.tr("Localizable", "search.key.exact", fallback: "Exact match")
        /// Exclude
        internal static let exclude = L10n.tr("Localizable", "search.key.exclude", fallback: "Exclude")
        /// Insert %@
        internal static func insert(_ p1: Any) -> String {
          return L10n.tr("Localizable", "search.key.insert", String(describing: p1), fallback: "Insert %@")
        }
      }
      internal enum Link {
        /// A link is on the clipboard
        internal static let body = L10n.tr("Localizable", "search.link.body", fallback: "A link is on the clipboard")
        /// Open
        internal static let `open` = L10n.tr("Localizable", "search.link.open", fallback: "Open")
        /// Open copied link
        internal static let title = L10n.tr("Localizable", "search.link.title", fallback: "Open copied link")
      }
      internal enum Scope {
        /// Everywhere
        internal static let everywhere = L10n.tr("Localizable", "search.scope.everywhere", fallback: "Everywhere")
        /// Favorites
        internal static let favorites = L10n.tr("Localizable", "search.scope.favorites", fallback: "Favorites")
        /// Sign in to search here
        internal static let signin = L10n.tr("Localizable", "search.scope.signin", fallback: "Sign in to search here")
        /// Watched
        internal static let watched = L10n.tr("Localizable", "search.scope.watched", fallback: "Watched")
      }
      internal enum Token {
        /// Not %@
        internal static func excluded(_ p1: Any) -> String {
          return L10n.tr("Localizable", "search.token.excluded", String(describing: p1), fallback: "Not %@")
        }
      }
    }
    internal enum SearchView {
      internal enum Section {
        internal enum Title {
          /// Quick search
          internal static let quickSearch = L10n.tr("Localizable", "search_view.section.title.quick_search", fallback: "Quick search")
          /// Recently viewed
          internal static let recentlySeen = L10n.tr("Localizable", "search_view.section.title.recently_seen", fallback: "Recently viewed")
        }
      }
      internal enum Title {
        /// Search
        internal static let search = L10n.tr("Localizable", "search_view.title.search", fallback: "Search")
      }
    }
    internal enum Searchable {
      internal enum Prompt {
        /// Filter titles
        internal static let filter = L10n.tr("Localizable", "searchable.prompt.filter", fallback: "Filter titles")
      }
    }
    internal enum SettingView {
      internal enum Title {
        /// Settings
        internal static let setting = L10n.tr("Localizable", "setting_view.title.setting", fallback: "Settings")
      }
    }
    internal enum Settings {
      /// Experience
      internal static let design = L10n.tr("Localizable", "settings.design", fallback: "Experience")
      internal enum Account {
        /// Cookies
        internal static let cookies = L10n.tr("Localizable", "settings.account.cookies", fallback: "Cookies")
        /// Signed in
        internal static let signedIn = L10n.tr("Localizable", "settings.account.signed_in", fallback: "Signed in")
        /// Not signed in
        internal static let signedOut = L10n.tr("Localizable", "settings.account.signed_out", fallback: "Not signed in")
        /// Site account settings
        internal static let site = L10n.tr("Localizable", "settings.account.site", fallback: "Site account settings")
        internal enum SignedIn {
          /// Signed in · %@ Credits
          internal static func credits(_ p1: Any) -> String {
            return L10n.tr("Localizable", "settings.account.signed_in.credits", String(describing: p1), fallback: "Signed in · %@ Credits")
          }
        }
        internal enum SignedOut {
          /// Favorites, Watched, rating, comments and ExHentai need an account
          internal static let body = L10n.tr("Localizable", "settings.account.signed_out.body", fallback: "Favorites, Watched, rating, comments and ExHentai need an account")
        }
      }
      internal enum Design {
        /// Accent color
        internal static let accent = L10n.tr("Localizable", "settings.design.accent", fallback: "Accent color")
        /// %1$d pages changed from %2$@
        internal static func changed(_ p1: Int, _ p2: Any) -> String {
          return L10n.tr("Localizable", "settings.design.changed", p1, String(describing: p2), fallback: "%1$d pages changed from %2$@")
        }
        /// Custom
        internal static let custom = L10n.tr("Localizable", "settings.design.custom", fallback: "Custom")
        /// Customize
        internal static let customise = L10n.tr("Localizable", "settings.design.customise", fallback: "Customize")
        /// %@ on every page
        internal static func everyPage(_ p1: Any) -> String {
          return L10n.tr("Localizable", "settings.design.every_page", String(describing: p1), fallback: "%@ on every page")
        }
        /// Every combination works. Colors and type apply to the whole app, so a mix still looks like one app.
        internal static let footer = L10n.tr("Localizable", "settings.design.footer", fallback: "Every combination works. Colors and type apply to the whole app, so a mix still looks like one app.")
        /// %1$@ from %2$@
        internal static func from(_ p1: Any, _ p2: Any) -> String {
          return L10n.tr("Localizable", "settings.design.from", String(describing: p1), String(describing: p2), fallback: "%1$@ from %2$@")
        }
        /// Look
        internal static let look = L10n.tr("Localizable", "settings.design.look", fallback: "Look")
        /// Your own mix
        internal static let ownMix = L10n.tr("Localizable", "settings.design.own_mix", fallback: "Your own mix")
        /// Pages
        internal static let pages = L10n.tr("Localizable", "settings.design.pages", fallback: "Pages")
        /// Preset
        internal static let preset = L10n.tr("Localizable", "settings.design.preset", fallback: "Preset")
        /// Set up step by step
        internal static let setup = L10n.tr("Localizable", "settings.design.setup", fallback: "Set up step by step")
        internal enum Accent {
          /// Custom…
          internal static let custom = L10n.tr("Localizable", "settings.design.accent.custom", fallback: "Custom…")
          /// Look’s own
          internal static let own = L10n.tr("Localizable", "settings.design.accent.own", fallback: "Look’s own")
        }
        internal enum Bar {
          /// Menu & search
          internal static let command = L10n.tr("Localizable", "settings.design.bar.command", fallback: "Menu & search")
          /// Tabs
          internal static let tabs = L10n.tr("Localizable", "settings.design.bar.tabs", fallback: "Tabs")
        }
        internal enum Caption {
          /// How you move between lists and reach search, Continue and Settings.
          internal static let bar = L10n.tr("Localizable", "settings.design.caption.bar", fallback: "How you move between lists and reach search, Continue and Settings.")
          /// A gallery’s page and what opens from it: comments, previews, tag details.
          internal static let gallery = L10n.tr("Localizable", "settings.design.caption.gallery", fallback: "A gallery’s page and what opens from it: comments, previews, tag details.")
          /// How your favorites folders are shown.
          internal static let library = L10n.tr("Localizable", "settings.design.caption.library", fallback: "How your favorites folders are shown.")
          /// Every list of galleries: Frontpage, Watched, Toplists, History, favorites folders and search results.
          internal static let list = L10n.tr("Localizable", "settings.design.caption.list", fallback: "Every list of galleries: Frontpage, Watched, Toplists, History, favorites folders and search results.")
          /// The palette, the typefaces and the accent for the whole app, whatever the pages are.
          internal static let look = L10n.tr("Localizable", "settings.design.caption.look", fallback: "The palette, the typefaces and the accent for the whole app, whatever the pages are.")
          /// The reader’s controls. Pages are read the same way in all three.
          internal static let reader = L10n.tr("Localizable", "settings.design.caption.reader", fallback: "The reader’s controls. Pages are read the same way in all three.")
          /// Where you type a search: the field, suggestions, quick and recent searches.
          internal static let search = L10n.tr("Localizable", "settings.design.caption.search", fallback: "Where you type a search: the field, suggestions, quick and recent searches.")
          /// What you see first, before or above the first list.
          internal static let start = L10n.tr("Localizable", "settings.design.caption.start", fallback: "What you see first, before or above the first list.")
        }
        internal enum Desc {
          internal enum Bar {
            /// List menu, wide search, filters
            internal static let command = L10n.tr("Localizable", "settings.design.desc.bar.command", fallback: "List menu, wide search, filters")
            /// Four tabs and search, Continue above
            internal static let tabs = L10n.tr("Localizable", "settings.design.desc.bar.tabs", fallback: "Four tabs and search, Continue above")
          }
          internal enum Gallery {
            /// A fact table, tags as text
            internal static let ledger = L10n.tr("Localizable", "settings.design.desc.gallery.ledger", fallback: "A fact table, tags as text")
            /// Figures, action tiles, grouped tags
            internal static let shelf = L10n.tr("Localizable", "settings.design.desc.gallery.shelf", fallback: "Figures, action tiles, grouped tags")
            /// A cover card over its own colors
            internal static let wall = L10n.tr("Localizable", "settings.design.desc.gallery.wall", fallback: "A cover card over its own colors")
          }
          internal enum Library {
            /// A folder grid and a plain list
            internal static let ledger = L10n.tr("Localizable", "settings.design.desc.library.ledger", fallback: "A folder grid and a plain list")
            /// Folder chips over the list
            internal static let shelf = L10n.tr("Localizable", "settings.design.desc.library.shelf", fallback: "Folder chips over the list")
            /// Folders as piles of covers
            internal static let wall = L10n.tr("Localizable", "settings.design.desc.library.wall", fallback: "Folders as piles of covers")
          }
          internal enum List {
            /// Dense rows, or titles only
            internal static let ledger = L10n.tr("Localizable", "settings.design.desc.list.ledger", fallback: "Dense rows, or titles only")
            /// Detailed rows
            internal static let shelf = L10n.tr("Localizable", "settings.design.desc.list.shelf", fallback: "Detailed rows")
            /// A wall of covers, pinch for density
            internal static let wall = L10n.tr("Localizable", "settings.design.desc.list.wall", fallback: "A wall of covers, pinch for density")
          }
          internal enum Look {
            /// Warm paper, serif titles
            internal static let ledger = L10n.tr("Localizable", "settings.design.desc.look.ledger", fallback: "Warm paper, serif titles")
            /// System colors, indigo
            internal static let shelf = L10n.tr("Localizable", "settings.design.desc.look.shelf", fallback: "System colors, indigo")
            /// Monochrome, color from covers
            internal static let wall = L10n.tr("Localizable", "settings.design.desc.look.wall", fallback: "Monochrome, color from covers")
          }
          internal enum Reader {
            /// A control sheet that pulls up
            internal static let ledger = L10n.tr("Localizable", "settings.design.desc.reader.ledger", fallback: "A control sheet that pulls up")
            /// A top bar and a bottom panel
            internal static let shelf = L10n.tr("Localizable", "settings.design.desc.reader.shelf", fallback: "A top bar and a bottom panel")
            /// One cluster at the bottom
            internal static let wall = L10n.tr("Localizable", "settings.design.desc.reader.wall", fallback: "One cluster at the bottom")
          }
          internal enum Search {
            /// Namespace keys, grouped results
            internal static let ledger = L10n.tr("Localizable", "settings.design.desc.search.ledger", fallback: "Namespace keys, grouped results")
            /// Scopes on top, the field over the keys
            internal static let shelf = L10n.tr("Localizable", "settings.design.desc.search.shelf", fallback: "Scopes on top, the field over the keys")
            /// Anchored to the bottom
            internal static let wall = L10n.tr("Localizable", "settings.design.desc.search.wall", fallback: "Anchored to the bottom")
          }
          internal enum Start {
            /// An index of lists, folders, searches
            internal static let ledger = L10n.tr("Localizable", "settings.design.desc.start.ledger", fallback: "An index of lists, folders, searches")
            /// Home: Continue, Popular, Frontpage
            internal static let shelf = L10n.tr("Localizable", "settings.design.desc.start.shelf", fallback: "Home: Continue, Popular, Frontpage")
            /// Straight into the list
            internal static let wall = L10n.tr("Localizable", "settings.design.desc.start.wall", fallback: "Straight into the list")
          }
        }
        internal enum Gallery {
          /// On this page
          internal static let header = L10n.tr("Localizable", "settings.design.gallery.header", fallback: "On this page")
        }
        internal enum Lists {
          /// In lists
          internal static let header = L10n.tr("Localizable", "settings.design.lists.header", fallback: "In lists")
          /// Ledger’s rows never show tags.
          internal static let tagsNote = L10n.tr("Localizable", "settings.design.lists.tags_note", fallback: "Ledger’s rows never show tags.")
        }
        internal enum Look {
          /// Colors and type sets the palette and the typefaces. Theme chooses its light or dark version. Accent replaces the look’s own color.
          internal static let footer = L10n.tr("Localizable", "settings.design.look.footer", fallback: "Colors and type sets the palette and the typefaces. Theme chooses its light or dark version. Accent replaces the look’s own color.")
          /// Every preview in Settings is drawn in the colors chosen here.
          internal static let note = L10n.tr("Localizable", "settings.design.look.note", fallback: "Every preview in Settings is drawn in the colors chosen here.")
        }
        internal enum Option {
          /// A tap applies at once. The other pages stay as they are.
          internal static let applies = L10n.tr("Localizable", "settings.design.option.applies", fallback: "A tap applies at once. The other pages stay as they are.")
        }
        internal enum Part {
          /// Bottom bar
          internal static let bar = L10n.tr("Localizable", "settings.design.part.bar", fallback: "Bottom bar")
          /// Gallery page
          internal static let gallery = L10n.tr("Localizable", "settings.design.part.gallery", fallback: "Gallery page")
          /// Library
          internal static let library = L10n.tr("Localizable", "settings.design.part.library", fallback: "Library")
          /// Lists
          internal static let list = L10n.tr("Localizable", "settings.design.part.list", fallback: "Lists")
          /// Colors and type
          internal static let look = L10n.tr("Localizable", "settings.design.part.look", fallback: "Colors and type")
          /// Reader
          internal static let reader = L10n.tr("Localizable", "settings.design.part.reader", fallback: "Reader")
          /// Search
          internal static let search = L10n.tr("Localizable", "settings.design.part.search", fallback: "Search")
          /// First screen
          internal static let start = L10n.tr("Localizable", "settings.design.part.start", fallback: "First screen")
        }
        internal enum Setup {
          /// Apply
          internal static let apply = L10n.tr("Localizable", "settings.design.setup.apply", fallback: "Apply")
          /// Back to summary
          internal static let backToSummary = L10n.tr("Localizable", "settings.design.setup.back_to_summary", fallback: "Back to summary")
          /// Current
          internal static let current = L10n.tr("Localizable", "settings.design.setup.current", fallback: "Current")
          /// Custom · %1$d pages changed from %2$@
          internal static func customChanged(_ p1: Int, _ p2: Any) -> String {
            return L10n.tr("Localizable", "settings.design.setup.custom_changed", p1, String(describing: p2), fallback: "Custom · %1$d pages changed from %2$@")
          }
          /// Nine steps, a preview of every option
          internal static let desc = L10n.tr("Localizable", "settings.design.setup.desc", fallback: "Nine steps, a preview of every option")
          /// Next
          internal static let next = L10n.tr("Localizable", "settings.design.setup.next", fallback: "Next")
          /// This is what you already have.
          internal static let noChanges = L10n.tr("Localizable", "settings.design.setup.no_changes", fallback: "This is what you already have.")
          /// Nothing has changed yet. Tap a line to go back to that step.
          internal static let nothingYet = L10n.tr("Localizable", "settings.design.setup.nothing_yet", fallback: "Nothing has changed yet. Tap a line to go back to that step.")
          /// Skip
          internal static let skip = L10n.tr("Localizable", "settings.design.setup.skip", fallback: "Skip")
          /// So far: %@
          internal static func soFar(_ p1: Any) -> String {
            return L10n.tr("Localizable", "settings.design.setup.so_far", String(describing: p1), fallback: "So far: %@")
          }
          /// %1$d of %2$d
          internal static func step(_ p1: Int, _ p2: Int) -> String {
            return L10n.tr("Localizable", "settings.design.setup.step", p1, p2, fallback: "%1$d of %2$d")
          }
          /// Summary
          internal static let summary = L10n.tr("Localizable", "settings.design.setup.summary", fallback: "Summary")
          /// Experience setup
          internal static let title = L10n.tr("Localizable", "settings.design.setup.title", fallback: "Experience setup")
          /// %1$@ with %2$@’s colors
          internal static func withColours(_ p1: Any, _ p2: Any) -> String {
            return L10n.tr("Localizable", "settings.design.setup.with_colours", String(describing: p1), String(describing: p2), fallback: "%1$@ with %2$@’s colors")
          }
          internal enum CustomChanged {
            /// Custom · 1 page changed from %@
            internal static func one(_ p1: Any) -> String {
              return L10n.tr("Localizable", "settings.design.setup.custom_changed.one", String(describing: p1), fallback: "Custom · 1 page changed from %@")
            }
          }
          internal enum Differ {
            /// %1$d pages differ from %2$@: %3$@.
            internal static func many(_ p1: Int, _ p2: Any, _ p3: Any) -> String {
              return L10n.tr("Localizable", "settings.design.setup.differ.many", p1, String(describing: p2), String(describing: p3), fallback: "%1$d pages differ from %2$@: %3$@.")
            }
            /// One page differs from %1$@: %2$@.
            internal static func one(_ p1: Any, _ p2: Any) -> String {
              return L10n.tr("Localizable", "settings.design.setup.differ.one", String(describing: p1), String(describing: p2), fallback: "One page differs from %1$@: %2$@.")
            }
          }
          internal enum Discard {
            /// Discard
            internal static let confirm = L10n.tr("Localizable", "settings.design.setup.discard.confirm", fallback: "Discard")
            /// Keep editing
            internal static let keep = L10n.tr("Localizable", "settings.design.setup.discard.keep", fallback: "Keep editing")
            /// Discard your changes?
            internal static let title = L10n.tr("Localizable", "settings.design.setup.discard.title", fallback: "Discard your changes?")
          }
          internal enum Start {
            /// Watch how each one behaves. Pick one to change from, or keep what you have.
            internal static let body = L10n.tr("Localizable", "settings.design.setup.start.body", fallback: "Watch how each one behaves. Pick one to change from, or keep what you have.")
            /// Keep what I have
            internal static let keep = L10n.tr("Localizable", "settings.design.setup.start.keep", fallback: "Keep what I have")
            /// Choosing a preset here replaces what you picked in later steps.
            internal static let replace = L10n.tr("Localizable", "settings.design.setup.start.replace", fallback: "Choosing a preset here replaces what you picked in later steps.")
            /// Start from a preset
            internal static let title = L10n.tr("Localizable", "settings.design.setup.start.title", fallback: "Start from a preset")
          }
        }
        internal enum Stage {
          /// Pause
          internal static let pause = L10n.tr("Localizable", "settings.design.stage.pause", fallback: "Pause")
          /// Play
          internal static let play = L10n.tr("Localizable", "settings.design.stage.play", fallback: "Play")
          internal enum A11y {
            /// An index of lists that leads into dense rows. Swiping a row shows its actions. A gallery reads like a page of text, and the reader’s controls are a sheet that pulls up.
            internal static let ledger = L10n.tr("Localizable", "settings.design.stage.a11y.ledger", fallback: "An index of lists that leads into dense rows. Swiping a row shows its actions. A gallery reads like a page of text, and the reader’s controls are a sheet that pulls up.")
            /// Tabs at the bottom with a Continue bar above them. Scrolling tucks the bar away. A cover opens its gallery, and the reader has a bar at the top and a panel at the bottom.
            internal static let shelf = L10n.tr("Localizable", "settings.design.stage.a11y.shelf", fallback: "Tabs at the bottom with a Continue bar above them. Scrolling tucks the bar away. A cover opens its gallery, and the reader has a bar at the top and a panel at the bottom.")
            /// A wall of covers and one bar at the bottom. Pinching changes the size of the covers, swiping the bar changes the list, and the bar turns into the gallery’s actions. The reader has one bar that scrubs through pages.
            internal static let wall = L10n.tr("Localizable", "settings.design.stage.a11y.wall", fallback: "A wall of covers and one bar at the bottom. Pinching changes the size of the covers, swiping the bar changes the list, and the bar turns into the gallery’s actions. The reader has one bar that scrubs through pages.")
          }
          internal enum Ledger {
            /// From the Index into a list
            internal static let _1 = L10n.tr("Localizable", "settings.design.stage.ledger.1", fallback: "From the Index into a list")
            /// Swipe a row for actions
            internal static let _2 = L10n.tr("Localizable", "settings.design.stage.ledger.2", fallback: "Swipe a row for actions")
            /// A gallery reads like a page
            internal static let _3 = L10n.tr("Localizable", "settings.design.stage.ledger.3", fallback: "A gallery reads like a page")
            /// Read: pull the sheet up
            internal static let _4 = L10n.tr("Localizable", "settings.design.stage.ledger.4", fallback: "Read: pull the sheet up")
          }
          internal enum Shelf {
            /// Scroll: the bar tucks away
            internal static let _1 = L10n.tr("Localizable", "settings.design.stage.shelf.1", fallback: "Scroll: the bar tucks away")
            /// Tap a tab to switch lists
            internal static let _2 = L10n.tr("Localizable", "settings.design.stage.shelf.2", fallback: "Tap a tab to switch lists")
            /// A cover opens its gallery
            internal static let _3 = L10n.tr("Localizable", "settings.design.stage.shelf.3", fallback: "A cover opens its gallery")
            /// Read: a bar above, a panel below
            internal static let _4 = L10n.tr("Localizable", "settings.design.stage.shelf.4", fallback: "Read: a bar above, a panel below")
          }
          internal enum Wall {
            /// Pinch for bigger covers
            internal static let _1 = L10n.tr("Localizable", "settings.design.stage.wall.1", fallback: "Pinch for bigger covers")
            /// Swipe the bar to the next list
            internal static let _2 = L10n.tr("Localizable", "settings.design.stage.wall.2", fallback: "Swipe the bar to the next list")
            /// The bar becomes the actions
            internal static let _3 = L10n.tr("Localizable", "settings.design.stage.wall.3", fallback: "The bar becomes the actions")
            /// Read: drag to scrub pages
            internal static let _4 = L10n.tr("Localizable", "settings.design.stage.wall.4", fallback: "Read: drag to scrub pages")
          }
        }
      }
      internal enum Row {
        internal enum About {
          /// Version %1$@ (%2$@)
          internal static func desc(_ p1: Any, _ p2: Any) -> String {
            return L10n.tr("Localizable", "settings.row.about.desc", String(describing: p1), String(describing: p2), fallback: "Version %1$@ (%2$@)")
          }
        }
        internal enum General {
          /// Language, app icon, tags, links, lock, cache, logs
          internal static let desc = L10n.tr("Localizable", "settings.row.general.desc", fallback: "Language, app icon, tags, links, lock, cache, logs")
        }
        internal enum Laboratory {
          /// Network option for blocked regions
          internal static let desc = L10n.tr("Localizable", "settings.row.laboratory.desc", fallback: "Network option for blocked regions")
        }
        internal enum Reading {
          /// Direction, preload, two pages, gaps, zoom
          internal static let desc = L10n.tr("Localizable", "settings.row.reading.desc", fallback: "Direction, preload, two pages, gaps, zoom")
        }
      }
    }
    internal enum Shell {
      internal enum Account {
        /// Account and settings
        internal static let button = L10n.tr("Localizable", "shell.account.button", fallback: "Account and settings")
      }
      internal enum Bar {
        /// Navigation
        internal static let accessibility = L10n.tr("Localizable", "shell.bar.accessibility", fallback: "Navigation")
      }
      internal enum Continue {
        /// Continue · page %1$d of %2$d
        internal static func page(_ p1: Int, _ p2: Int) -> String {
          return L10n.tr("Localizable", "shell.continue.page", p1, p2, fallback: "Continue · page %1$d of %2$d")
        }
        /// Page %1$d of %2$d · %3$d%%
        internal static func progress(_ p1: Int, _ p2: Int, _ p3: Int) -> String {
          return L10n.tr("Localizable", "shell.continue.progress", p1, p2, p3, fallback: "Page %1$d of %2$d · %3$d%%")
        }
        /// Continue reading
        internal static let reading = L10n.tr("Localizable", "shell.continue.reading", fallback: "Continue reading")
        /// Continue
        internal static let title = L10n.tr("Localizable", "shell.continue.title", fallback: "Continue")
      }
      internal enum Library {
        /// Favorites
        internal static let favorites = L10n.tr("Localizable", "shell.library.favorites", fallback: "Favorites")
      }
      internal enum Place {
        /// Favorites
        internal static let favorites = L10n.tr("Localizable", "shell.place.favorites", fallback: "Favorites")
        /// Home
        internal static let home = L10n.tr("Localizable", "shell.place.home", fallback: "Home")
        /// Index
        internal static let index = L10n.tr("Localizable", "shell.place.index", fallback: "Index")
      }
      internal enum Search {
        /// Search
        internal static let prompt = L10n.tr("Localizable", "shell.search.prompt", fallback: "Search")
        internal enum Prompt {
          /// Search favorites
          internal static let favorites = L10n.tr("Localizable", "shell.search.prompt.favorites", fallback: "Search favorites")
          /// Search or paste a link
          internal static let link = L10n.tr("Localizable", "shell.search.prompt.link", fallback: "Search or paste a link")
          /// Search Watched
          internal static let watched = L10n.tr("Localizable", "shell.search.prompt.watched", fallback: "Search Watched")
        }
      }
      internal enum Tab {
        /// Library
        internal static let library = L10n.tr("Localizable", "shell.tab.library", fallback: "Library")
        /// Top
        internal static let top = L10n.tr("Localizable", "shell.tab.top", fallback: "Top")
        /// Watched
        internal static let watched = L10n.tr("Localizable", "shell.tab.watched", fallback: "Watched")
      }
    }
    internal enum Start {
      internal enum Ledger {
        /// %@ in all
        internal static func favoritesTotal(_ p1: Any) -> String {
          return L10n.tr("Localizable", "start.ledger.favorites_total", String(describing: p1), fallback: "%@ in all")
        }
        /// Lists
        internal static let lists = L10n.tr("Localizable", "start.ledger.lists", fallback: "Lists")
        /// Quick searches
        internal static let quickSearches = L10n.tr("Localizable", "start.ledger.quick_searches", fallback: "Quick searches")
        /// Sign in
        internal static let signIn = L10n.tr("Localizable", "start.ledger.sign_in", fallback: "Sign in")
        /// Sign in to see your favorites
        internal static let signInFavorites = L10n.tr("Localizable", "start.ledger.sign_in_favorites", fallback: "Sign in to see your favorites")
      }
      internal enum Shelf {
        /// Popular now
        internal static let popular = L10n.tr("Localizable", "start.shelf.popular", fallback: "Popular now")
        /// Couldn't load Popular
        internal static let popularFailed = L10n.tr("Localizable", "start.shelf.popular_failed", fallback: "Couldn't load Popular")
        /// See all
        internal static let seeAll = L10n.tr("Localizable", "start.shelf.see_all", fallback: "See all")
      }
    }
    internal enum Struct {
      internal enum CookieValue {
        internal enum LocalizedString {
          /// Expired
          internal static let expired = L10n.tr("Localizable", "struct.cookie_value.localized_string.expired", fallback: "Expired")
          /// Not valid
          internal static let mystery = L10n.tr("Localizable", "struct.cookie_value.localized_string.mystery", fallback: "Not valid")
          /// Not set
          internal static let `none` = L10n.tr("Localizable", "struct.cookie_value.localized_string.none", fallback: "Not set")
        }
      }
      internal enum Greeting {
        internal enum Mark {
          ///  and 
          internal static let and = L10n.tr("Localizable", "struct.greeting.mark.and", fallback: " and ")
          /// 
          internal static let end = L10n.tr("Localizable", "struct.greeting.mark.end", fallback: "")
          /// , 
          internal static let separator = L10n.tr("Localizable", "struct.greeting.mark.separator", fallback: ", ")
          /// Today's reward: 
          internal static let start = L10n.tr("Localizable", "struct.greeting.mark.start", fallback: "Today's reward: ")
        }
      }
      internal enum HathArchive {
        internal enum Price {
          /// Free
          internal static let free = L10n.tr("Localizable", "struct.hath_archive.price.free", fallback: "Free")
          /// Unavailable
          internal static let notAvailable = L10n.tr("Localizable", "struct.hath_archive.price.not_available", fallback: "Unavailable")
        }
      }
      internal enum User {
        internal enum FavoriteCategory {
          /// Favorites %@
          internal static func `default`(_ p1: Any) -> String {
            return L10n.tr("Localizable", "struct.user.favorite_category.default", String(describing: p1), fallback: "Favorites %@")
          }
        }
      }
    }
    internal enum SubSection {
      internal enum Button {
        /// See all
        internal static let showAll = L10n.tr("Localizable", "sub_section.button.show_all", fallback: "See all")
      }
    }
    internal enum TabItem {
      internal enum Title {
        /// Favorites
        internal static let favorites = L10n.tr("Localizable", "tab_item.title.favorites", fallback: "Favorites")
        /// Home
        internal static let home = L10n.tr("Localizable", "tab_item.title.home", fallback: "Home")
        /// Settings
        internal static let setting = L10n.tr("Localizable", "tab_item.title.setting", fallback: "Settings")
      }
    }
    internal enum TagDetailView {
      internal enum Section {
        internal enum Title {
          /// Images
          internal static let images = L10n.tr("Localizable", "tag_detail_view.section.title.images", fallback: "Images")
          /// Links
          internal static let links = L10n.tr("Localizable", "tag_detail_view.section.title.links", fallback: "Links")
        }
      }
    }
    internal enum Tip {
      internal enum Favorite {
        /// A tap saves to the folder you used last: %@.
        internal static func message(_ p1: Any) -> String {
          return L10n.tr("Localizable", "tip.favorite.message", String(describing: p1), fallback: "A tap saves to the folder you used last: %@.")
        }
        /// Touch and hold to choose a folder
        internal static let title = L10n.tr("Localizable", "tip.favorite.title", fallback: "Touch and hold to choose a folder")
      }
    }
    internal enum ToolbarItem {
      internal enum Button {
        /// Filters
        internal static let filters = L10n.tr("Localizable", "toolbar_item.button.filters", fallback: "Filters")
        /// Quick search
        internal static let quickSearch = L10n.tr("Localizable", "toolbar_item.button.quick_search", fallback: "Quick search")
      }
    }
    internal enum ToplistsView {
      internal enum Title {
        /// Toplists
        internal static let toplists = L10n.tr("Localizable", "toplists_view.title.toplists", fallback: "Toplists")
      }
    }
    internal enum TorrentsView {
      internal enum Title {
        /// Torrents
        internal static let torrents = L10n.tr("Localizable", "torrents_view.title.torrents", fallback: "Torrents")
      }
    }
    internal enum WatchedView {
      internal enum Title {
        /// Watched
        internal static let watched = L10n.tr("Localizable", "watched_view.title.watched", fallback: "Watched")
      }
    }
    internal enum Website {
      internal enum Response {
        /// This needs an H@H client linked to your account.
        internal static let hathClientNotFound = L10n.tr("Localizable", "website.response.hath_client_not_found", fallback: "This needs an H@H client linked to your account.")
        /// Your H@H client seems to be offline. Start it, then try again.
        internal static let hathClientNotOnline = L10n.tr("Localizable", "website.response.hath_client_not_online", fallback: "Your H@H client seems to be offline. Start it, then try again.")
        /// This gallery can't be downloaded at the chosen resolution.
        internal static let invalidResolution = L10n.tr("Localizable", "website.response.invalid_resolution", fallback: "This gallery can't be downloaded at the chosen resolution.")
      }
    }
  }
}
// swiftlint:enable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:enable nesting type_body_length type_name vertical_whitespace_opening_braces

// MARK: - Implementation Details

extension L10n {
  private static func tr(_ table: String, _ key: String, _ args: CVarArg..., fallback value: String) -> String {
    let format = BundleToken.bundle.localizedString(forKey: key, value: value, table: table)
    return String(format: format, locale: Locale.current, arguments: args)
  }
}

// swiftlint:disable convenience_type
private final class BundleToken {
  static let bundle: Bundle = {
    #if SWIFT_PACKAGE
    return Bundle.module
    #else
    return Bundle(for: BundleToken.self)
    #endif
  }()
}
// swiftlint:enable convenience_type
