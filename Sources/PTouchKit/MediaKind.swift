// Spec: Raster Command Reference PT-E550W/P750W/P710BT v1.02,
// §4 "ESC i z" {n2} and "ESC i S" status table (4) Media type.

/// The kind of media loaded in, or targeted at, the printer.
public enum MediaKind: UInt8, Sendable, Hashable, CaseIterable {
    case none = 0x00
    case laminatedTape = 0x01
    case nonLaminatedTape = 0x03
    /// Heat-shrink tube, 2:1 shrink ratio (spec IDs 415–419).
    case heatShrinkTube2to1 = 0x11
    /// Heat-shrink tube, 3:1 shrink ratio (spec IDs 420–423).
    case heatShrinkTube3to1 = 0x17
    case incompatible = 0xFF
}
