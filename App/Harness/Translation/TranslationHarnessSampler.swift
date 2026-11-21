#if DEBUG || HARNESS
import Darwin
import Foundation
import Metal
import Synchronization

/// The app's memory, the GPU's and the memory left, sampled every 50 ms on a thread of its
/// own for the whole run. Each page takes the highest and lowest values seen while it was in
/// work (`takeWindow`); the run keeps its own.
nonisolated final class TranslationHarnessSampler: Sendable {
    struct Sample: Sendable, Codable, Equatable {
        /// `phys_footprint`, what the system ends an app for.
        var footprint: UInt64 = 0
        var footprintPeak: UInt64 = 0
        /// Metal's `currentAllocatedSize` for this process: the repaint model and a language
        /// model live there.
        var gpu: UInt64 = 0
        var gpuPeak: UInt64 = 0
        /// `os_proc_available_memory()`, the least seen: how close the app came to its limit.
        /// `nil` on a simulator, where the call has no limit to report.
        var availableLeast: UInt64?
    }

    private struct State {
        var window = Sample()
        var run = Sample()
    }

    static let period = Duration.milliseconds(50)

    private let state = Mutex(State())
    private let device = MTLCreateSystemDefaultDevice()
    private let task = Mutex<Task<Void, Never>?>(nil)

    func start() {
        let first = now()
        state.withLock { $0 = State(window: first, run: first) }
        let task = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled, let self {
                self.sample()
                try? await Task.sleep(for: Self.period)
            }
        }
        self.task.withLock { $0 = task }
    }

    func stop() {
        task.withLock { $0?.cancel(); $0 = nil }
    }

    deinit { stop() }

    /// The values since the last call, and the current ones as the start of the next window.
    func takeWindow() -> Sample {
        sample()
        let current = now()
        return state.withLock { state in
            let window = state.window
            state.window = current
            return window
        }
    }

    var run: Sample {
        sample()
        return state.withLock { $0.run }
    }

    /// One reading, without keeping it.
    func now() -> Sample {
        var sample = Sample()
        if let footprint = MemoryFootprint.current() {
            sample.footprint = footprint.current
            sample.footprintPeak = footprint.current
        }
        sample.gpu = UInt64(device?.currentAllocatedSize ?? 0)
        sample.gpuPeak = sample.gpu
        let available = UInt64(os_proc_available_memory())
        sample.availableLeast = available > 0 ? available : nil
        return sample
    }

    /// The process's own record of its highest footprint since it started.
    static var lifetimePeak: UInt64 { MemoryFootprint.current()?.peak ?? 0 }

    private func sample() {
        let reading = now()
        state.withLock { state in
            state.window.merge(reading)
            state.run.merge(reading)
        }
    }
}

nonisolated extension TranslationHarnessSampler.Sample {
    mutating func merge(_ reading: Self) {
        footprint = reading.footprint
        footprintPeak = max(footprintPeak, reading.footprint)
        gpu = reading.gpu
        gpuPeak = max(gpuPeak, reading.gpu)
        if let available = reading.availableLeast { availableLeast = min(availableLeast ?? available, available) }
    }
}

/// Memory held and written to for a whole run, standing in for a full image cache.
nonisolated final class TranslationHarnessBallast: Sendable {
    private let pages: Mutex<[UnsafeMutableRawBufferPointer]>

    init(megabytes: Int) {
        var pages: [UnsafeMutableRawBufferPointer] = []
        for _ in 0..<megabytes {
            let page = UnsafeMutableRawBufferPointer.allocate(byteCount: 1 << 20, alignment: 16_384)
            // Written to, so the memory is resident and dirty like decoded bitmaps.
            page.initializeMemory(as: UInt8.self, repeating: 0x5A)
            pages.append(page)
        }
        self.pages = Mutex(pages)
    }

    deinit {
        pages.withLock { pages in
            for page in pages { page.deallocate() }
            pages = []
        }
    }
}
#endif
