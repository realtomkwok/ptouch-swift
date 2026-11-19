// Spec: Raster Command Reference PT-E550W/P750W/P710BT v1.02,
// §2.3.3 "Feed amount" and §2.3.4 "Maximum and minimum lengths".

/// Print resolution along the feed direction.
public enum Resolution: Sendable, Hashable {
    /// 180 × 180 dpi.
    case standard
    /// 180 dpi across the tape, 360 dpi along it (§2.3.1).
    case high

    /// Dots per inch along the feed direction.
    public var feedDPI: Int { self == .high ? 360 : 180 }
}

/// Length and margin limits, in dots along the feed direction.
public struct Limits: Sendable, Hashable {
    public let minimumMarginDots: Int
    public let maximumMarginDots: Int
    public let minimumLengthDots: Int
    public let maximumLengthDots: Int

    /// Limits for the given resolution and media kind (§2.3.3, §2.3.4).
    public static func forMedia(_ kind: MediaKind, resolution: Resolution) -> Limits {
        let isHeatShrink = kind == .heatShrinkTube2to1 || kind == .heatShrinkTube3to1
        switch resolution {
        case .standard:
            return Limits(
                minimumMarginDots: 14,
                maximumMarginDots: 900,
                minimumLengthDots: 31,
                maximumLengthDots: isHeatShrink ? 3543 : 7086
            )
        case .high:
            // §2.3.4 gives no 360 dpi figures for heat-shrink tube; double the 180 dpi ones.
            return Limits(
                minimumMarginDots: 28,
                maximumMarginDots: 1800,
                minimumLengthDots: 60,
                maximumLengthDots: isHeatShrink ? 7086 : 14172
            )
        }
    }
}

/// Converts millimetres to dots at the given dots per inch, rounding to nearest.
public func dots(fromMillimetres mm: Double, dpi: Int) -> Int {
    Int((mm * Double(dpi) / 25.4).rounded())
}
