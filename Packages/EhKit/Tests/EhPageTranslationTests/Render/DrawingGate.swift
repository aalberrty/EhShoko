import Testing

/// Lets one test of the drawing suites run at a time.
///
/// These tests analyse and draw pages pixel by pixel, which an unoptimised build does slowly.
/// Side by side on every core they starve the timing tests of the package's other targets;
/// one at a time they keep to one core and leave the rest free.
actor DrawingGate {
    static let shared = DrawingGate()

    /// Set while a test holds the gate, so a scope inside another does not wait for itself.
    @TaskLocal static var isHeld = false

    private var isTaken = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        if isTaken {
            await withCheckedContinuation { waiting.append($0) }
        } else {
            isTaken = true
        }
    }

    /// Hands the gate to the test that has waited longest, or opens it.
    func leave() {
        if waiting.isEmpty {
            isTaken = false
        } else {
            waiting.removeFirst().resume()
        }
    }
}

struct OneDrawingTestAtATime: SuiteTrait, TestTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(
        for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void
    ) async throws {
        guard !DrawingGate.isHeld else { return try await function() }
        await DrawingGate.shared.enter()
        do {
            try await DrawingGate.$isHeld.withValue(true) { try await function() }
        } catch {
            await DrawingGate.shared.leave()
            throw error
        }
        await DrawingGate.shared.leave()
    }
}

extension Trait where Self == OneDrawingTestAtATime {
    /// The suite's tests run one at a time, among themselves and with every other suite
    /// that asks for the same.
    static var oneDrawingTestAtATime: Self { Self() }
}
