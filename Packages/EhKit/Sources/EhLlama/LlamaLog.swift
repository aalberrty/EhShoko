import Foundation
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
        install()
        state.withLock {
            $0.sink = sink
            $0.partial = ""
        }
    }

    private static let installed: Void = {
        llama_log_set({ _, text, _ in
            guard let text else { return }
            LlamaLog.receive(text)
        }, nil)
    }()

    /// Takes the log away from stderr. Cheap, and safe before llama.cpp is started.
    static func install() {
        _ = installed
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
    /// The number of Metal devices llama.cpp may open, read by it from the environment.
    static let metalDevicesVariable = "GGML_METAL_DEVICES"

    private static let started: Void = {
        LlamaLog.install()
        #if arch(x86_64) || targetEnvironment(simulator)
        // The GPU is never the right choice here (`LlamaConfiguration.Device.preferred`), and
        // llama.cpp's Metal backend compiles its three dozen shader libraries when it starts:
        // seconds on Apple silicon, minutes on a busy Intel Mac. With no Metal device it does
        // not start at all. A value already in the environment is left alone.
        setenv(metalDevicesVariable, "0", 0)
        #endif
        llama_backend_init()
    }()

    /// Starts llama.cpp once for the process. It is never shut down: that would only matter
    /// to a process that goes on without it.
    ///
    /// The first call can take long (see above), so it is only ever made on an engine's own
    /// queue, never on the caller's thread.
    static func start() {
        _ = started
    }
}
