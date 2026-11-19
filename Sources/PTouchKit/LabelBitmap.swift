/// A 1-bit label image in printer orientation.
///
/// `width` runs along the feed: one column per raster line, at the print
/// resolution (twice as many columns for high-resolution printing).
/// `height` is the medium's print-area pins; row `y` lands on head pin
/// `leftMarginPins + y` (Raster Command Reference §2.3.5).
public struct LabelBitmap: Sendable, Hashable {
    public let width: Int
    public let height: Int
    /// Column-major bits: `width` columns of `bytesPerColumn` bytes, MSB = row 0.
    private var storage: [UInt8]

    var bytesPerColumn: Int { (height + 7) / 8 }

    /// A blank (all white) bitmap.
    public init(width: Int, height: Int) {
        precondition(width >= 0 && height >= 0, "Bitmap size must not be negative")
        self.width = width
        self.height = height
        self.storage = [UInt8](repeating: 0, count: width * ((height + 7) / 8))
    }

    /// A bitmap whose pixels come from `isBlack(x, y)`.
    public init(width: Int, height: Int, isBlack: (_ x: Int, _ y: Int) -> Bool) {
        self.init(width: width, height: height)
        for x in 0..<width {
            for y in 0..<height where isBlack(x, y) {
                self[x, y] = true
            }
        }
    }

    /// `true` for a black (printed) pixel.
    public subscript(x: Int, y: Int) -> Bool {
        get {
            precondition(x >= 0 && x < width && y >= 0 && y < height, "Pixel out of range")
            return storage[x * bytesPerColumn + y / 8] & (0x80 >> UInt8(y % 8)) != 0
        }
        set {
            precondition(x >= 0 && x < width && y >= 0 && y < height, "Pixel out of range")
            let index = x * bytesPerColumn + y / 8
            let mask: UInt8 = 0x80 >> UInt8(y % 8)
            if newValue { storage[index] |= mask } else { storage[index] &= ~mask }
        }
    }

    /// Returns a copy with every column repeated `factor` times along the feed.
    /// Use it to print a 180 dpi image at high resolution without changing its length.
    public func repeatingColumns(_ factor: Int) -> LabelBitmap {
        precondition(factor >= 1, "Factor must be at least 1")
        var copy = LabelBitmap(width: width * factor, height: height)
        let n = bytesPerColumn
        for x in 0..<width {
            let column = storage[(x * n)..<(x * n + n)]
            for k in 0..<factor {
                let start = (x * factor + k) * n
                copy.storage.replaceSubrange(start..<(start + n), with: column)
            }
        }
        return copy
    }
}
