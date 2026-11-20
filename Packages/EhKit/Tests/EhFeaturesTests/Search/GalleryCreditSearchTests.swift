@testable import EhFeatures
import EhModels
import Testing

@Suite struct GalleryCreditSearchTests {
    private func tag(_ namespace: String, _ texts: String...) -> GalleryTag {
        GalleryTag(rawNamespace: namespace, contents: texts.map {
            GalleryTag.Content(rawNamespace: namespace, text: $0, isVotedUp: false, isVotedDown: false, backgroundColor: nil)
        })
    }

    @Test func theCircleAndTheArtistsSearchTheirTagsWhenTheGalleryHasThem() {
        var gallery = Gallery.stub("1", title: "(C102) [Summer Gang (Hoshino Kanae, Someone Else)] Title")
        gallery.tags = [tag("group", "summer gang"), tag("artist", "hoshino kanae")]

        let targets = GalleryCreditSearch.targets(for: GalleryEntry(gallery: gallery))

        #expect(targets == [
            GalleryCreditSearch(name: "Summer Gang", keyword: #"g:"summer gang$""#, kind: .circle),
            GalleryCreditSearch(name: "Hoshino Kanae", keyword: #"a:"hoshino kanae$""#, kind: .artist),
            GalleryCreditSearch(name: "Someone Else", keyword: #""Someone Else""#, kind: .artist)
        ])
    }

    @Test func atMostThreeArtistsAndNoNameTwice() {
        let gallery = Gallery.stub("1", title: "[Solo (Solo, B, C, D)] Title")
        let targets = GalleryCreditSearch.targets(for: GalleryEntry(gallery: gallery))
        #expect(targets.map(\.name) == ["Solo", "B", "C"])
        #expect(targets.map(\.kind) == [.circle, .artist, .artist])
    }

    @Test func aTitleNamingNobodyHasNoSearches() {
        #expect(GalleryCreditSearch.targets(for: GalleryEntry(gallery: .stub("1", title: "Just a title"))).isEmpty)
    }
}
