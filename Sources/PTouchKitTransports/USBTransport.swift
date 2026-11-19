#if os(macOS)
import Foundation
import IOKit
import IOUSBHost
import PTouchKit

/// USB connection through IOUSBHost: bulk OUT for commands, bulk IN for status
/// (Raster Command Reference, Appendix A: endpoint 2 OUT, endpoint 1 IN).
///
/// A sandboxed app needs the `com.apple.security.device.usb` entitlement.
public final class USBTransport: PrinterTransport, @unchecked Sendable {
    public let vendorID: UInt16
    public let productID: UInt16

    private let lock = NSLock()
    private var interface: IOUSBHostInterface?
    private var pipeOut: IOUSBHostPipe?
    private var pipeIn: IOUSBHostPipe?
    private var pending: [UInt8] = []

    private static let endpointOut = 0x02
    private static let endpointIn = 0x81
    private static let maxPacket = 64
    /// kIOUSBPipeStalled.
    private static let pipeStalled = Int(Int32(bitPattern: 0xE000_4051))

    public init(model: PrinterModel = .ptP710BT) {
        vendorID = model.usbVendorID
        productID = model.usbProductID
    }

    /// `true` if a printer with this vendor and product ID is plugged in.
    public static func isConnected(model: PrinterModel = .ptP710BT) -> Bool {
        let matching = IOUSBHostDevice.__createMatchingDictionary(
            withVendorID: NSNumber(value: model.usbVendorID), productID: NSNumber(value: model.usbProductID),
            bcdDevice: nil, deviceClass: nil, deviceSubclass: nil, deviceProtocol: nil, speed: nil, productIDArray: nil
        ).takeRetainedValue()
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        defer { if service != 0 { IOObjectRelease(service) } }
        return service != 0
    }

    public func open() async throws {
        try lock.withLock { try openLocked() }
    }

    private func openLocked() throws {
        if interface != nil { return }

        var service = findInterface()
        if service == 0 {
            // A printer-class device may be left unconfigured; select configuration 1.
            try configureDevice()
            service = findInterface()
        }
        guard service != 0 else {
            throw TransportError.notFound(String(format: "USB %04X:%04X", vendorID, productID))
        }
        defer { IOObjectRelease(service) }
        do {
            let iface = try IOUSBHostInterface(__ioService: service, options: [], queue: nil, interestHandler: nil)
            interface = iface
            pipeOut = try iface.copyPipe(withAddress: Self.endpointOut)
            pipeIn = try iface.copyPipe(withAddress: Self.endpointIn)
        } catch {
            interface?.destroy()
            interface = nil
            throw TransportError.openFailed("\(error.localizedDescription) (is another app using the printer?)")
        }
    }

    public func write(_ bytes: [UInt8]) async throws {
        let pipe: IOUSBHostPipe? = lock.withLock { pipeOut }
        guard let pipe else { throw TransportError.notOpen }
        let data = NSMutableData(bytes: bytes, length: bytes.count)
        var sent = 0
        do {
            try pipe.__sendIORequest(with: data, bytesTransferred: &sent, completionTimeout: 30)
        } catch {
            throw TransportError.writeFailed(error.localizedDescription)
        }
        guard sent == bytes.count else { throw TransportError.writeFailed("sent \(sent) of \(bytes.count) bytes") }
    }

    public func read(upTo count: Int, timeout: Duration) async throws -> [UInt8] {
        let (pipe, buffered): (IOUSBHostPipe?, [UInt8]) = lock.withLock {
            let b = pending
            pending = []
            return (pipeIn, b)
        }
        if !buffered.isEmpty { return keep(buffered, upTo: count) }
        guard let pipe else { throw TransportError.notOpen }

        // The printer may answer with zero-length packets; keep asking until the deadline.
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            let remaining = deadline - clock.now
            let seconds = max(0.05, min(0.5, Double(remaining.components.seconds) + Double(remaining.components.attoseconds) / 1e18))
            let data = NSMutableData(length: Self.maxPacket)!
            var received = 0
            do {
                try pipe.__sendIORequest(with: data, bytesTransferred: &received, completionTimeout: seconds)
            } catch let error as NSError where error.code == Int(kIOReturnTimeout) || error.code == Self.pipeStalled {
                if error.code == Self.pipeStalled { try? pipe.clearStall() }
                continue
            }
            if received > 0 {
                let bytes = [UInt8](UnsafeRawBufferPointer(start: data.bytes, count: received))
                return keep(bytes, upTo: count)
            }
        }
        return []
    }

    public func close() async {
        lock.withLock {
            interface?.destroy()
            interface = nil
            pipeIn = nil
            pipeOut = nil
            pending = []
        }
    }

    private func keep(_ bytes: [UInt8], upTo count: Int) -> [UInt8] {
        guard bytes.count > count else { return bytes }
        lock.withLock { pending = Array(bytes[count...]) + pending }
        return Array(bytes[..<count])
    }

    private func findInterface() -> io_service_t {
        let matching = IOUSBHostInterface.__createMatchingDictionary(
            withVendorID: NSNumber(value: vendorID), productID: NSNumber(value: productID),
            // IOKit interface matching needs the configuration value as well as the number.
            bcdDevice: nil, interfaceNumber: 0, configurationValue: 1,
            interfaceClass: nil, interfaceSubclass: nil, interfaceProtocol: nil, speed: nil, productIDArray: nil
        ).takeRetainedValue()
        return IOServiceGetMatchingService(kIOMainPortDefault, matching)
    }

    private func configureDevice() throws {
        let matching = IOUSBHostDevice.__createMatchingDictionary(
            withVendorID: NSNumber(value: vendorID), productID: NSNumber(value: productID),
            bcdDevice: nil, deviceClass: nil, deviceSubclass: nil, deviceProtocol: nil, speed: nil, productIDArray: nil
        ).takeRetainedValue()
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            throw TransportError.notFound(String(format: "USB %04X:%04X", vendorID, productID))
        }
        defer { IOObjectRelease(service) }
        do {
            let device = try IOUSBHostDevice(__ioService: service, options: [.deviceCapture], queue: nil, interestHandler: nil)
            defer { device.destroy() }
            try device.__configure(withValue: 1, matchInterfaces: true)
        } catch {
            throw TransportError.openFailed("couldn't configure the USB device: \(error.localizedDescription)")
        }
    }
}
#endif
