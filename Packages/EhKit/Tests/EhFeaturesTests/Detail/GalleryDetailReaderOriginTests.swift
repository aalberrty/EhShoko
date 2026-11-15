import EhFeatures
import EhModels
import EhTestSupport
import Foundation
import Testing

/// What opened the reader, for the zoom that grows out of it.
@MainActor
@Suite struct GalleryDetailReaderOriginTests {
    @Test func readOpensFromTheReadButton() async throws {
        let env = try await DetailEnvironment()
        let model = env.makeDetailModel()
        await model.load()
        model.openReader(page: 4)
        model.read()
        #expect(model.destination == .reader(page: nil))
        #expect(model.readerOrigin == .readButton)
    }

    @Test func aPreviewOpensFromItself() async throws {
        let env = try await DetailEnvironment()
        let model = env.makeDetailModel()
        model.openReader(page: 7)
        #expect(model.destination == .reader(page: 7))
        #expect(model.readerOrigin == .preview(page: 7))
    }

    /// "Read again" opens page 1 from the pill, which page 1's preview must not be taken for.
    @Test func readAgainOpensFromTheReadButton() async throws {
        let env = try await DetailEnvironment()
        try await env.database.updateReadingProgress(gid: DetailEnvironment.gid, progress: 156)
        let model = env.makeDetailModel()
        await model.load()
        model.openReader(page: 1)
        #expect(model.readerOrigin == .preview(page: 1))
        model.read()
        #expect(model.destination == .reader(page: 1))
        #expect(model.readerOrigin == .readButton)
    }

    @Test func aLinkToAPageOpensFromTheReadButton() async throws {
        let env = try await DetailEnvironment()
        let model = await env.loadedDetailModel(intent: .read(page: 12))
        await pollUntil { model.destination == .reader(page: 12) }
        #expect(model.readerOrigin == .readButton)
    }
}
