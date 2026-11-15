import EhModels
import Foundation
import Testing
@testable import EhCore

/// The download of one file as a state machine: ranges, the part file, the checksum, the
/// order of sources and what each answer does. The transport is a stub; the files and
/// their SHA-256 are real.
@Suite struct ModelDownloaderTests {
    private let root = StoreSamples.temporaryFolder()
    private let transport = StubModelTransport()
    private let waits = Shared<[Duration]>([])
    private let reports = Shared<[Int64]>([])

    /// 10,500 bytes: ten whole ranges of 1,024 and one of 260.
    private let data = StoreSamples.bytes(10_500, seed: 42)
    private let first = URL(string: "https://one.example/files/model.gguf")!
    private let second = URL(string: "https://two.example/files/model.gguf")!

    private var file: ModelFile { ModelFile("model.gguf", Int64(data.count), StoreSamples.sha256(data)) }
    private var layout: ModelStoreLayout { ModelStoreLayout(root: root) }
    private var destination: URL { layout.url(of: file, in: .galTransl4B) }
    private var part: URL { layout.partURL(of: file, in: .galTransl4B) }

    private func downloader(slots: Int = 96) -> ModelDownloader {
        ModelDownloader(
            transport: transport, layout: layout, chunkSize: StoreSamples.chunkSize, slots: ModelWorkSlots(slots),
            sleep: { [waits] duration in waits.update { $0.append(duration) } }
        )
    }

    private func job(_ sources: [URL], token: String? = nil) -> ModelFileJob {
        ModelFileJob(
            artifact: .galTransl4B, file: file,
            sources: sources.map { ModelFileSource(kind: .privateStore, url: $0, token: token) }
        )
    }

    private var progress: ModelDownloadProgress {
        ModelDownloadProgress(interval: .zero) { [reports] _, bytes in reports.update { $0.append(bytes) } }
    }

    private func leftovers() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: layout.folder(of: .galTransl4B).path(percentEncoded: false))) ?? [])
            .sorted()
    }

    private func ranges(to url: URL) -> [Range<Int64>] {
        transport.requests.filter { $0.url == url }.map(\.range).sorted { $0.lowerBound < $1.lowerBound }
    }

    // MARK: Ranges

    @Test func aFileArrivesInRangesAndIsPutTogetherInOrder() async throws {
        transport.publish(data, at: first)

        try await downloader().download(job([first]), progress: progress)

        #expect(try Data(contentsOf: destination) == data)
        let asked = ranges(to: first)
        #expect(asked.count == 11)
        #expect(asked.first == 0..<1024)
        #expect(asked.last == 10_240..<10_500)
        #expect(asked.dropLast().allSatisfy { $0.count == 1024 })
        // Nothing of the download is left beside the file.
        #expect(leftovers() == ["model.gguf"])
        #expect(reports.get().last == Int64(data.count))
        #expect(transport.mainThreadCalls == 0)
    }

    @Test func rangesAreCutAtTheChunkSize() {
        let downloader = downloader()
        #expect(downloader.chunkRanges(of: ModelFile("a", 1024, "")) == [0..<1024])
        #expect(downloader.chunkRanges(of: ModelFile("a", 1025, "")) == [0..<1024, 1024..<1025])
        #expect(downloader.chunkRanges(of: ModelFile("a", 1, "")) == [0..<1])
        #expect(ModelStoreEnvironment.standardChunkSize == 32 * 1024 * 1024)
    }

    @Test func withOneSlotRangesStillArriveInOrder() async throws {
        transport.publish(data, at: first)

        try await downloader(slots: 1).download(job([first]), progress: progress)

        #expect(try Data(contentsOf: destination) == data)
        #expect(transport.requests.count == 11)
    }

    // MARK: Going on

    /// The part file is the state: its length says which range comes next, and ranges
    /// that arrived before their turn are used, not fetched again.
    @Test func aDownloadGoesOnFromItsPartFile() async throws {
        transport.publish(data, at: first)
        try FileManager.default.createDirectory(at: part.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Three whole ranges and 100 bytes of the fourth, cut off when the app was killed.
        try data.prefix(3 * 1024 + 100).write(to: part)
        // The sixth range arrived on its own.
        try data.subdata(in: 5 * 1024..<6 * 1024).write(to: layout.chunkURL(of: file, in: .galTransl4B, index: 5))
        #expect(downloader().bytesOnDisk(of: file, in: .galTransl4B) == 4 * 1024)

        try await downloader().download(job([first]), progress: progress)

        #expect(try Data(contentsOf: destination) == data)
        let asked = ranges(to: first).map(\.lowerBound)
        #expect(asked == [3, 4, 6, 7, 8, 9, 10].map { Int64($0) * 1024 })
        #expect(leftovers() == ["model.gguf"])
    }

    @Test func aPartThatIsAlreadyWholeAsksForNothing() async throws {
        try FileManager.default.createDirectory(at: part.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: part)

        try await downloader().download(job([first]), progress: progress)

        #expect(try Data(contentsOf: destination) == data)
        #expect(transport.requests.isEmpty)
    }

    @Test func cancellingKeepsWhatArrived() async throws {
        transport.publish(data, at: first)
        transport.hang(first, from: 4 * 1024)
        let downloader = downloader()
        let job = job([first])
        let progress = progress
        let download = Task { try await downloader.download(job, progress: progress) }
        while downloader.bytesOnDisk(of: file, in: .galTransl4B) < 4 * 1024 {
            try await Task.sleep(for: .milliseconds(5))
        }

        download.cancel()
        await #expect(throws: CancellationError.self) { try await download.value }

        #expect(!FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)))
        #expect(downloader.bytesOnDisk(of: file, in: .galTransl4B) == 4 * 1024)
        // Going on fetches only what is missing.
        transport.release(first)
        transport.clearRequests()
        try await downloader.download(job, progress: progress)
        #expect(try Data(contentsOf: destination) == data)
        #expect(ranges(to: first).map(\.lowerBound) == (4...10).map { Int64($0) * 1024 })
    }

    // MARK: The checksum

    @Test func aWrongChecksumMovesToTheNextSource() async throws {
        var wrong = data
        wrong[7000] ^= 0x01
        transport.publish(wrong, at: first)
        transport.publish(data, at: second)

        try await downloader().download(job([first, second]), progress: progress)

        #expect(try Data(contentsOf: destination) == data)
        // The whole file was fetched from each: nothing of the wrong one was kept.
        #expect(ranges(to: first).count == 11)
        #expect(ranges(to: second).count == 11)
        #expect(leftovers() == ["model.gguf"])
    }

    @Test func aWrongChecksumEverywhereStopsAndLeavesNothing() async throws {
        var wrong = data
        wrong[0] ^= 0x80
        transport.publish(wrong, at: first)
        transport.publish(wrong, at: second)

        await #expect(throws: ModelStoreFailure.checksumMismatch) {
            try await downloader().download(job([first, second]), progress: progress)
        }

        #expect(leftovers().isEmpty)
        #expect(reports.get().last == 0)
    }

    /// A file of the right length and the wrong content is refused, whatever it is.
    @Test func aFileOfTheRightSizeAndTheWrongBytesIsRefused() async throws {
        transport.publish(Data(repeating: 0, count: data.count), at: first)

        await #expect(throws: ModelStoreFailure.checksumMismatch) {
            try await downloader().download(job([first]), progress: progress)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)))
    }

    /// Bytes left by an earlier run may be what was wrong. The source they were blamed on
    /// gets one more try from nothing before the download gives up on it.
    @Test func aSpoiledPartFileDoesNotCondemnTheSource() async throws {
        transport.publish(data, at: first)
        try FileManager.default.createDirectory(at: part.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0xAA, count: 2 * 1024).write(to: part)

        try await downloader().download(job([first]), progress: progress)

        #expect(try Data(contentsOf: destination) == data)
        // Nine ranges after the spoiled two, then all eleven again.
        #expect(ranges(to: first).count == 9 + 11)
    }

    // MARK: Sources

    @Test(arguments: [403, 404, 500, 503])
    func anAnswerWithoutTheFileMovesToTheNextSource(status: Int) async throws {
        transport.script([.status(status)], at: first)
        transport.publish(data, at: second)

        try await downloader(slots: 1).download(job([first, second]), progress: progress)

        #expect(try Data(contentsOf: destination) == data)
        // The first source was asked, answered without the file, and was not waited for.
        #expect(transport.requests.contains { $0.url == first })
        #expect(ranges(to: second).count == 11)
        #expect(waits.get().isEmpty)
    }

    @Test func aTimeoutMovesToTheNextSource() async throws {
        transport.script([.error(.timedOut)], at: first)
        transport.publish(data, at: second)

        try await downloader(slots: 1).download(job([first, second]), progress: progress)

        #expect(try Data(contentsOf: destination) == data)
    }

    /// What the first source delivered before it failed is not fetched again.
    @Test func theNextSourceGoesOnWhereTheFirstStopped() async throws {
        transport.publish(data, at: first)
        transport.publish(data, at: second)
        // One request at a time: three ranges arrive, the fourth is refused.
        let downloader = downloader(slots: 1)
        let job = job([first, second])
        transport.hang(first, from: 3 * 1024)
        let progress = progress
        let download = Task { try await downloader.download(job, progress: progress) }
        while downloader.bytesOnDisk(of: file, in: .galTransl4B) < 3 * 1024 {
            try await Task.sleep(for: .milliseconds(5))
        }
        download.cancel()
        _ = try? await download.value
        transport.release(first)
        transport.withdraw(first)
        transport.clearRequests()

        try await downloader.download(job, progress: progress)

        #expect(try Data(contentsOf: destination) == data)
        #expect(ranges(to: second).map(\.lowerBound) == (3...10).map { Int64($0) * 1024 })
    }

    @Test func whenEverySourceRefusesTheLastAnswerIsReported() async throws {
        transport.script([.status(403)], at: first)

        await #expect(throws: ModelStoreFailure.refused(status: 404)) {
            try await downloader(slots: 1).download(job([first, second]), progress: progress)
        }
    }

    @Test func whenNoSourceCanBeReachedThatIsReported() async throws {
        transport.script([.error(.cannotFindHost)], at: first)
        transport.script([.error(.networkConnectionLost)], at: second)

        await #expect(throws: ModelStoreFailure.unreachable) {
            try await downloader(slots: 1).download(job([first, second]), progress: progress)
        }
    }

    @Test func aFileWithNoSourceFailsAtOnce() async throws {
        await #expect(throws: ModelStoreFailure.noSource) {
            try await downloader().download(job([]), progress: progress)
        }
        #expect(transport.requests.isEmpty)
    }

    // MARK: Too many requests

    /// A 429 waits as long as the server's header says and asks the same source again.
    @Test func a429WaitsAsLongAsTheServerSays() async throws {
        transport.publish(data, at: first)
        transport.publish(data, at: second)
        transport.script([.status(429, retryAfter: .seconds(7)), .status(429, retryAfter: nil)], at: first)

        try await downloader(slots: 1).download(job([first, second]), progress: progress)

        #expect(try Data(contentsOf: destination) == data)
        #expect(waits.get() == [.seconds(7), .seconds(5)])
        #expect(transport.requests.allSatisfy { $0.url == first })
    }

    @Test func aWaitIsNeverLongerThanTwoMinutes() async throws {
        transport.publish(data, at: first)
        transport.script([.status(429, retryAfter: .seconds(86_400))], at: first)

        try await downloader(slots: 1).download(job([first]), progress: progress)

        #expect(waits.get() == [.seconds(120)])
    }

    @Test func aSourceThatKeepsAskingToWaitIsGivenUp() async throws {
        transport.script(Array(repeating: .status(429, retryAfter: .seconds(1)), count: 6), at: first)
        transport.publish(data, at: second)

        try await downloader(slots: 1).download(job([first, second]), progress: progress)

        #expect(waits.get().count == 5)
        #expect(ranges(to: second).count == 11)
    }

    // MARK: The token

    @Test func theTokenTravelsWithEachRequestToItsSource() async throws {
        transport.publish(data, at: first)

        try await downloader().download(job([first], token: StoreSamples.token), progress: progress)

        #expect(transport.requests.allSatisfy { $0.token == StoreSamples.token && $0.url == first })
    }

    // MARK: Progress

    @Test func progressCountsWhatIsOnDiskAndOnItsWay() {
        let reports = Shared<[Int64]>([])
        let progress = ModelDownloadProgress(interval: .zero) { _, bytes in reports.update { $0.append(bytes) } }

        progress.settle("a", bytes: 2048)
        progress.arrived("a", chunk: 2, bytes: 512)
        progress.arrived("b", chunk: 0, bytes: 100)
        progress.arrived("a", chunk: 2, bytes: 1024)
        progress.settle("a", bytes: 3072, clearingChunk: 2)
        progress.settle("b", bytes: 0)

        #expect(reports.get() == [2048, 2560, 2660, 3172, 3172, 3072])
    }

    @Test func progressIsReportedAFewTimesASecondAtMost() {
        let reports = Shared<[Int64]>([])
        let progress = ModelDownloadProgress(interval: .seconds(3600)) { _, bytes in reports.update { $0.append(bytes) } }

        for bytes in 1...500 { progress.arrived("a", chunk: 0, bytes: Int64(bytes)) }
        #expect(reports.get() == [1])
        // What is settled is always said.
        progress.settle("a", bytes: 1024, clearingChunk: 0)
        #expect(reports.get() == [1, 1024])
    }

    // MARK: Hashing

    /// Asked from the main actor, a download still puts its file together and hashes it
    /// elsewhere: a report is made by the task that has just appended and hashed a range.
    @Test @MainActor func puttingAFileTogetherAndHashingItRunOffTheMainActor() async throws {
        transport.publish(data, at: first)
        let onMainThread = Shared<[Bool]>([])
        let progress = ModelDownloadProgress(interval: .zero) { _, _ in
            onMainThread.update { $0.append(isOnMainThread()) }
        }

        try await downloader().download(job([first]), progress: progress)

        #expect(onMainThread.get().count >= 11)
        #expect(!onMainThread.get().contains(true))
        #expect(transport.mainThreadCalls == 0)
        #expect(try Data(contentsOf: destination) == data)
    }

    @Test func aFilesChecksumIsReadInBlocks() async throws {
        let url = root.appending(path: "big.bin")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let big = StoreSamples.bytes(3 * ModelChecksum.blockSize + 17, seed: 9)
        try big.write(to: url)

        #expect(try await ModelChecksum.sha256(of: url) == StoreSamples.sha256(big))
    }

    @Test func aPartFileIsCutBackToWholeRangesAndHashedAgain() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appending(path: "file.part")
        try data.prefix(2 * 1024 + 300).write(to: url)

        let part = try ModelPartFile(url: url, chunkSize: 1024, fileSize: Int64(data.count))
        #expect(part.length == 2048)
        let chunk = root.appending(path: "chunk")
        try data.subdata(in: 2048..<3072).write(to: chunk)
        try part.append(contentsOf: chunk)

        #expect(part.length == 3072)
        #expect(try part.finish() == StoreSamples.sha256(data.prefix(3072)))
        #expect(try Data(contentsOf: url) == data.prefix(3072))
    }

    @Test func aPartFileLongerThanItsFileStartsOver() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appending(path: "file.part")
        try Data(count: 5000).write(to: url)

        let part = try ModelPartFile(url: url, chunkSize: 1024, fileSize: 4096)
        #expect(part.length == 0)
        part.close()
    }
}
