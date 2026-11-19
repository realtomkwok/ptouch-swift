#if os(macOS)
import Foundation
import IOBluetooth
import PTouchKit

/// Bluetooth Classic connection through IOBluetooth, on the printer's plain
/// serial RFCOMM channel.
///
/// The P710BT offers two RFCOMM channels: 1 is Apple's iAP2 accessory channel
/// and ignores raster commands; 2 is plain serial (see docs/protocol). The
/// serial port macOS creates after pairing opens channel 1, so it can't be used.
///
/// The app needs `NSBluetoothAlwaysUsageDescription` in its Info.plist (macOS
/// kills it otherwise), and a sandboxed app needs `com.apple.security.device.bluetooth`.
/// The printer takes one Bluetooth connection at a time: close after each job.
public final class BluetoothTransport: NSObject, PrinterTransport, IOBluetoothRFCOMMChannelDelegate, @unchecked Sendable {
    public static let serialChannel: BluetoothRFCOMMChannelID = 2

    public let address: String
    public let channelID: BluetoothRFCOMMChannelID

    private let lock = NSLock()
    private var buffer: [UInt8] = []
    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?

    /// - Parameter address: the printer's Bluetooth address, e.g. "B4-22-00-ED-60-3B".
    public init(address: String, channelID: BluetoothRFCOMMChannelID = BluetoothTransport.serialChannel) {
        self.address = address
        self.channelID = channelID
    }

    /// Paired devices whose name contains `name`, as (name, address) pairs.
    public static func pairedPrinters(named name: String = "PT-P710") -> [(name: String, address: String)] {
        let devices = (IOBluetoothDevice.pairedDevices() ?? []).compactMap { $0 as? IOBluetoothDevice }
        return devices
            .filter { ($0.name ?? "").localizedCaseInsensitiveContains(name) }
            .map { ($0.name ?? "?", $0.addressString ?? "?") }
    }

    public func open() async throws {
        if lock.withLock({ channel != nil }) { return }
        try BluetoothThread.shared.run { [self] in
            guard let device = IOBluetoothDevice(addressString: address) else {
                throw TransportError.notFound("no Bluetooth device \(address)")
            }
            let link = device.openConnection()
            guard link == kIOReturnSuccess else {
                throw TransportError.openFailed(String(format: "Bluetooth link failed (0x%08X). Is the printer on and not connected to another device?", UInt32(bitPattern: link)))
            }
            var channel: IOBluetoothRFCOMMChannel?
            let result = device.openRFCOMMChannelSync(&channel, withChannelID: channelID, delegate: self)
            guard result == kIOReturnSuccess, let channel else {
                device.closeConnection()
                throw TransportError.openFailed(String(format: "RFCOMM channel %d failed (0x%08X)", channelID, UInt32(bitPattern: result)))
            }
            lock.withLock {
                self.device = device
                self.channel = channel
                self.buffer = []
            }
        }
    }

    public func write(_ bytes: [UInt8]) async throws {
        guard let channel = lock.withLock({ self.channel }) else { throw TransportError.notOpen }
        try BluetoothThread.shared.run {
            let mtu = max(1, Int(channel.getMTU()))
            var offset = 0
            while offset < bytes.count {
                var chunk = Array(bytes[offset..<min(offset + mtu, bytes.count)])
                let result = chunk.withUnsafeMutableBytes { channel.writeSync($0.baseAddress, length: UInt16($0.count)) }
                guard result == kIOReturnSuccess else {
                    throw TransportError.writeFailed(String(format: "0x%08X after %d of %d bytes", UInt32(bitPattern: result), offset, bytes.count))
                }
                offset += chunk.count
            }
        }
    }

    public func read(upTo count: Int, timeout: Duration) async throws -> [UInt8] {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while true {
            let (bytes, open): ([UInt8], Bool) = lock.withLock {
                let n = min(count, buffer.count)
                let out = Array(buffer[..<n])
                buffer.removeFirst(n)
                return (out, channel != nil)
            }
            if !bytes.isEmpty { return bytes }
            if !open { throw TransportError.notOpen }
            if clock.now >= deadline { return [] }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    public func close() async {
        let (channel, device) = lock.withLock { () -> (IOBluetoothRFCOMMChannel?, IOBluetoothDevice?) in
            defer { self.channel = nil; self.device = nil; buffer = [] }
            return (self.channel, self.device)
        }
        try? BluetoothThread.shared.run {
            channel?.close()
            device?.closeConnection()
        }
    }

    // MARK: IOBluetoothRFCOMMChannelDelegate (called on BluetoothThread)

    public func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let bytes = [UInt8](UnsafeRawBufferPointer(start: dataPointer, count: dataLength))
        lock.withLock { buffer += bytes }
    }

    public func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        lock.withLock {
            if channel === rfcommChannel { channel = nil }
        }
    }
}

/// A thread with its own run loop. IOBluetooth delivers channel callbacks on
/// the run loop of the thread that opened the channel, which async code
/// doesn't provide.
final class BluetoothThread: Thread, @unchecked Sendable {
    static let shared: BluetoothThread = {
        let t = BluetoothThread()
        t.name = "PTouchKit.Bluetooth"
        t.start()
        t.ready.wait()
        return t
    }()

    private let ready = DispatchSemaphore(value: 0)
    private var runLoop: CFRunLoop?

    override func main() {
        runLoop = CFRunLoopGetCurrent()
        // A port keeps the run loop running when no other source is attached.
        RunLoop.current.add(NSMachPort(), forMode: .default)
        ready.signal()
        while !isCancelled {
            RunLoop.current.run(mode: .default, before: .distantFuture)
        }
    }

    /// Runs `body` on this thread and waits for it.
    func run<T>(_ body: @escaping () throws -> T) throws -> T {
        if Thread.current === self { return try body() }
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Result<T, Error>!
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
            result = Result { try body() }
            done.signal()
        }
        CFRunLoopWakeUp(runLoop)
        done.wait()
        return try result.get()
    }
}
#endif
