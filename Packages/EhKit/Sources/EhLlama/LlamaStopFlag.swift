import Synchronization

/// Ends a generation from any thread. The engine looks at it before every token and, through
/// llama.cpp's abort callback, while a step is being computed, so generation ends within
/// one token of `stop()`. A flag that was set stays set: use a new one for the next call.
public final class LlamaStopFlag: Sendable {
    private let stopped = Atomic<Bool>(false)

    public init() {}

    public func stop() {
        stopped.store(true, ordering: .relaxed)
    }

    public var isStopped: Bool {
        stopped.load(ordering: .relaxed)
    }
}

/// The flags one generation listens to: the caller's, and one set when its task is cancelled.
final class StopSignal: Sendable {
    private let flags: [LlamaStopFlag]

    init(_ flags: [LlamaStopFlag]) {
        self.flags = flags
    }

    var isSet: Bool {
        flags.contains { $0.isStopped }
    }
}
