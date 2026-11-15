import Foundation

/// What a downloaded model does in page translation.
public enum ModelRole: String, Codable, Sendable, Hashable, CaseIterable {
    /// Finds text and balloons on a page.
    case detector
    /// Reads the Japanese in one block.
    case reader
    /// Translates one block's Japanese into Chinese.
    case translator
    /// Redraws artwork behind text that is not in a balloon.
    case repaint
}

/// One model with the files it needs, as the model catalog names it (`det-k2xl-768`, …).
///
/// A struct rather than an enum, so that the generated catalog and a stored list of installed
/// files can name an artifact this build does not know without failing to decode.
public struct ModelArtifactID: RawRepresentable, Codable, Sendable, Hashable, Comparable,
    CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String { rawValue }
}

extension ModelArtifactID {
    // Detectors
    public static let k2xl = ModelArtifactID("det-k2xl-768")
    public static let yolo26s = ModelArtifactID("det-yolo26s")
    public static let v4s = ModelArtifactID("det-v4s")
    public static let rtmdet2 = ModelArtifactID("det-rtmdet2")
    // Readers
    public static let cpt2 = ModelArtifactID("ocr-cpt2")
    public static let narSmall = ModelArtifactID("ocr-nar-small")
    // Translators
    public static let jmtFast1 = ModelArtifactID("mt-jmt-fast-1")
    public static let galTransl4B = ModelArtifactID("mt-galtransl-v4-4b")
    public static let sakura1_5B = ModelArtifactID("mt-sakura-1.5b")
    public static let hyMT2 = ModelArtifactID("mt-hy-mt2-1.8b")
    public static let qwen35_4B = ModelArtifactID("mt-qwen3.5-4b")
    // Repaint
    public static let lamaManga = ModelArtifactID("inp-lama-manga")
    public static let bigLama = ModelArtifactID("inp-big-lama")
}
