import EhModels
import Kingfisher
import UIKit

/// Why an image did not load. Images come from the image server, not the site's pages, so
/// the card says so in its own words; a page whose image URL could not be resolved says why
/// in the site's (`AppError.readerPageReason`).
nonisolated enum ReaderImageFailure: Equatable, Sendable {
    case timedOut
    case unreachable
    /// The server answered with this HTTP status instead of the image.
    case status(Int)
    /// The bytes arrived but are not an image the system can read.
    case unreadable

    /// The reason for an error of `ImagePipeline.image(for:…)`; `nil` when it says nothing
    /// a reader could act on.
    init?(_ error: any Error) {
        switch error {
        case is ImagePipelineError:
            self = .unreadable
        case let error as KingfisherError:
            switch error {
            case .responseError(reason: .invalidHTTPStatusCode(let response)):
                self = .status(response.statusCode)
            case .responseError(reason: .URLSessionError(let underlying)):
                guard let reason = Self(underlying) else { return nil }
                self = reason
            default:
                return nil
            }
        case let error as URLError:
            self = error.code == .timedOut ? .timedOut : .unreachable
        default:
            return nil
        }
    }
}

@MainActor
extension ReaderImageFailure {
    /// The line under "This page didn't load".
    var text: String {
        switch self {
        case .timedOut: L10n.Localizable.Reader.Page.Reason.timedOut
        case .unreachable: L10n.Localizable.ErrorView.Title.network
        case .status(let status): L10n.Localizable.Reader.Page.Reason.status(status)
        case .unreadable: L10n.Localizable.Reader.Page.Reason.unreadable
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
