// Spec: Raster Command Reference PT-E550W/P750W/P710BT v1.02,
// §2.3.2 "Page size" (tape IDs, widths, offsets) and §2.3.5 "Raster line"
// (pin layout per tape), §4 "ESC i S" table (3) Media width.

/// A tape or tube the printer can print on, with its pin layout on the 128-pin head.
public struct Media: Sendable, Hashable, Identifiable {
    /// Brother's media ID from §2.3.2 (e.g. 261 for 24 mm TZe tape).
    public let id: Int
    public let name: String
    public let kind: MediaKind
    /// Nominal width in millimetres (3.5 for 3.5 mm tape).
    public let nominalWidthMM: Double
    /// The width byte used in "ESC i z" {n3} and reported in the status reply.
    /// Brother reports 3.5 mm tape as 4.
    public let widthByte: UInt8
    /// Unprinted pins before the print area, counted from pin 0 (§2.3.5).
    public let leftMarginPins: Int
    /// Printable pins across the tape (§2.3.5); the label bitmap height.
    public let printAreaPins: Int
    /// Unprinted pins after the print area (§2.3.5).
    public let rightMarginPins: Int

    public init(
        id: Int,
        name: String,
        kind: MediaKind,
        nominalWidthMM: Double,
        widthByte: UInt8,
        leftMarginPins: Int,
        printAreaPins: Int,
        rightMarginPins: Int
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.nominalWidthMM = nominalWidthMM
        self.widthByte = widthByte
        self.leftMarginPins = leftMarginPins
        self.printAreaPins = printAreaPins
        self.rightMarginPins = rightMarginPins
    }

    public var totalPins: Int { leftMarginPins + printAreaPins + rightMarginPins }
}

public extension Media {
    // MARK: TZe laminated tape (§2.3.2 (a), §2.3.5 TZe table)
    static let tze3_5mm = Media(id: 263, name: "TZe 3.5 mm", kind: .laminatedTape, nominalWidthMM: 3.5, widthByte: 4, leftMarginPins: 52, printAreaPins: 24, rightMarginPins: 52)
    static let tze6mm = Media(id: 257, name: "TZe 6 mm", kind: .laminatedTape, nominalWidthMM: 6, widthByte: 6, leftMarginPins: 48, printAreaPins: 32, rightMarginPins: 48)
    static let tze9mm = Media(id: 258, name: "TZe 9 mm", kind: .laminatedTape, nominalWidthMM: 9, widthByte: 9, leftMarginPins: 39, printAreaPins: 50, rightMarginPins: 39)
    static let tze12mm = Media(id: 259, name: "TZe 12 mm", kind: .laminatedTape, nominalWidthMM: 12, widthByte: 12, leftMarginPins: 29, printAreaPins: 70, rightMarginPins: 29)
    static let tze18mm = Media(id: 260, name: "TZe 18 mm", kind: .laminatedTape, nominalWidthMM: 18, widthByte: 18, leftMarginPins: 8, printAreaPins: 112, rightMarginPins: 8)
    static let tze24mm = Media(id: 261, name: "TZe 24 mm", kind: .laminatedTape, nominalWidthMM: 24, widthByte: 24, leftMarginPins: 0, printAreaPins: 128, rightMarginPins: 0)

    // MARK: Heat-shrink tube 2:1 (§2.3.2 Heat-Shrink Tube, §2.3.5 HS table)
    // The spec's status width table (4 "ESC i S" (3)) lists TZe widths only.
    // Heat-shrink width bytes below are the nominal width rounded to whole mm:
    // unverified against hardware.
    static let hs5_8mm = Media(id: 415, name: "HS 5.8 mm", kind: .heatShrinkTube2to1, nominalWidthMM: 5.8, widthByte: 6, leftMarginPins: 50, printAreaPins: 28, rightMarginPins: 50)
    static let hs8_8mm = Media(id: 416, name: "HS 8.8 mm", kind: .heatShrinkTube2to1, nominalWidthMM: 8.8, widthByte: 9, leftMarginPins: 40, printAreaPins: 48, rightMarginPins: 40)
    static let hs11_7mm = Media(id: 417, name: "HS 11.7 mm", kind: .heatShrinkTube2to1, nominalWidthMM: 11.7, widthByte: 12, leftMarginPins: 31, printAreaPins: 66, rightMarginPins: 31)
    static let hs17_7mm = Media(id: 418, name: "HS 17.7 mm", kind: .heatShrinkTube2to1, nominalWidthMM: 17.7, widthByte: 18, leftMarginPins: 11, printAreaPins: 106, rightMarginPins: 11)
    static let hs23_6mm = Media(id: 419, name: "HS 23.6 mm", kind: .heatShrinkTube2to1, nominalWidthMM: 23.6, widthByte: 24, leftMarginPins: 0, printAreaPins: 128, rightMarginPins: 0)

    // MARK: Heat-shrink tube 3:1
    static let hs5_2mm = Media(id: 420, name: "HS 5.2 mm", kind: .heatShrinkTube3to1, nominalWidthMM: 5.2, widthByte: 5, leftMarginPins: 54, printAreaPins: 20, rightMarginPins: 54)
    static let hs9_0mm = Media(id: 421, name: "HS 9.0 mm", kind: .heatShrinkTube3to1, nominalWidthMM: 9.0, widthByte: 9, leftMarginPins: 42, printAreaPins: 44, rightMarginPins: 42)
    static let hs11_2mm = Media(id: 422, name: "HS 11.2 mm", kind: .heatShrinkTube3to1, nominalWidthMM: 11.2, widthByte: 11, leftMarginPins: 39, printAreaPins: 50, rightMarginPins: 39)
    static let hs21_0mm = Media(id: 423, name: "HS 21.0 mm", kind: .heatShrinkTube3to1, nominalWidthMM: 21.0, widthByte: 21, leftMarginPins: 4, printAreaPins: 120, rightMarginPins: 4)

    static let allTZe: [Media] = [.tze3_5mm, .tze6mm, .tze9mm, .tze12mm, .tze18mm, .tze24mm]
    static let allHeatShrink: [Media] = [.hs5_8mm, .hs8_8mm, .hs11_7mm, .hs17_7mm, .hs23_6mm, .hs5_2mm, .hs9_0mm, .hs11_2mm, .hs21_0mm]
}
