import EhCore
import EhFeatures
import Testing

@Suite struct ReaderTranslationDownloadPaceTests {
    private let start = ContinuousClock.now
    private static let megabyte: Int64 = 1_000_000
    private static let total = 1_200 * megabyte

    private func at(_ seconds: Double) -> ContinuousClock.Instant {
        start + .milliseconds(Int64(seconds * 1_000))
    }

    private func progress(_ megabytes: Int64, of total: Int64 = total) -> ModelTransferProgress {
        ModelTransferProgress(completedBytes: megabytes * Self.megabyte, totalBytes: total)
    }

    private func minutes(_ value: Duration?) -> Int64? {
        value.map { $0.components.seconds / 60 }
    }

    @Test func saysNothingUntilTheBytesHaveBeenWatchedLongEnough() {
        var pace = ReaderTranslationDownloadPace()
        pace.note(progress(0), at: at(0))
        #expect(pace.remaining(of: progress(0)) == nil)
        pace.note(progress(4), at: at(4.9))
        #expect(pace.remaining(of: progress(4)) == nil)
        pace.note(progress(5), at: at(5))
        // 1 MB/s with 1,195 MB left: 19.9 minutes, rounded up.
        #expect(minutes(pace.remaining(of: progress(5))) == 20)
    }

    @Test func roundsUpToWholeMinutesAndNeverSaysLessThanOne() {
        var pace = ReaderTranslationDownloadPace()
        pace.note(progress(1_000), at: at(0))
        pace.note(progress(1_199), at: at(10))
        #expect(minutes(pace.remaining(of: progress(1_199))) == 1)
    }

    @Test func burstsGiveTheSameTimeAsASteadyStream() {
        // 2 MB/s for 60 s: steadily, four times a second; and as 32 MB ranges at once with
        // nothing in between.
        var steady = ReaderTranslationDownloadPace()
        steady.note(progress(0), at: at(0))
        for quarter in 1...240 {
            steady.note(progress(Int64(quarter) / 2), at: at(Double(quarter) / 4))
        }
        var bursts = ReaderTranslationDownloadPace()
        bursts.note(progress(0), at: at(0))
        var last: Int64 = 0
        for burst in 1...3 {
            last = Int64(burst) * 32 + (burst == 3 ? 24 : 0)
            bursts.note(progress(last), at: at(Double(last) / 2))
        }
        #expect(last == 120)
        #expect(minutes(steady.remaining(of: progress(120))) == 9)
        #expect(minutes(bursts.remaining(of: progress(120))) == 9)
    }

    @Test func theQuietTimeBeforeABurstCounts() {
        var pace = ReaderTranslationDownloadPace()
        pace.note(progress(0), at: at(0))
        // Nothing for 32 s, then a 32 MB range at once: 1 MB/s, not a burst's rate.
        pace.note(progress(32), at: at(32))
        #expect(minutes(pace.remaining(of: progress(32))) == 20)
    }

    @Test func bytesAlreadyThereWhenWatchingStartsDoNotCount() {
        var pace = ReaderTranslationDownloadPace()
        pace.note(progress(600), at: at(0))
        pace.note(progress(610), at: at(10))
        // 1 MB/s from where watching started, not 61 MB/s since the download began.
        #expect(minutes(pace.remaining(of: progress(610))) == 10)
    }

    @Test func bytesTakenBackByAFailedRangeCountAsNotMoved() {
        var pace = ReaderTranslationDownloadPace()
        pace.note(progress(100), at: at(0))
        pace.note(progress(140), at: at(8))
        pace.note(progress(110), at: at(10))
        // 10 MB in 10 s: 1 MB/s with 1,090 MB left.
        #expect(minutes(pace.remaining(of: progress(110))) == 19)
    }

    @Test func startsAgainWhenTheBytesGoBackPastTheStart() {
        var pace = ReaderTranslationDownloadPace()
        pace.note(progress(100), at: at(0))
        pace.note(progress(200), at: at(10))
        pace.note(progress(50), at: at(11))
        #expect(pace.remaining(of: progress(50)) == nil)
        pace.note(progress(60), at: at(16))
        #expect(minutes(pace.remaining(of: progress(60))) == 10)
    }

    @Test func startsAgainAfterAStop() {
        var pace = ReaderTranslationDownloadPace()
        pace.note(progress(0), at: at(0))
        pace.note(progress(100), at: at(10))
        pace.note(nil, at: at(11))
        pace.note(progress(100), at: at(60))
        pace.note(progress(102), at: at(62))
        #expect(pace.remaining(of: progress(102)) == nil)
        pace.note(progress(105), at: at(65))
        // 1 MB/s since the resume, not the 10 MB/s before the pause.
        #expect(minutes(pace.remaining(of: progress(105))) == 19)
    }

    @Test func startsAgainWhenTheTotalChanges() {
        var pace = ReaderTranslationDownloadPace()
        pace.note(progress(0), at: at(0))
        pace.note(progress(100), at: at(10))
        pace.note(progress(100, of: 2_000 * Self.megabyte), at: at(11))
        #expect(pace.remaining(of: progress(100, of: 2_000 * Self.megabyte)) == nil)
    }

    @Test func givesNoTimeWhenNothingMoved() {
        var pace = ReaderTranslationDownloadPace()
        pace.note(progress(10), at: at(0))
        pace.note(progress(10), at: at(30))
        #expect(pace.remaining(of: progress(10)) == nil)
    }
}
