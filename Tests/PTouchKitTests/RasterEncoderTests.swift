import Testing
@testable import PTouchKit

extension GoldenFixture {
    var media: Media {
        get throws { try #require(PrinterModel.ptP710BT.supportedMedia.first { $0.id == mediaID }) }
    }

    var printOptions: PrintOptions {
        PrintOptions(
            autoCut: options.autoCut,
            mirror: options.mirror,
            chainPrinting: options.chainPrinting,
            specialTape: options.specialTape,
            resolution: options.highResolution ? .high : .standard,
            marginMM: options.marginMM,
            compression: options.compression == "none" ? .none : .tiff,
            feedAfterLastLabel: options.feedAfterLastLabel,
            preCut: options.preCut ?? false
        )
    }

    func bitmaps() throws -> [LabelBitmap] {
        try labelBitmaps().map { pbm in
            LabelBitmap(width: pbm.width, height: pbm.height) { x, y in pbm.isBlack(x: x, y: y) }
        }
    }
}

@Suite("Raster encoder")
struct RasterEncoderTests {
    @Test("Matches ptouch byte for byte", arguments: GoldenFixture.cases)
    func golden(fixture: GoldenFixture) throws {
        #expect(fixture.quirks == "ptouch")
        let encoder = RasterEncoder(quirks: .ptouch)
        let actual = try encoder.encode(fixture.bitmaps(), media: fixture.media, options: fixture.printOptions)
        let expected = try fixture.expectedBytes()
        if actual != expected {
            let first = zip(actual, expected).enumerated().first { $0.element.0 != $0.element.1 }?.offset
                ?? min(actual.count, expected.count)
            Issue.record("First difference at byte \(first) (actual \(actual.count) bytes, expected \(expected.count))")
        }
    }

    // §2.1 examples, with the spec quirks.
    @Test("Spec preset: header for 24 mm laminated tape")
    func specHeader() throws {
        let bitmap = LabelBitmap(width: 40, height: 128) { x, _ in x == 0 }
        let bytes = try RasterEncoder(quirks: .spec).encode([bitmap], media: .tze24mm)
        #expect(bytes.prefix(100).allSatisfy { $0 == 0 })
        let body = Array(bytes.dropFirst(100))
        #expect(Array(body.prefix(2)) == [0x1B, 0x40])
        #expect(Array(body[2..<6]) == [0x1B, 0x69, 0x61, 0x01])
        #expect(Array(body[6..<19]) == [0x1B, 0x69, 0x7A, 0x86, 0x01, 0x18, 0x00, 40, 0, 0, 0, 0x00, 0x00])
        #expect(Array(body[19..<23]) == [0x1B, 0x69, 0x4D, 0x40]) // auto cut
        #expect(Array(body[23..<27]) == [0x1B, 0x69, 0x4B, 0x08]) // no chain printing
        #expect(Array(body[27..<32]) == [0x1B, 0x69, 0x64, 0x0E, 0x00]) // 2 mm = 14 dots
        #expect(Array(body[32..<34]) == [0x4D, 0x02]) // TIFF
        #expect(body.last == 0x1A)
    }

    @Test("Spec preset marks pages after the first in ESC i z n9")
    func specFollowingPages() throws {
        let label = LabelBitmap(width: 31, height: 70)
        let bytes = try RasterEncoder(quirks: .spec).encode([label, label], media: .tze12mm)
        let starts = bytes.indices.filter { bytes[$0...].starts(with: [0x1B, 0x69, 0x7A]) }
        #expect(starts.count == 2)
        #expect(bytes[starts[0] + 11] == 0x00)
        #expect(bytes[starts[1] + 11] == 0x01)
    }

    @Test("Copies repeat the pages")
    func copies() throws {
        let label = LabelBitmap(width: 31, height: 70) { x, y in x == y }
        let once = try RasterEncoder().encode([label, label, label], media: .tze12mm, options: PrintOptions())
        let thrice = try RasterEncoder().encode([label], media: .tze12mm, options: PrintOptions(copies: 3))
        #expect(once == thrice)
    }

    @Test("Pre-cut is off by default")
    func preCutDefaultsOff() throws {
        #expect(PrintOptions().preCut == false)
        let label = LabelBitmap(width: 31, height: 70) { x, y in x == y }
        let plain = try RasterEncoder().encode([label], media: .tze12mm)
        let explicit = try RasterEncoder().encode([label], media: .tze12mm, options: PrintOptions(preCut: false))
        #expect(plain == explicit)
    }

    // The golden fixtures cover ptouch's bytes; this pins the structure with the
    // spec quirks: the job, then a zero-line job (§2.1) ended with Control-Z (§4).
    @Test("Pre-cut sends a zero-line feed-and-cut job before the labels")
    func preCutStructure() throws {
        let label = LabelBitmap(width: 31, height: 70) { x, y in x == y }
        let encoder = RasterEncoder(quirks: .spec)
        let plain = try encoder.encode([label], media: .tze12mm)
        let cut = try encoder.encode([label], media: .tze12mm, options: PrintOptions(preCut: true))

        let initBytes = [UInt8](repeating: 0, count: 100) + [0x1B, 0x40]
        #expect(cut.starts(with: initBytes))
        // The pre-cut job carries its own initialization.
        let preCut = Array(cut.dropFirst(initBytes.count))
        #expect(preCut.starts(with: initBytes))
        let body = Array(preCut.dropFirst(initBytes.count))
        #expect(body.starts(with: [0x1B, 0x69, 0x61, 0x01]))
        // ESC i z with {n5..n8} = 0 raster lines.
        let z = try #require(body.indices.first { body[$0...].starts(with: [0x1B, 0x69, 0x7A]) })
        #expect(Array(body[(z + 7)..<(z + 11)]) == [0, 0, 0, 0])
        let end = try #require(body.firstIndex(of: 0x1A))
        #expect(!body[..<end].contains(0x47) && !body[..<end].contains(0x5A)) // no raster data
        // Then the real job, exactly as without pre-cut.
        #expect(Array(body[(end + 1)...]) == Array(plain.dropFirst(initBytes.count)))
    }

    @Test("Pre-cut ignores the label options but keeps compression")
    func preCutFixedSettings() throws {
        let label = LabelBitmap(width: 62, height: 70) { x, y in x == y }
        let encoder = RasterEncoder(quirks: .spec)
        let options = PrintOptions(
            autoCut: false, mirror: true, chainPrinting: true, specialTape: true, marginMM: 5,
            compression: .none, preCut: true)
        let bytes = try encoder.encode([label], media: .tze12mm, options: options)
        let first1A = try #require(bytes.firstIndex(of: 0x1A))
        let preCut = Array(bytes[102..<first1A])
        #expect(preCut.contains(0x4D)) // sanity
        let m = try #require(preCut.indices.first { preCut[$0...].starts(with: [0x1B, 0x69, 0x4D]) })
        #expect(preCut[m + 3] == 0x40) // auto cut, no mirror
        let k = try #require(preCut.indices.first { preCut[$0...].starts(with: [0x1B, 0x69, 0x4B]) })
        #expect(preCut[k + 3] == 0x08) // no chain printing, standard resolution, no special tape
        let d = try #require(preCut.indices.first { preCut[$0...].starts(with: [0x1B, 0x69, 0x64]) })
        #expect(Array(preCut[(d + 3)...(d + 4)]) == [0x0E, 0x00]) // 2 mm
        #expect(Array(preCut.suffix(2)) == [0x4D, 0x00]) // compression follows the job
    }

    @Test func rejectsWrongHeight() {
        #expect(throws: EncodingError.bitmapHeightMismatch(label: 0, expected: 70, actual: 64)) {
            try RasterEncoder().encode([LabelBitmap(width: 40, height: 64)], media: .tze12mm)
        }
    }

    @Test func rejectsShortLabel() {
        // 2 dots + 2 × 14-dot margins = 30 < 31 (§2.3.4).
        #expect(throws: EncodingError.labelTooShort(label: 0, minimumDots: 31, actualDots: 30)) {
            try RasterEncoder().encode([LabelBitmap(width: 2, height: 70)], media: .tze12mm)
        }
    }

    @Test func rejectsSmallMargin() {
        #expect(throws: EncodingError.marginOutOfRange(minimumDots: 14, maximumDots: 900, actualDots: 7)) {
            try RasterEncoder().encode([LabelBitmap(width: 40, height: 70)], media: .tze12mm, options: PrintOptions(marginMM: 1))
        }
    }
}

@Suite("PackBits")
struct PackBitsTests {
    @Test("§4 example: 20 × 00, 2 × 22, then 6 literal bytes")
    func specExample() {
        let input: [UInt8] = Array(repeating: 0x00, count: 20) + [0x22, 0x22, 0x23, 0xBA, 0xBF, 0xA2, 0x22, 0x2B]
        #expect(PackBits.encode(input) == [0xED, 0x00, 0xFF, 0x22, 0x05, 0x23, 0xBA, 0xBF, 0xA2, 0x22, 0x2B])
    }

    @Test("Round-trips random lines")
    func roundTrip() {
        var rng = SplitMix64(seed: 42)
        for _ in 0..<2000 {
            let line = (0..<16).map { _ in UInt8(truncatingIfNeeded: rng.next() % 4 == 0 ? 0 : rng.next()) }
            #expect(PackBits.decode(PackBits.encode(line)) == line)
        }
    }

    @Test("Spec cap: a line over 16 bytes compressed is sent as a 17-byte literal")
    func cap() throws {
        // a, b b, c, d d, … compresses to more than 16 bytes.
        let line: [UInt8] = [1, 2, 2, 3, 4, 4, 5, 6, 6, 7, 8, 8, 9, 10, 10, 11]
        #expect(PackBits.encode(line).count > 16)
        let bitmap = LabelBitmap(width: 31, height: 128) { x, y in
            x == 0 && line[y / 8] & (0x80 >> UInt8(y % 8)) != 0
        }
        let bytes = try RasterEncoder(quirks: .spec).encode([bitmap], media: .tze24mm)
        let g = try #require(bytes.firstIndex(of: 0x47))
        #expect(Array(bytes[g..<(g + 3)]) == [0x47, 17, 0])
        #expect(Array(bytes[(g + 3)..<(g + 20)]) == [15] + line)
    }
}

/// Small deterministic RNG for tests.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
