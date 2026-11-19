/// A hardware test label: a frame, a short tick on the pin-0 edge, a diagonal,
/// a checker block, and `bars` vertical bars near the start (used to show which
/// encoder preset produced the print).
public enum TestPage {
    public static func bitmap(for media: Media, lengthMM: Double = 30, bars: Int = 1) -> LabelBitmap {
        let w = dots(fromMillimetres: lengthMM, dpi: 180)
        let h = media.printAreaPins
        let barRanges = (0..<max(0, bars)).map { (10 + $0 * 8)..<(14 + $0 * 8) }
        return LabelBitmap(width: w, height: h) { x, y in
            if x == 0 || x == w - 1 || y == 0 || y == h - 1 { return true }
            if y < 4, (26 + max(0, bars - 1) * 8..<30 + max(0, bars - 1) * 8).contains(x) { return true }
            if barRanges.contains(where: { $0.contains(x) }) { return true }
            if x >= 34, x - 34 == y { return true }
            if x >= w - 50, x < w - 8, y >= 3, y < h - 3 { return (x / 4 + y / 4) % 2 == 0 }
            return false
        }
    }
}
