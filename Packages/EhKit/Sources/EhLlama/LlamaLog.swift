import Synchronization
import llama

/// llama.cpp's own log: a few hundred lines for each load (the file's metadata, buffer sizes,
/// the Metal device). Left alone it goes to stderr; here it is dropped unless a sink is set.
/// The log belongs to the process, not to an engine.
public enum LlamaLog {
    public typealias Sink = @Sendable (_ line: String) -> Void

    private struct State {
        var sink: Sink?
        var partial = ""
    }

    private static let state = Mutex(State())

    /// Sends every following line to `sink`, from whichever thread llama.cpp writes it on.
    /// `nil` drops the lines again.
    public static func setSink(_ sink: Sink?) {
        LlamaBackend.start()
        state.withLock {
            $0.sink = sink
            $0.partial = ""
        }
    }

    static func install() {
        llama_log_set({ _, text, _ in
            guard let text else { return }
            LlamaLog.receive(text)
        }, nil)
    }

    private static func receive(_ text: UnsafePointer<CChar>) {
        // llama.cpp sends one line in several calls; they are joined before a line is passed on.
        let (sink, lines) = state.withLock { state -> (Sink?, [String]) in
            guard let sink = state.sink else { return (nil, []) }
            state.partial += String(cString: text)
            guard state.partial.hasSuffix("\n") else { return (sink, []) }
            let lines = state.partial.split(separator: "\n").map(String.init)
            state.partial = ""
            return (sink, lines)
        }
        // Outside the lock, so a sink may itself call `setSink`.
        guard let sink else { return }
        for line in lines { sink(line) }
    }
}

enum LlamaBackend {
    private static let started: Void = {
        LlamaLog.install()
        llama_backend_init()
    }()

    /// Starts llama.cpp once for the process. It is never shut down: that would only matter
    /// to a process that goes on without it.
    static func start() {
        _ = started
    }
}
