// Spec: Raster Command Reference PT-E550W/P750W/P710BT v1.02, §4 "M Select
// compression mode", TIFF (PackBits).

/// TIFF PackBits compression of one raster line.
enum PackBits {
    /// Encodes `data`: runs of two or more equal bytes become
    /// `[1 - count, byte]`; other bytes become `[count - 1, bytes…]`.
    /// Runs and literals are split at 128 bytes.
    static func encode(_ data: some Collection<UInt8>) -> [UInt8] {
        let bytes = Array(data)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count + bytes.count / 128 + 1)
        var literal: [UInt8] = []

        func flushLiteral() {
            guard !literal.isEmpty else { return }
            out.append(UInt8(literal.count - 1))
            out.append(contentsOf: literal)
            literal.removeAll(keepingCapacity: true)
        }

        var i = 0
        while i < bytes.count {
            var run = 1
            while i + run < bytes.count, bytes[i + run] == bytes[i], run < 128 {
                run += 1
            }
            if run >= 2 {
                flushLiteral()
                out.append(UInt8(bitPattern: Int8(1 - run)))
                out.append(bytes[i])
                i += run
            } else {
                literal.append(bytes[i])
                if literal.count == 128 { flushLiteral() }
                i += 1
            }
        }
        flushLiteral()
        return out
    }

    /// Decodes PackBits data (used by tests and diagnostics).
    static func decode(_ data: some Collection<UInt8>) -> [UInt8] {
        let bytes = Array(data)
        var out: [UInt8] = []
        var i = 0
        while i < bytes.count {
            let header = Int(Int8(bitPattern: bytes[i]))
            i += 1
            if header >= 0 {
                let end = min(i + header + 1, bytes.count)
                out.append(contentsOf: bytes[i..<end])
                i = end
            } else if header != -128, i < bytes.count {
                out.append(contentsOf: repeatElement(bytes[i], count: 1 - header))
                i += 1
            }
        }
        return out
    }
}
