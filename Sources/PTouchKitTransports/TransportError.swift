import PTouchKit

public enum TransportError: Error, CustomStringConvertible, Sendable {
    case notFound(String)
    case openFailed(String)
    case writeFailed(String)
    case notOpen

    public var description: String {
        switch self {
        case .notFound(let s): "Printer not found: \(s)"
        case .openFailed(let s): "Couldn't connect: \(s)"
        case .writeFailed(let s): "Couldn't send: \(s)"
        case .notOpen: "The connection isn't open"
        }
    }
}
