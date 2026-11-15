import EhModels
import Kingfisher
import UIKit

/// Why an image did not load, told in the terms the site's requests use (`AppError`), so a
/// page that failed either way says why in the same words.
nonisolated enum ReaderImageFailure {
    /// The reason for an error of `ImagePipeline.image(for:…)`; `nil` when it says nothing
    /// a reader could act on.
    static func reason(for error: any Error) -> AppError? {
        switch error {
        case is ImagePipelineError:
            // The bytes arrived but are not an image the system can read.
            return .parseFailed
        case let error as KingfisherError:
            switch error {
            case .responseError(reason: .invalidHTTPStatusCode(let response)):
                return .serverError(response.statusCode)
            case .responseError(reason: .URLSessionError(let underlying)):
                return reason(for: underlying)
            default:
                return nil
            }
        case is URLError:
            return .networkingFailed
        default:
            return nil
        }
    }
}

// `Error` types stay nonisolated under the target's default isolation; this reads `L10n`.
@MainActor
extension AppError {
    /// The line under "This page didn't load": what went wrong, in a sentence or two, without
    /// the "try again later" that full-screen errors add (the card's Retry says that).
    var readerPageReason: String? {
        typealias Strings = L10n.Localizable.ErrorView
        switch self {
        case .networkingFailed: return Strings.Title.network
        case .serverError(let status): return Strings.Title.serverError("\(status)")
        case .parseFailed: return Strings.Headline.parseFailed
        case .notFound: return Strings.Title.notFound
        case .loginRequired: return Strings.Headline.loginRequired
        case .exhentaiAccessDenied: return Strings.Headline.exhentaiAccessDenied
        case .unknown: return Strings.Title.unknown
        case .ipBanned, .copyrightClaim, .expunged: return alertText
        case .databaseCorrupted, .noUpdates, .webImageFailed: return nil
        }
    }
}
