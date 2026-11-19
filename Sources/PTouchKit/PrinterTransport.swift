/// A byte pipe to a printer: USB, Bluetooth, network, or a test double.
///
/// Implementations live outside the core target, which stays free of
/// platform frameworks. See `PTouchKitTransports` for macOS.
public protocol PrinterTransport: Sendable {
    /// Connects. Calling it on an open transport does nothing.
    func open() async throws
    /// Sends all of `bytes`.
    func write(_ bytes: [UInt8]) async throws
    /// Returns up to `count` bytes, waiting at most `timeout` for the first
    /// ones to arrive. Returns an empty array if nothing arrived.
    func read(upTo count: Int, timeout: Duration) async throws -> [UInt8]
    /// Disconnects. Safe to call more than once.
    func close() async
}

public enum PrinterClientError: Error, Equatable, Sendable {
    /// The printer sent nothing before the timeout.
    case noReply
    /// The printer sent part of a status reply, then stopped.
    case incompleteReply([UInt8])
    /// The printer reported an error while printing.
    case printerError(PrinterStatus)
}

/// Talks to a printer over any transport: asks for status and sends jobs,
/// following the status flow in Raster Command Reference §1 and §5.
public struct PrinterClient<Transport: PrinterTransport>: Sendable {
    public let transport: Transport

    public init(transport: Transport) {
        self.transport = transport
    }

    /// Resets the printer's receive state and asks for its status (§4 "ESC i S").
    /// Don't call it while a job is printing.
    public func status(timeout: Duration = .seconds(5)) async throws -> PrinterStatus {
        let reset = [UInt8](repeating: 0x00, count: 100) + [0x1B, 0x40]
        try await transport.write(reset + statusRequestCommand)
        guard let status = try await readStatus(timeout: timeout) else { throw PrinterClientError.noReply }
        return status
    }

    /// Sends an encoded job and waits until the printer reports every page
    /// printed. Each status the printer sends is passed to `onStatus`.
    ///
    /// - Parameter pages: how many "printing completed" replies to wait for.
    /// - Throws: `PrinterClientError.printerError` if the printer reports an error.
    @discardableResult
    public func print(
        _ job: [UInt8],
        pages: Int = 1,
        timeout: Duration = .seconds(60),
        onStatus: @Sendable (PrinterStatus) -> Void = { _ in }
    ) async throws -> PrinterStatus {
        try await transport.write(job)
        var completed = 0
        while true {
            guard let status = try await readStatus(timeout: timeout) else { throw PrinterClientError.noReply }
            onStatus(status)
            switch status.statusType {
            case .errorOccurred:
                throw PrinterClientError.printerError(status)
            case .printingCompleted:
                completed += 1
                if completed >= pages { return status }
            default:
                continue
            }
        }
    }

    /// Reads one 32-byte status reply, or `nil` if nothing arrives in time.
    func readStatus(timeout: Duration) async throws -> PrinterStatus? {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        var bytes: [UInt8] = []
        while bytes.count < PrinterStatus.byteCount {
            let remaining = deadline - clock.now
            guard remaining > .zero else { break }
            bytes += try await transport.read(upTo: PrinterStatus.byteCount - bytes.count, timeout: remaining)
        }
        if bytes.isEmpty { return nil }
        guard bytes.count == PrinterStatus.byteCount else { throw PrinterClientError.incompleteReply(bytes) }
        return try PrinterStatus(bytes: bytes)
    }
}
