// Spec: Raster Command Reference PT-E550W/P750W/P710BT v1.02, §4 "ESC i S
// Status information request", status table and tables (1)–(9).

/// The "ESC i S" command that asks the printer for a 32-byte status reply.
/// Send it once before a job, never while printing (§4).
public let statusRequestCommand: [UInt8] = [0x1B, 0x69, 0x53]

/// A parsed 32-byte status reply.
public struct PrinterStatus: Sendable, Hashable {
    public static let byteCount = 32

    /// Error flags: "Error information 1" in the low byte, "Error information 2"
    /// in the high byte (tables (1) and (2)).
    public struct Errors: OptionSet, Sendable, Hashable {
        public let rawValue: UInt16
        public init(rawValue: UInt16) { self.rawValue = rawValue }

        public static let noMedia = Errors(rawValue: 0x0001)
        public static let cutterJam = Errors(rawValue: 0x0004)
        public static let weakBatteries = Errors(rawValue: 0x0008)
        public static let highVoltageAdapter = Errors(rawValue: 0x0040)
        /// "Replace media": the loaded media doesn't match the print information.
        public static let wrongMedia = Errors(rawValue: 0x0100)
        public static let coverOpen = Errors(rawValue: 0x1000)
        public static let overheating = Errors(rawValue: 0x2000)

        static let named: [(Errors, String)] = [
            (.noMedia, "noMedia"), (.cutterJam, "cutterJam"), (.weakBatteries, "weakBatteries"),
            (.highVoltageAdapter, "highVoltageAdapter"), (.wrongMedia, "wrongMedia"),
            (.coverOpen, "coverOpen"), (.overheating, "overheating"),
        ]
    }

    /// Why the printer sent this status (table (5)).
    public enum StatusType: Sendable, Hashable {
        case replyToRequest
        case printingCompleted
        case errorOccurred
        case turnedOff
        case notification
        case phaseChange
        case other(UInt8)

        init(_ raw: UInt8) {
            switch raw {
            case 0x00: self = .replyToRequest
            case 0x01: self = .printingCompleted
            case 0x02: self = .errorOccurred
            case 0x04: self = .turnedOff
            case 0x05: self = .notification
            case 0x06: self = .phaseChange
            default: self = .other(raw)
            }
        }
    }

    /// What the printer is doing (table (6)).
    public enum Phase: Sendable, Hashable {
        /// Editing state, ready to receive.
        case receiving
        case feeding
        case printing
        case coverOpenWhileReceiving
        case other(type: UInt8, number: UInt16)

        init(type: UInt8, number: UInt16) {
            switch (type, number) {
            case (0x00, 0): self = .receiving
            case (0x00, 1): self = .feeding
            case (0x01, 0): self = .printing
            case (0x01, 20): self = .coverOpenWhileReceiving
            default: self = .other(type: type, number: number)
            }
        }
    }

    /// Table (7).
    public enum Notification: Sendable, Hashable {
        case none
        case coverOpened
        case coverClosed
        case other(UInt8)

        init(_ raw: UInt8) {
            switch raw {
            case 0x00: self = .none
            case 0x01: self = .coverOpened
            case 0x02: self = .coverClosed
            default: self = .other(raw)
            }
        }
    }

    public enum ParseError: Error, Equatable, Sendable {
        case wrongLength(Int)
        /// Bytes 0–2 aren't 80h 20h "B".
        case badHeader
    }

    /// The 32 bytes as received.
    public let raw: [UInt8]

    /// Offset 4. The spec lists "f" (PT-E550W) and "h" (PT-P750W) only.
    public var modelCode: UInt8 { raw[4] }
    public var errors: Errors { Errors(rawValue: UInt16(raw[8]) | UInt16(raw[9]) << 8) }
    /// Loaded media width in mm as the printer reports it; 3.5 mm tape reads 4 (table (3)).
    public var mediaWidthMM: UInt8 { raw[10] }
    /// `nil` for a value table (4) doesn't define.
    public var mediaKind: MediaKind? { MediaKind(rawValue: raw[11]) }
    /// Offset 15: the last "ESC i M" value, 00h if none.
    public var mode: UInt8 { raw[15] }
    public var statusType: StatusType { StatusType(raw[18]) }
    public var phase: Phase { Phase(type: raw[19], number: UInt16(raw[20]) << 8 | UInt16(raw[21])) }
    public var notification: Notification { Notification(raw[22]) }
    /// Table (8) tape colour ID.
    public var tapeColorID: UInt8 { raw[24] }
    /// Table (9) text colour ID.
    public var textColorID: UInt8 { raw[25] }

    public init(bytes: some Collection<UInt8>) throws {
        let raw = Array(bytes)
        guard raw.count == Self.byteCount else { throw ParseError.wrongLength(raw.count) }
        guard raw[0] == 0x80, raw[1] == 0x20, raw[2] == 0x42 else { throw ParseError.badHeader }
        self.raw = raw
    }

    /// The supported medium matching the reported width and type, if any.
    public func loadedMedia(for model: PrinterModel = .ptP710BT) -> Media? {
        guard let kind = mediaKind, kind != .none, kind != .incompatible else { return nil }
        // Non-laminated TZe tape uses the same pin layout as laminated.
        let layoutKind: MediaKind = kind == .nonLaminatedTape ? .laminatedTape : kind
        return model.supportedMedia.first { $0.kind == layoutKind && $0.widthByte == mediaWidthMM }
    }

    /// `true` when the printer reports no errors and has media loaded.
    public var isReadyToPrint: Bool {
        errors.isEmpty && loadedMedia() != nil
    }
}

extension PrinterStatus.Errors: CustomStringConvertible {
    public var description: String {
        let names = Self.named.filter { contains($0.0) }.map(\.1)
        return "[" + names.joined(separator: ", ") + "]"
    }
}

/// Tape colours from table (8).
public enum TapeColor {
    public static let names: [UInt8: String] = [
        0x01: "White", 0x02: "Other", 0x03: "Clear", 0x04: "Red", 0x05: "Blue", 0x06: "Yellow",
        0x07: "Green", 0x08: "Black", 0x09: "Clear (white text)", 0x20: "Matte white",
        0x21: "Matte clear", 0x22: "Matte silver", 0x23: "Satin gold", 0x24: "Satin silver",
        0x30: "Blue (D)", 0x31: "Red (D)", 0x40: "Fluorescent orange", 0x41: "Fluorescent yellow",
        0x50: "Berry pink (S)", 0x51: "Light gray (S)", 0x52: "Lime green (S)", 0x60: "Yellow (F)",
        0x61: "Pink (F)", 0x62: "Blue (F)", 0x70: "White (heat-shrink tube)", 0x90: "White (Flex. ID)",
        0x91: "Yellow (Flex. ID)", 0xF0: "Cleaning", 0xF1: "Stencil", 0xFF: "Incompatible",
    ]
}

/// Text colours from table (9).
public enum TextColor {
    public static let names: [UInt8: String] = [
        0x01: "White", 0x02: "Other", 0x04: "Red", 0x05: "Blue", 0x08: "Black", 0x0A: "Gold",
        0x62: "Blue (F)", 0xF0: "Cleaning", 0xF1: "Stencil", 0xFF: "Incompatible",
    ]
}
