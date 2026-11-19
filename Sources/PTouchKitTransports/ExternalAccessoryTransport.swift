#if os(iOS)
import ExternalAccessory
import Foundation
import PTouchKit

/// Bluetooth connection on iOS and iPadOS through ExternalAccessory.
///
/// iOS can't open Bluetooth Classic channels directly; the P710BT is an MFi
/// accessory whose RFCOMM channel 1 speaks Apple's iAP2, and ExternalAccessory
/// carries the raster protocol over it. The app's Info.plist must list
/// `com.brother.ptcbp` in `UISupportedExternalAccessoryProtocols`. App Store
/// release also needs Brother to approve the app for its accessory.
public final class ExternalAccessoryTransport: NSObject, PrinterTransport, StreamDelegate, @unchecked Sendable {
    /// Brother's protocol string for P-touch printers.
    public static let brotherProtocol = "com.brother.ptcbp"

    public let accessory: EAAccessory
    public let protocolString: String

    private let lock = NSLock()
    private var session: EASession?
    private var received: [UInt8] = []
    private var outgoing: [UInt8] = []
    private var failure: String?

    public init(accessory: EAAccessory, protocolString: String = ExternalAccessoryTransport.brotherProtocol) {
        self.accessory = accessory
        self.protocolString = protocolString
    }

    /// Connected accessories that speak `protocolString`.
    @MainActor
    public static func connectedPrinters(protocolString: String = brotherProtocol) -> [EAAccessory] {
        EAAccessoryManager.shared().connectedAccessories.filter { $0.protocolStrings.contains(protocolString) }
    }

    public func open() async throws {
        if lock.withLock({ session != nil }) { return }
        try RunLoopThread.shared.run { [self] in
            guard accessory.isConnected else { throw TransportError.notFound("\(accessory.name) isn't connected") }
            guard let session = EASession(accessory: accessory, forProtocol: protocolString),
                  let input = session.inputStream, let output = session.outputStream else {
                throw TransportError.openFailed("no session for \(protocolString). Is it in UISupportedExternalAccessoryProtocols, and is another app using the printer?")
            }
            for stream in [input, output] as [Stream] {
                stream.delegate = self
                stream.schedule(in: .current, forMode: .default)
                stream.open()
            }
            lock.withLock {
                self.session = session
                received = []
                outgoing = []
                failure = nil
            }
        }
    }

    public func write(_ bytes: [UInt8]) async throws {
        guard lock.withLock({ session != nil }) else { throw TransportError.notOpen }
        lock.withLock { outgoing += bytes }
        try RunLoopThread.shared.run { [self] in flush() }
        // Wait until the stream has taken every byte.
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(30)
        while true {
            let (left, error) = lock.withLock { (outgoing.count, failure) }
            if let error { throw TransportError.writeFailed(error) }
            if left == 0 { return }
            if clock.now >= deadline { throw TransportError.writeFailed("timed out with \(left) bytes unsent") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    public func read(upTo count: Int, timeout: Duration) async throws -> [UInt8] {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while true {
            let (bytes, open) = lock.withLock { () -> ([UInt8], Bool) in
                let n = min(count, received.count)
                let out = Array(received[..<n])
                received.removeFirst(n)
                return (out, session != nil)
            }
            if !bytes.isEmpty { return bytes }
            if !open { throw TransportError.notOpen }
            if clock.now >= deadline { return [] }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    public func close() async {
        let session: EASession? = lock.withLock {
            defer { self.session = nil; received = []; outgoing = [] }
            return self.session
        }
        guard let session else { return }
        try? RunLoopThread.shared.run {
            for stream in [session.inputStream, session.outputStream].compactMap({ $0 as Stream? }) {
                stream.close()
                stream.remove(from: .current, forMode: .default)
                stream.delegate = nil
            }
        }
    }

    // MARK: Stream events (on RunLoopThread)

    public func stream(_ stream: Stream, handle event: Stream.Event) {
        switch event {
        case .hasBytesAvailable:
            guard let input = stream as? InputStream else { return }
            var buffer = [UInt8](repeating: 0, count: 512)
            while input.hasBytesAvailable {
                let n = input.read(&buffer, maxLength: buffer.count)
                guard n > 0 else { break }
                lock.withLock { received += buffer[0..<n] }
            }
        case .hasSpaceAvailable:
            flush()
        case .errorOccurred:
            lock.withLock { failure = stream.streamError?.localizedDescription ?? "stream error" }
        case .endEncountered:
            lock.withLock { session = nil }
        default:
            break
        }
    }

    /// Writes as much of `outgoing` as the stream accepts. Runs on RunLoopThread.
    private func flush() {
        guard let output = lock.withLock({ session?.outputStream }) else { return }
        while output.hasSpaceAvailable {
            let chunk: [UInt8] = lock.withLock { Array(outgoing.prefix(1024)) }
            if chunk.isEmpty { return }
            let n = output.write(chunk, maxLength: chunk.count)
            guard n > 0 else {
                if n < 0 { lock.withLock { failure = output.streamError?.localizedDescription ?? "write failed" } }
                return
            }
            lock.withLock { outgoing.removeFirst(n) }
        }
    }
}
#endif
