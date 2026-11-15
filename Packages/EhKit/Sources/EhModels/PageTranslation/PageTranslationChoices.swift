import Foundation

// The models the user chooses for page translation. A choice's raw value is its name in the
// table of measured figures and in preferences, and never changes. `key` names a model's
// results in the cache and changes whenever the model would give different results.

/// The model that finds text and balloons on a page.
public enum TextDetectorChoice: String, Codable, Sendable, Hashable, CaseIterable {
    /// KoharuLayout RF-DETR-Seg-2XL at 768 × 768.
    case k2xl
    /// Koharu YOLO26s.
    case yolo26s
    /// ogkalu comic-text-and-bubble-detector v4-s.
    case v4s
    /// RTMDet, which finds lines rather than blocks.
    case rtmdet2

    public static let `default`: Self = .k2xl

    public var artifact: ModelArtifactID {
        switch self {
        case .k2xl: .k2xl
        case .yolo26s: .yolo26s
        case .v4s: .v4s
        case .rtmdet2: .rtmdet2
        }
    }

    public var key: String {
        switch self {
        case .k2xl: "k2xl768"
        case .yolo26s: "yolo26s"
        case .v4s: "v4s"
        case .rtmdet2: "rtmdet2"
        }
    }
}

/// The model that reads the Japanese in a block.
public enum TextReaderChoice: String, Codable, Sendable, Hashable, CaseIterable {
    /// manga-ocr-base CPT v2.
    case cpt2
    /// manga-ocr-nar-small.
    case narSmall

    public static let `default`: Self = .cpt2

    public var artifact: ModelArtifactID {
        switch self {
        case .cpt2: .cpt2
        case .narSmall: .narSmall
        }
    }

    public var key: String {
        switch self {
        case .cpt2: "cpt2"
        case .narSmall: "narsmall"
        }
    }
}

/// The model that translates the Japanese of a page into Chinese.
///
/// Every choice the measurements describe is a case. Which of them the app offers is the
/// model catalog's business: a translator is offered once it has an entry there.
public enum TranslatorChoice: String, Codable, Sendable, Hashable, CaseIterable {
    /// JMangaTranslator-Fast v1, on Core ML.
    case jmtFast1
    /// GalTransl v4 4B, a language model.
    case galTransl4B
    /// Sakura 1.5B, a language model.
    case sakura1_5B
    /// Hy-MT2 1.8B, a language model.
    case hyMT2
    /// Qwen3.5 4B, a language model.
    case qwen35_4B

    public static let `default`: Self = .jmtFast1

    public var artifact: ModelArtifactID {
        switch self {
        case .jmtFast1: .jmtFast1
        case .galTransl4B: .galTransl4B
        case .sakura1_5B: .sakura1_5B
        case .hyMT2: .hyMT2
        case .qwen35_4B: .qwen35_4B
        }
    }

    public var key: String {
        switch self {
        case .jmtFast1: "jmt1"
        case .galTransl4B: "galtransl4b"
        case .sakura1_5B: "sakura15b"
        case .hyMT2: "hymt2"
        case .qwen35_4B: "qwen354b"
        }
    }
}

/// What redraws artwork behind text that is not in a balloon.
public enum RepaintChoice: String, Codable, Sendable, Hashable, CaseIterable {
    /// No model: the same smooth fill as in balloons.
    case off
    /// lama_large_512px, trained for manga.
    case lamaManga
    /// big-lama, a general model.
    case bigLama

    /// The repaint model is part of the default download.
    public static let `default`: Self = .lamaManga

    /// The model to download, or `nil` when nothing is needed.
    public var artifact: ModelArtifactID? {
        switch self {
        case .off: nil
        case .lamaManga: .lamaManga
        case .bigLama: .bigLama
        }
    }

    /// Names the drawn patches, beside the model set's key: changing the repaint choice draws
    /// pages again and keeps their text.
    public var key: String {
        switch self {
        case .off: "fill"
        case .lamaManga: "lamamanga"
        case .bigLama: "biglama"
        }
    }
}

/// The detector, reader and translator a page's text was made with. The repaint choice is not
/// part of it: it only changes how the text is drawn.
public struct PageTranslationModelSet: Sendable, Hashable {
    public var detector: TextDetectorChoice
    public var reader: TextReaderChoice
    public var translator: TranslatorChoice

    public init(
        detector: TextDetectorChoice = .default,
        reader: TextReaderChoice = .default,
        translator: TranslatorChoice = .default
    ) {
        self.detector = detector
        self.reader = reader
        self.translator = translator
    }

    public static let `default` = PageTranslationModelSet()

    /// The version of the rules that turn the detector's output into blocks. Raise it when
    /// they change, so results made under the old rules are not found again.
    public static let groupingVersion = 1

    /// Names a page's stored text: detector, reader, translator and grouping rules, such as
    /// `k2xl768.cpt2.jmt1.t1`. Only letters, digits and dots, so it is also a file name.
    public var key: String {
        "\(detector.key).\(reader.key).\(translator.key).t\(Self.groupingVersion)"
    }

    /// The artifacts the set needs: detector, reader and translator.
    public var artifacts: [ModelArtifactID] {
        [detector.artifact, reader.artifact, translator.artifact]
    }
}
