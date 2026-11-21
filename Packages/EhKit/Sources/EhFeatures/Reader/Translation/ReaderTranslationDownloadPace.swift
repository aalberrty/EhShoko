import EhCore

/// The time left of a download, from how its bytes moved while the sheet watched: the store
/// gives bytes, not a rate (`MT6`'s report, section 8).
///
/// The rate is the average since the bytes were first seen, measured up to the latest report.
/// The background transport delivers ranges in bursts with quiet time between them; an
/// average over the whole span counts that quiet time, so a burst does not make the estimate
/// jump. Nothing is said until the bytes have been watched for `settling`, and the estimate
/// starts again when the download stops, or when its total or its bytes go back past where
/// watching started.
nonisolated public struct ReaderTranslationDownloadPace: Sendable {
    /// How long the bytes must be watched before a time is given.
    public static let settling: Duration = .seconds(5)

    private struct Sample: Sendable {
        var bytes: Int64
        var time: ContinuousClock.Instant
    }

    private var start: Sample?
    private var latest: Sample?
    private var totalBytes: Int64 = 0

    public init() {}

    /// Notes the progress at `time`; `nil` while no bytes are arriving.
    public mutating func note(_ progress: ModelTransferProgress?, at time: ContinuousClock.Instant) {
        guard let progress else {
            start = nil
            latest = nil
            return
        }
        let sample = Sample(bytes: progress.completedBytes, time: time)
        // A range that failed takes its bytes back; they count as not moved, which is what
        // the time left needs, unless they go back past the start.
        if let start, progress.totalBytes == totalBytes, sample.bytes >= start.bytes {
            latest = sample
        } else {
            start = sample
            latest = nil
            totalBytes = progress.totalBytes
        }
    }

    /// The time left in whole minutes, at least one, once the bytes have been watched long
    /// enough to tell: seconds would change at every report.
    public func remaining(of progress: ModelTransferProgress) -> Duration? {
        guard let start, let latest else { return nil }
        let elapsed = latest.time - start.time
        let moved = latest.bytes - start.bytes
        guard elapsed >= Self.settling, moved > 0 else { return nil }
        let seconds: Double = elapsed / Duration.seconds(1)
        let rate = Double(moved) / seconds
        let left = Double(max(0, progress.totalBytes - progress.completedBytes)) / rate
        let minutes = max(1, (left / 60).rounded(.up))
        // A rate of a few bytes a minute gives a time no one could read; there is none to give.
        guard minutes < 100_000 else { return nil }
        return .seconds(Int64(minutes) * 60)
    }
}
