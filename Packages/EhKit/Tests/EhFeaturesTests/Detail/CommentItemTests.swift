import EhFeatures
import EhTestSupport
import Testing

@MainActor
@Suite struct CommentItemUploaderTests {
    /// The site gives the uploader's comment the id "0".
    @Test func theUploadersCommentIsMarked() async throws {
        let env = try await DetailEnvironment()
        let model = await env.loadedDetailModel()
        let comments = model.comments
        #expect(comments.count > 1)
        #expect(comments.first?.id == "0")
        #expect(comments.first?.isUploaderComment == true)
        #expect(comments.dropFirst().allSatisfy { !$0.isUploaderComment })
    }
}
