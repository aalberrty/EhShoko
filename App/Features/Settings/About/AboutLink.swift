import Foundation

/// One row of the About screen. URLs and names come from `Constant.strings`.
struct AboutLink: Identifiable {
    let text: String
    let url: URL?

    var id: String { text }

    init(_ urlString: String, _ text: String) {
        self.text = text
        url = urlString.isEmpty ? nil : URL(string: urlString)
    }
}

extension AboutLink {
    private typealias App = L10n.Constant.App

    static let contacts: [AboutLink] = [
        AboutLink(App.Contact.Link.gitHub, App.Contact.Text.gitHub)
    ]

    static let specialThanks: [AboutLink] = [
        AboutLink(App.SpecialThanks.Link.ehTagTranslation, App.SpecialThanks.Text.ehTagTranslation)
    ]

    /// The libraries v2 actually uses that have strings in `Constant.strings`. Legacy-only
    /// libraries (TCA, SwiftyBeaver, AlertKit, …) are gone; GRDB and swift-dependencies have
    /// no strings yet.
    static let acknowledgements: [AboutLink] = [
        AboutLink(App.Acknowledgement.Link.kanna, App.Acknowledgement.Text.kanna),
        AboutLink(App.Acknowledgement.Link.kingfisher, App.Acknowledgement.Text.kingfisher),
        AboutLink(App.Acknowledgement.Link.swiftGen, App.Acknowledgement.Text.swiftGen),
        AboutLink(App.Acknowledgement.Link.sfSafeSymbols, App.Acknowledgement.Text.sfSafeSymbols),
        AboutLink(App.Acknowledgement.Link.swiftyOpenCC, App.Acknowledgement.Text.swiftyOpenCC)
    ]
}
