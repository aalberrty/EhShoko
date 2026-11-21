import CoreGraphics
import EhModels
import EhPageTranslation
import EhTestSupport
import Foundation
import Testing
@testable import EhCore

/// The stages an environment has when none is given: the real ones, which the service's
/// other tests replace. They are run here because they were once wrong without anyone
/// calling them: written as default arguments, their closures were miscompiled.
@Suite struct PageTranslationEnvironmentTests {
    static func environment() async throws -> PageTranslationEnvironment {
        let database = try await TestDatabase.inMemory()
        return PageTranslationEnvironment(
            setup: { nil }, imageData: { _ in Data() },
            loadPipeline: { _ in throw PageTranslatorError.unavailable(.hyMT2) },
            writer: PageTranslationResultWriter(database: database, logger: .console()),
            patchStore: PageTranslationPatchStore(directory: URL.temporaryDirectory.appending(path: UUID().uuidString)),
            logger: .console()
        )
    }

    @Test func theRealDecoderDecodesSkipsAndRefuses() async throws {
        let environment = try await Self.environment()
        // From this task and from one of another priority: the miscompiled closure gave
        // different answers in the two.
        for priority in [TaskPriority.userInitiated, .utility] {
            let results = await Task(priority: priority) { () -> [String] in
                var results: [String] = []
                for data in [TranslationWorld.png(of: 1), TranslationWorld.gif, Data("not an image".utf8)] {
                    do {
                        let bitmap = try await environment.decode(data)
                        results.append("\(bitmap.width) x \(bitmap.height)")
                    } catch let error as PageBitmapError {
                        results.append(error == .animated ? "animated" : "unreadable")
                    } catch {
                        results.append("\(error)")
                    }
                }
                return results
            }.value
            #expect(results == ["41 x 64", "animated", "unreadable"])
        }
        let bitmap = try await environment.decode(TranslationWorld.png(of: 2))
        #expect(bitmap.width == 42 && bitmap.height == 64)
    }

    @Test func theRealRendererDrawsAStoredPage() async throws {
        let environment = try await Self.environment()
        let bitmap = try await environment.decode(TranslationWorld.png(of: 60))
        // White paper and a box of text that is not there: the renderer has nothing to find
        // and still answers with what it drew, which is all this asks of it.
        let drawing = try await environment.draw(TranslationWorld.storedPage(60), bitmap, nil)
        #expect(drawing.patches.count <= 1 && drawing.failedRepaints == 0)
        #expect(drawing.patches.allSatisfy { $0.rect.x1 <= bitmap.width && $0.rect.y1 <= bitmap.height })
    }

    @Test func theRealRepaintModelRefusesAFileThatIsNoModel() async throws {
        let environment = try await Self.environment()
        await #expect(throws: (any Error).self) {
            _ = try await environment.loadInpainter(URL(fileURLWithPath: "/nowhere/LaMa.mlmodelc"), .cpuOnly)
        }
    }

    @Test func thePhonesStatesAreTheSystems() async throws {
        let environment = try await Self.environment()
        await environment.prepare()
        #expect(environment.heat() == PageTranslationHeat(ProcessInfo.processInfo.thermalState))
        #expect(environment.isLowPowerModeEnabled() == ProcessInfo.processInfo.isLowPowerModeEnabled)
        #expect(abs(environment.now().timeIntervalSinceNow) < 60)
    }
}
