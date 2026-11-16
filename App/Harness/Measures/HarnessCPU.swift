#if DEBUG || HARNESS
import Darwin
import Foundation

/// CPU time and process age for the probes that measure a screen from inside the app (the
/// offer after install, the setup wizard).
nonisolated enum HarnessCPU {
    /// The process's and the calling thread's CPU time over `seconds`, in ms per second:
    /// "over 3.0 s: CPU 12.3 ms/s (main thread 4.5 ms/s)". Call it on the main actor for the
    /// main thread's share. The rates are over the time that really passed, since a suspended
    /// app's timer fires late.
    @MainActor
    static func sample(for seconds: Double) async -> String {
        let process = processSeconds()
        let main = callingThreadSeconds()
        let start = Date.now
        try? await Task.sleep(for: .seconds(seconds))
        let elapsed = max(Date.now.timeIntervalSince(start), .ulpOfOne)
        let processRate = (processSeconds() - process) / elapsed * 1_000
        let mainRate = (callingThreadSeconds() - main) / elapsed * 1_000
        return String(format: "over %.1f s: CPU %.1f ms/s (main thread %.1f ms/s)", elapsed, processRate, mainRate)
    }

    /// The whole process's CPU time, user and system, in seconds.
    static func processSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    /// The calling thread's CPU time, user and system, in seconds.
    static func callingThreadSeconds() -> Double {
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let thread = pthread_mach_thread_np(pthread_self())
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return 0 }
        let user = Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1_000_000
        let system = Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1_000_000
        return user + system
    }

    /// Seconds since the process was created, as the kernel recorded it.
    static func sinceProcessStart() -> Double {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0 else { return 0 }
        let start = info.kp_proc.p_starttime
        let started = Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000
        return Date.now.timeIntervalSince1970 - started
    }

    /// The app's memory footprint, "123.45 MB".
    static func footprint() -> String {
        guard let footprint = MemoryFootprint.current() else { return "unknown" }
        return String(format: "%.2f MB", Double(footprint.current) / 1_048_576)
    }

    private static func seconds(_ value: timeval) -> Double {
        Double(value.tv_sec) + Double(value.tv_usec) / 1_000_000
    }
}
#endif
