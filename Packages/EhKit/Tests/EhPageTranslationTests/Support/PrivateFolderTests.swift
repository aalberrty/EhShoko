import Foundation
import Testing

@Suite struct PrivateFolderTests {
    @Test func theVariableNamesTheFolder() {
        #expect(PrivateFolder.named(in: [:]) == nil)
        #expect(PrivateFolder.named(in: ["PAGE_TRANSLATION_PRIVATE": ""]) == nil)
        #expect(PrivateFolder.named(in: ["PAGE_TRANSLATION_PRIVATE": "  \n"]) == nil)
        #expect(PrivateFolder.named(in: ["PAGE_TRANSLATION_PRIVATE": "/tmp/x"])?.root.path == "/tmp/x")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(PrivateFolder.named(in: ["PAGE_TRANSLATION_PRIVATE": "~/x"])?.root.path == home + "/x")
    }

    @Test func aMissingFileFailsInsteadOfSkipping() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "private-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "pages"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appending(path: "pages/b.PNG"))
        try Data().write(to: root.appending(path: "pages/a.png"))
        try Data().write(to: root.appending(path: "pages/notes.txt"))
        let folder = PrivateFolder(root: root)
        #expect(try folder.url("pages").lastPathComponent == "pages")
        #expect(throws: PrivateFolder.Missing.self) { try folder.url("models/none.mlpackage") }
        #expect(try folder.files(in: "pages", withExtensions: ["png"]).map(\.lastPathComponent) == ["a.png", "b.PNG"])
    }
}
