import Foundation
import Network

// What the model store asks the system: how much room there is, and whether there is a
// network.

extension ModelStoreEnvironment {
    /// The bytes the system would free for something the user asked for.
    public static let volumeFreeSpace: @Sendable (URL) -> Int64 = { folder in
        let values = try? folder.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey
        ])
        return values?.volumeAvailableCapacityForImportantUsage ?? Int64(values?.volumeAvailableCapacity ?? 0)
    }

    /// Whether the device has a network, from the system's path monitor.
    public static let networkPath: @Sendable () -> AsyncStream<Bool> = {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { continuation.yield($0.status == .satisfied) }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "EhCore.ModelStoreConnectivity", qos: .utility))
        }
    }
}
