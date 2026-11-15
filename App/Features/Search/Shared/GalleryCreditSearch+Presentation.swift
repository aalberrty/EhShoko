import EhFeatures

extension GalleryCreditSearch {
    /// The symbol beside "Search <name>", in SF Symbols 6.
    var systemImage: String {
        switch kind {
        case .circle: "person.2"
        case .artist: "paintbrush.pointed"
        }
    }
}
