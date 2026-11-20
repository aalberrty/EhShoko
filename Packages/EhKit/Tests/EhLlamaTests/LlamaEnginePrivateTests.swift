import EhLlama
import Foundation
import Synchronization
import Testing

/// The opt-in tier: a real model file through the Mac slice of the library (`PrivateModels`).
/// Serialized, because each test maps more than a gigabyte and uses every core it is given.
@Suite(.serialized) struct LlamaEnginePrivateTests {
    /// The smallest model file loads, generates 20 tokens, and a stop flag set at the fifth
    /// token of a second run ends that run there. Once on the CPU alone and once with every
    /// layer on the GPU; the times are printed for the task's report.
    @Test(.privateModels, .timeLimit(.minutes(30)), arguments: [LlamaConfiguration.Device.cpu, .gpu])
    func theSmallestModelLoadsGeneratesAndStops(on device: LlamaConfiguration.Device) async throws {
        let model = try PrivateModels.smallest()
        let log = Mutex<[String]>([])
        LlamaLog.setSink { line in log.withLock { $0.append(line) } }
        defer { LlamaLog.setSink(nil) }

        let clock = ContinuousClock()
        let loadStart = clock.now
        let engine = try await LlamaEngine.load(modelAt: model.url, configuration: LlamaConfiguration(device: device))
        let loadTime = clock.now - loadStart
        let info = try await engine.info
        #expect(info.parameterCount > 100_000_000)
        #expect(info.contextLength == 1024)

        let text = "こんにちは、世界。今日はいい天気ですね。"
        let prompt = try await engine.tokenize(text, addingSpecial: true)
        #expect(!prompt.isEmpty)
        #expect(try await engine.text(of: prompt).contains("今日はいい天気"))

        let options = LlamaGenerationOptions(maxTokens: 20, ignoresEndOfGeneration: true)
        let generated = try await engine.generate(prompt: prompt, options: options)
        #expect(generated.finish == .tokenLimit)
        #expect(generated.tokens.count == 20)
        // The likeliest token each time: the same run gives the same tokens.
        let again = try await engine.generate(prompt: prompt, options: options)
        #expect(again.tokens == generated.tokens)

        let stop = LlamaStopFlag()
        let stopStart = Mutex<ContinuousClock.Instant?>(nil)
        let stopped = try await engine.generate(
            prompt: prompt, options: LlamaGenerationOptions(maxTokens: 200, ignoresEndOfGeneration: true), stop: stop
        ) { count in
            guard count == 5 else { return }
            stopStart.withLock { $0 = clock.now }
            stop.stop()
        }
        let stopTime = stopStart.withLock { $0 }.map { clock.now - $0 }
        #expect(stopped.finish == .stopped)
        #expect(stopped.tokens.count == 5)

        await engine.unload()
        #expect(await engine.isLoaded == false)

        let lines = log.withLock { $0 }
        let marks = ["offloaded", "using device", "ggml_metal_init: picking", "GPU name"]
        let hardware = lines.filter { line in marks.contains { line.contains($0) } }
        print("""
        EhLlama opt-in, \(model.url.lastPathComponent) (\(model.bytes / 1_000_000) MB), on the \(device):
          \(info.summary), \(info.parameterCount / 1_000_000) M parameters
          load \(loadTime), prompt of \(prompt.count) tokens \(generated.promptDuration), \
        20 tokens \(generated.generationDuration), second run \(again.generationDuration)
          stop at token 5 returned after \(stopTime.map { "\($0)" } ?? "?") with \(stopped.tokens.count) tokens
          text: \(generated.text.replacingOccurrences(of: "\n", with: " "))
          \(hardware.joined(separator: "\n  "))
        """)
    }
}
