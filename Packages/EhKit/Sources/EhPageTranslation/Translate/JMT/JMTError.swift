/// A translator file that is not what the code ports: the wrong file, or another release.
/// Raised while loading, before any line is translated, except `missingOutput`.
public enum JMTError: Error, Equatable, CustomStringConvertible {
    /// A file that cannot be read as what it should be; carries the file and why.
    case badFile(String, String)
    /// A file of a kind this port does not reproduce exactly.
    case unsupported(String)
    /// A network returned no output of this name, or a smaller one than its description said.
    case missingOutput(String)

    public var description: String {
        switch self {
        case let .badFile(file, reason): "\(file): \(reason)"
        case let .unsupported(what): "unsupported: \(what)"
        case let .missingOutput(name): "model output \(name) missing"
        }
    }
}
