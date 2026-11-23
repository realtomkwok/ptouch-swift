import Foundation
import Testing

/// A golden fixture produced by `Tools/golden/generate.py`.
struct GoldenFixture: Decodable, CustomTestStringConvertible, Sendable {
    struct Options: Decodable, Sendable {
        let autoCut: Bool
        let mirror: Bool
        let chainPrinting: Bool
        let specialTape: Bool
        let highResolution: Bool
        let marginMM: Double
        let compression: String
        let feedAfterLastLabel: Bool
        /// Only present in the pre-cut fixtures.
        let preCut: Bool?
    }

    let name: String
    let mediaID: Int
    let labels: [String]
    let options: Options
    let quirks: String
    let expected: String

    var testDescription: String { name }

    static let directory: URL = Bundle.module.resourceURL!
        .appendingPathComponent("Fixtures/golden", isDirectory: true)

    static func all() throws -> [GoldenFixture] {
        struct Index: Decodable { let fixtures: [String] }
        let index = try JSONDecoder().decode(
            Index.self,
            from: Data(contentsOf: directory.appendingPathComponent("index.json"))
        )
        return try index.fixtures.map { name in
            try JSONDecoder().decode(
                GoldenFixture.self,
                from: Data(contentsOf: directory.appendingPathComponent("\(name).json"))
            )
        }
    }

    /// Fixtures for parameterised tests; an unreadable index fails loudly.
    static let cases: [GoldenFixture] = (try? all()) ?? []

    func expectedBytes() throws -> [UInt8] {
        [UInt8](try Data(contentsOf: Self.directory.appendingPathComponent(expected)))
    }

    func labelBitmaps() throws -> [PBM] {
        try labels.map { try PBM(contentsOf: Self.directory.appendingPathComponent($0)) }
    }
}

/// Minimal binary PBM (P4) reader. Width = raster lines along the feed,
/// height = print-area pins; 1 bits are black.
struct PBM: Equatable, Sendable {
    let width: Int
    let height: Int
    /// Row-major, `height` rows of `(width + 7) / 8` bytes, MSB first.
    let rows: [UInt8]

    enum ParseError: Error { case badHeader, truncated }

    init(contentsOf url: URL) throws {
        let data = [UInt8](try Data(contentsOf: url))
        var i = 0
        func token() throws -> String {
            while i < data.count, data[i] == 0x20 || data[i] == 0x0A || data[i] == 0x0D || data[i] == 0x09 { i += 1 }
            let start = i
            while i < data.count, !(data[i] == 0x20 || data[i] == 0x0A || data[i] == 0x0D || data[i] == 0x09) { i += 1 }
            guard i > start else { throw ParseError.badHeader }
            return String(decoding: data[start..<i], as: UTF8.self)
        }
        guard try token() == "P4", let w = Int(try token()), let h = Int(try token()) else {
            throw ParseError.badHeader
        }
        i += 1 // single whitespace before raster data
        let count = h * ((w + 7) / 8)
        guard data.count - i >= count else { throw ParseError.truncated }
        width = w
        height = h
        rows = Array(data[i..<(i + count)])
    }

    func isBlack(x: Int, y: Int) -> Bool {
        rows[y * ((width + 7) / 8) + x / 8] & (0x80 >> UInt8(x % 8)) != 0
    }
}
