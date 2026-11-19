// ptouchkit-testpage: read a PT-P710BT's status and print a test page.
//
//   ptouchkit-testpage status (--usb | --bluetooth [ADDRESS] | --hex "80 20 42 …")
//   ptouchkit-testpage print  (--usb | --bluetooth [ADDRESS]) [--quirks spec|ptouch] [--length MM]
//   ptouchkit-testpage print  --out job.bin --tape MM [--quirks spec|ptouch]
//   ptouchkit-testpage list
//
// Bluetooth needs NSBluetoothAlwaysUsageDescription, so run it from the app
// bundle that Tools/hardware/make-testpage-app.sh builds (docs/hardware-testing.md).

import Foundation
import PTouchKit
import PTouchKitTransports

// MARK: Arguments

enum Connection {
    case usb
    case bluetooth(address: String?)
}

struct Options {
    var command = ""
    var connection: Connection?
    var out: String?
    var tapeMM: Double?
    var quirksName = "spec"
    var lengthMM = 30.0
    var hex: String?

    var quirks: EncoderQuirks { quirksName == "ptouch" ? .ptouch : .spec }
}

func usage() -> Never {
    print("""
    usage: ptouchkit-testpage status (--usb | --bluetooth [ADDRESS] | --hex "80 20 42 …")
           ptouchkit-testpage print (--usb | --bluetooth [ADDRESS] | --out FILE --tape MM) [--quirks spec|ptouch] [--length MM]
           ptouchkit-testpage list
    """)
    exit(2)
}

func parse(_ args: [String]) -> Options {
    var o = Options()
    guard let command = args.first, ["status", "print", "list"].contains(command) else { usage() }
    o.command = command
    var i = 1
    func value() -> String {
        i += 1
        guard i < args.count else { usage() }
        return args[i]
    }
    while i < args.count {
        switch args[i] {
        case "--usb": o.connection = .usb
        case "--bluetooth":
            if i + 1 < args.count, !args[i + 1].hasPrefix("--") { o.connection = .bluetooth(address: value()) }
            else { o.connection = .bluetooth(address: nil) }
        case "--out": o.out = value()
        case "--tape": guard let mm = Double(value()) else { usage() }; o.tapeMM = mm
        case "--quirks": o.quirksName = value(); guard ["spec", "ptouch"].contains(o.quirksName) else { usage() }
        case "--length": guard let mm = Double(value()) else { usage() }; o.lengthMM = mm
        case "--hex": o.hex = value()
        default: usage()
        }
        i += 1
    }
    if o.command == "status", o.connection == nil, o.hex == nil { usage() }
    if o.command == "print", o.connection == nil, o.out == nil || o.tapeMM == nil { usage() }
    return o
}

// MARK: Output

struct ToolError: Error, CustomStringConvertible {
    let description: String
}

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

// MARK: Running

func makeTransport(_ connection: Connection) throws -> any PrinterTransport {
    switch connection {
    case .usb:
        guard USBTransport.isConnected() else { throw ToolError(description: "No PT-P710BT on USB.") }
        print("Connection: USB")
        return USBTransport()
    case .bluetooth(let address):
        let resolved: String
        if let address {
            resolved = address
        } else {
            let found = BluetoothTransport.pairedPrinters()
            guard let first = found.first else { throw ToolError(description: "No paired PT-P710BT. Pair it in System Settings first.") }
            resolved = first.address
        }
        print("Connection: Bluetooth \(resolved), RFCOMM channel \(BluetoothTransport.serialChannel)")
        return BluetoothTransport(address: resolved)
    }
}

func run<T: PrinterTransport>(_ transport: T, options: Options) async throws {
    let client = PrinterClient(transport: transport)
    try await transport.open()
    do {
        let status = try await client.status()
        print("Status:")
        describe(status)
        if options.command == "status" { await transport.close(); return }

        if let first = status.problems.first { throw ToolError(description: "Not printing: \(first.title).") }
        guard let media = status.loadedMedia() else { throw ToolError(description: "Unknown tape.") }
        if let mm = options.tapeMM, let wanted = mediaFor(widthMM: mm), wanted != media {
            throw ToolError(description: "Loaded tape is \(media.name), not \(wanted.name).")
        }
        let page = testPage(media: media, lengthMM: options.lengthMM, quirksName: options.quirksName)
        let job = try RasterEncoder(quirks: options.quirks).encode([page], media: media)
        print("Job: \(media.name), \(page.width) lines, quirks \(options.quirksName), \(job.count) bytes")
        let start = ContinuousClock.now
        let final = try await client.print(job) { s in
            print("Status: \(s.statusType), phase \(s.phase)")
        }
        print("Printing completed in \(ContinuousClock.now - start). Final status:")
        describe(final)
    } catch {
        await transport.close()
        throw error
    }
    await transport.close()
}

let options = parse(Array(CommandLine.arguments.dropFirst()))

do {
    switch options.command {
    case "list":
        print("USB: \(USBTransport.isConnected() ? "PT-P710BT connected" : "none")")
        let paired = BluetoothTransport.pairedPrinters()
        if paired.isEmpty { print("Bluetooth: no paired PT-P710BT") }
        for p in paired { print("Bluetooth: \(p.name) \(p.address)") }
    default:
        if let hexReply = options.hex {
            let bytes = hexReply.split(whereSeparator: { $0 == " " || $0 == ":" }).compactMap { UInt8($0, radix: 16) }
            print("Status:")
            describe(try PrinterStatus(bytes: bytes))
        } else if let connection = options.connection {
            try await run(try makeTransport(connection), options: options)
        } else if let out = options.out, let mm = options.tapeMM {
            guard let media = mediaFor(widthMM: mm) else { throw ToolError(description: "No TZe tape is \(mm) mm wide.") }
            let page = testPage(media: media, lengthMM: options.lengthMM, quirksName: options.quirksName)
            let job = try RasterEncoder(quirks: options.quirks).encode([page], media: media)
            try Data(job).write(to: URL(fileURLWithPath: out))
            print("Wrote \(out): \(media.name), \(page.width) lines, quirks \(options.quirksName), \(job.count) bytes")
        }
    }
} catch {
    print("Error: \(error)")
    exit(1)
}
