import UIKit
import XCTest

/// What happened in one walk. Attached to the test as `walk-result.json`, which
/// `run_walks.sh` reads for its table.
struct WalkRecord: Codable, Sendable {
    struct StepTime: Codable, Sendable {
        var name: String
        var seconds: Double
        var passed: Bool
    }

    var walk: String
    var title: String
    var device: String
    var passed = false
    /// The step that failed, with the groups it was in, and why.
    var failedStep: String?
    var reason: String?
    var seconds: Double = 0
    var steps: [StepTime] = []
    var screenshots: [String] = []
    /// Optional steps that failed without failing the walk.
    var notes: [String] = []

    @MainActor
    init(walk: Walk) {
        self.walk = walk.id
        title = walk.title
        device = Self.deviceDescription
    }

    mutating func fail(_ failure: WalkFailure) {
        passed = false
        if failedStep == nil {
            failedStep = failure.step
            reason = failure.reason
        }
    }

    @MainActor
    var attachment: XCTAttachment {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = (try? encoder.encode(self)) ?? Data()
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "\(walk)__walk-result"
        attachment.lifetime = .keepAlways
        return attachment
    }

    /// "iPad8,7 · iPadOS 26.7.3", or the simulated model on a simulator.
    @MainActor
    static var deviceDescription: String {
        let environment = ProcessInfo.processInfo.environment
        var model = environment["SIMULATOR_MODEL_IDENTIFIER"].map { "\($0) simulator" } ?? ""
        if model.isEmpty {
            var system = utsname()
            uname(&system)
            model = withUnsafeBytes(of: &system.machine) { bytes in
                String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            }
        }
        let device = UIDevice.current
        return "\(model) · \(device.systemName) \(device.systemVersion)"
    }
}
