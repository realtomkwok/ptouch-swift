// ptouchkit-testpage: read a PT-P710BT's status and print a test page.
//
//   ptouchkit-testpage status --device /dev/cu.PT-P710BT1234
//   ptouchkit-testpage print  --device /dev/cu.PT-P710BT1234 [--quirks spec|ptouch]
//   ptouchkit-testpage print  --out job.bin --tape 12 [--quirks spec|ptouch]
//
// The device is the Bluetooth serial port macOS creates after pairing, or any
// character device that passes bytes straight to the printer. With --out, the
// job is written to a file instead; send it over USB with `lp -d <queue> -o raw job.bin`.

import Foundation
import PTouchKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: Arguments

struct Options {
    var command = ""
    var device: String?
    var out: String?
    var tapeMM: Double?
    var quirksName = "spec"
    var lengthMM = 30.0

    var quirks: EncoderQuirks { quirksName == "ptouch" ? .ptouch : .spec }
}

func usage() -> Never {
    print("""
    usage: ptouchkit-testpage status --device PATH
           ptouchkit-testpage print (--device PATH | --out FILE --tape MM) [--quirks spec|ptouch] [--length MM]
    """)
    exit(2)
}

func parse(_ args: [String]) -> Options {
    var o = Options()
    guard let command = args.first, ["status", "print"].contains(command) else { usage() }
    o.command = command
    var i = 1
    func value() -> String {
        i += 1
        guard i < args.count else { usage() }
        return args[i]
    }
    while i < args.count {
        switch args[i] {
        case "--device": o.device = value()
        case "--out": o.out = value()
        case "--tape": guard let mm = Double(value()) else { usage() }; o.tapeMM = mm
        case "--quirks": o.quirksName = value(); guard ["spec", "ptouch"].contains(o.quirksName) else { usage() }
        case "--length": guard let mm = Double(value()) else { usage() }; o.lengthMM = mm
        default: usage()
        }
        i += 1
    }
    if o.command == "status", o.device == nil { usage() }
    if o.command == "print", o.device == nil, o.out == nil || o.tapeMM == nil { usage() }
    return o
}

// MARK: Serial port

struct PortError: Error, CustomStringConvertible {
    let description: String
}

final class Port {
    let fd: Int32

    init(path: String) throws {
        fd = open(path, O_RDWR | O_NOCTTY)
        guard fd >= 0 else { throw PortError(description: "Can't open \(path): \(String(cString: strerror(errno)))") }
        var t = termios()
        if tcgetattr(fd, &t) == 0 {
            cfmakeraw(&t)
            _ = tcsetattr(fd, TCSANOW, &t)
        }
    }

    deinit { close(fd) }

    func write(_ bytes: [UInt8]) throws {
        var offset = 0
        while offset < bytes.count {
            let n = bytes[offset...].withUnsafeBytes { buffer in
                #if canImport(Darwin)
                Darwin.write(fd, buffer.baseAddress, buffer.count)
                #else
                Glibc.write(fd, buffer.baseAddress, buffer.count)
                #endif
            }
            guard n > 0 else { throw PortError(description: "Write failed: \(String(cString: strerror(errno)))") }
            offset += n
        }
    }

    /// Reads exactly `count` bytes, or returns what arrived before `timeout` seconds.
    func read(count: Int, timeout: Double) -> [UInt8] {
        var out: [UInt8] = []
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = [UInt8](repeating: 0, count: count)
        while out.count < count {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { break }
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&pfd, 1, Int32(remaining * 1000)) > 0 else { break }
            let n = buffer.withUnsafeMutableBytes { b in
                #if canImport(Darwin)
                Darwin.read(fd, b.baseAddress, count - out.count)
                #else
                Glibc.read(fd, b.baseAddress, count - out.count)
                #endif
            }
            guard n > 0 else { break }
            out += buffer[0..<n]
        }
        return out
    }

    func readStatus(timeout: Double) throws -> PrinterStatus? {
        let bytes = read(count: PrinterStatus.byteCount, timeout: timeout)
        if bytes.isEmpty { return nil }
        guard bytes.count == PrinterStatus.byteCount else {
            throw PortError(description: "Short status reply (\(bytes.count) bytes): \(hex(bytes))")
        }
        return try PrinterStatus(bytes: bytes)
    }
}

// MARK: Output

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
}

func describe(_ s: PrinterStatus) {
    let code = s.modelCode
    let ascii = (0x20..<0x7F).contains(code) ? " '\(Character(UnicodeScalar(code)))'" : ""
    print("  raw:        \(hex(s.raw))")
    print("  model code: \(String(format: "%02Xh", code))\(ascii)")
    print("  status:     \(s.statusType), phase \(s.phase), notification \(s.notification)")
    print("  media:      width \(s.mediaWidthMM) mm, kind \(s.mediaKind.map { "\($0)" } ?? String(format: "%02Xh", s.raw[11])) -> \(s.loadedMedia()?.name ?? "not recognised")")
    print("  colours:    tape \(TapeColor.names[s.tapeColorID] ?? String(format: "%02Xh", s.tapeColorID)), text \(TextColor.names[s.textColorID] ?? String(format: "%02Xh", s.textColorID))")
    print("  errors:     \(s.errors)")
    for p in s.problems { print("  problem:    \(p.title). \(p.recovery)") }
}

// MARK: Test page

/// Frame, a pin-0 tick, a diagonal, a checker block, and one bar for the spec
/// preset or two for the ptouch preset, so the printout shows which ran.
func testPage(media: Media, lengthMM: Double, quirksName: String) -> LabelBitmap {
    let w = dots(fromMillimetres: lengthMM, dpi: 180)
    let h = media.printAreaPins
    let bars = quirksName == "ptouch" ? [10..<14, 18..<22] : [10..<14]
    return LabelBitmap(width: w, height: h) { x, y in
        if x == 0 || x == w - 1 || y == 0 || y == h - 1 { return true }
        if y < 4, (26..<30).contains(x) { return true } // pin 0 side
        if bars.contains(where: { $0.contains(x) }) { return true }
        if x >= 34, x - 34 == y { return true }
        if x >= w - 50, x < w - 8, y >= 3, y < h - 3 { return (x / 4 + y / 4) % 2 == 0 }
        return false
    }
}

func mediaFor(widthMM: Double) -> Media? {
    Media.allTZe.first { abs($0.nominalWidthMM - widthMM) < 0.6 }
}

// MARK: Main

let options = parse(Array(CommandLine.arguments.dropFirst()))
let encoder = RasterEncoder(quirks: options.quirks)
let reset: [UInt8] = [UInt8](repeating: 0, count: 100) + [0x1B, 0x40]

do {
    var port: Port?
    var media: Media?

    if let device = options.device {
        let p = try Port(path: device)
        port = p
        try p.write(reset + statusRequestCommand)
        guard let status = try p.readStatus(timeout: 5) else {
            throw PortError(description: "No status reply within 5 s. Is the printer on and paired?")
        }
        print("Status:")
        describe(status)
        if options.command == "status" { exit(0) }
        if let first = status.problems.first { throw PortError(description: "Not printing: \(first.title).") }
        media = status.loadedMedia()
    }
    if let mm = options.tapeMM {
        guard let m = mediaFor(widthMM: mm) else { throw PortError(description: "No TZe tape is \(mm) mm wide.") }
        if let loaded = media, loaded != m { throw PortError(description: "Loaded tape is \(loaded.name), not \(m.name).") }
        media = m
    }
    guard let media else { throw PortError(description: "Unknown tape.") }

    let page = testPage(media: media, lengthMM: options.lengthMM, quirksName: options.quirksName)
    let job = try encoder.encode([page], media: media)
    print("Job: \(media.name), \(page.width) lines, quirks \(options.quirksName), \(job.count) bytes")

    if let out = options.out {
        try Data(job).write(to: URL(fileURLWithPath: out))
        print("Wrote \(out)")
    }
    if let port {
        try port.write(job)
        print("Sent. Waiting for the printer…")
        while let status = try port.readStatus(timeout: 30) {
            print("Status:")
            describe(status)
            if status.statusType == .printingCompleted { print("Printing completed."); break }
            if status.statusType == .errorOccurred { throw PortError(description: "The printer reported an error.") }
        }
    }
} catch {
    print("Error: \(error)")
    exit(1)
}
