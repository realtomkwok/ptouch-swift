// Spec: Raster Command Reference PT-E550W/P750W/P710BT v1.02,
// §2.1 "Print data overview", §2.3.5 "Raster line", §4 "Printing Command Details".

/// How raster lines are sent (§4 "M Select compression mode").
public enum Compression: UInt8, Sendable, Hashable {
    case none = 0x00
    /// TIFF PackBits; blank lines are sent as "Z" zero raster graphics.
    case tiff = 0x02
}

/// Settings for one print job.
public struct PrintOptions: Sendable, Hashable {
    /// Cut after each label ("ESC i M" bit 6).
    public var autoCut: Bool
    /// Mirror the print ("ESC i M" bit 7).
    public var mirror: Bool
    /// Chain printing ("ESC i K" bit 3 cleared): don't feed and cut after the
    /// last label, so the next job starts without a leader.
    public var chainPrinting: Bool
    /// Special tape, no cutting ("ESC i K" bit 4).
    public var specialTape: Bool
    /// Feed resolution ("ESC i K" bit 6). Bitmaps must be at this resolution.
    public var resolution: Resolution
    /// Leading and trailing margin in millimetres ("ESC i d"); at least 2 mm (§2.3.3).
    public var marginMM: Double
    public var compression: Compression
    /// End the job with "Control-Z" (print with feeding) rather than "FF" (§4).
    public var feedAfterLastLabel: Bool
    /// Print the whole job this many times, as extra pages.
    public var copies: Int

    public init(
        autoCut: Bool = true,
        mirror: Bool = false,
        chainPrinting: Bool = false,
        specialTape: Bool = false,
        resolution: Resolution = .standard,
        marginMM: Double = 2.0,
        compression: Compression = .tiff,
        feedAfterLastLabel: Bool = true,
        copies: Int = 1
    ) {
        self.autoCut = autoCut
        self.mirror = mirror
        self.chainPrinting = chainPrinting
        self.specialTape = specialTape
        self.resolution = resolution
        self.marginMM = marginMM
        self.compression = compression
        self.feedAfterLastLabel = feedAfterLastLabel
        self.copies = copies
    }
}

/// Byte-level choices where Brother's spec and the ptouch library differ.
/// See docs/protocol/README.md.
public struct EncoderQuirks: Sendable, Hashable {
    /// Zero bytes sent before "ESC @" (§2.1: 100).
    public var invalidateByteCount: Int
    /// Send the real media type in "ESC i z" {n2}; `false` sends 00h.
    public var sendsMediaKindInPrintInformation: Bool
    /// Set "ESC i z" {n9} to 01h on pages after the first.
    public var marksFollowingPages: Bool
    /// With auto cut, send "ESC i A 01h" (cut each label) even though §3 says
    /// the P710BT doesn't support it.
    public var sendsCutEachLabel: Bool
    /// Send a compressed line longer than 16 bytes as one 17-byte literal (§4 "M").
    public var capsCompressedLines: Bool

    public init(
        invalidateByteCount: Int,
        sendsMediaKindInPrintInformation: Bool,
        marksFollowingPages: Bool,
        sendsCutEachLabel: Bool,
        capsCompressedLines: Bool
    ) {
        self.invalidateByteCount = invalidateByteCount
        self.sendsMediaKindInPrintInformation = sendsMediaKindInPrintInformation
        self.marksFollowingPages = marksFollowingPages
        self.sendsCutEachLabel = sendsCutEachLabel
        self.capsCompressedLines = capsCompressedLines
    }

    /// As Brother's Raster Command Reference v1.02 describes.
    public static let spec = EncoderQuirks(
        invalidateByteCount: 100,
        sendsMediaKindInPrintInformation: true,
        marksFollowingPages: true,
        sendsCutEachLabel: false,
        capsCompressedLines: true
    )

    /// Byte-for-byte what ptouch 1.1.0 sends to a PT-P710BT.
    public static let ptouch = EncoderQuirks(
        invalidateByteCount: 200,
        sendsMediaKindInPrintInformation: false,
        marksFollowingPages: false,
        sendsCutEachLabel: true,
        capsCompressedLines: false
    )
}

public enum EncodingError: Error, Equatable, Sendable {
    case noLabels
    case unsupportedMedia(id: Int)
    case unsupportedResolution
    case bitmapHeightMismatch(label: Int, expected: Int, actual: Int)
    case labelTooShort(label: Int, minimumDots: Int, actualDots: Int)
    case labelTooLong(label: Int, maximumDots: Int, actualDots: Int)
    case marginOutOfRange(minimumDots: Int, maximumDots: Int, actualDots: Int)
    case invalidCopies(Int)
}

/// Turns label bitmaps into the byte stream a printer expects.
public struct RasterEncoder: Sendable {
    public let model: PrinterModel
    public let quirks: EncoderQuirks

    public init(model: PrinterModel = .ptP710BT, quirks: EncoderQuirks = .spec) {
        self.model = model
        self.quirks = quirks
    }

    /// Encodes a job: one page per label (repeated `copies` times), each ended
    /// by "FF" except the last, which ends with "Control-Z" when feeding.
    public func encode(_ labels: [LabelBitmap], media: Media, options: PrintOptions = PrintOptions()) throws -> [UInt8] {
        guard !labels.isEmpty else { throw EncodingError.noLabels }
        guard model.supportedMedia.contains(media) else { throw EncodingError.unsupportedMedia(id: media.id) }
        guard options.resolution == .standard || model.supportsHighResolution else {
            throw EncodingError.unsupportedResolution
        }
        guard options.copies >= 1 else { throw EncodingError.invalidCopies(options.copies) }

        let limits = Limits.forMedia(media.kind, resolution: options.resolution)
        let marginDots = dots(fromMillimetres: options.marginMM, dpi: options.resolution.feedDPI)
        guard (limits.minimumMarginDots...limits.maximumMarginDots).contains(marginDots) else {
            throw EncodingError.marginOutOfRange(
                minimumDots: limits.minimumMarginDots, maximumDots: limits.maximumMarginDots, actualDots: marginDots)
        }
        for (i, label) in labels.enumerated() {
            guard label.height == media.printAreaPins else {
                throw EncodingError.bitmapHeightMismatch(label: i, expected: media.printAreaPins, actual: label.height)
            }
            // §2.3.4: the print data length includes both margins.
            let length = label.width + 2 * marginDots
            guard length >= limits.minimumLengthDots else {
                throw EncodingError.labelTooShort(label: i, minimumDots: limits.minimumLengthDots, actualDots: length)
            }
            guard length <= limits.maximumLengthDots else {
                throw EncodingError.labelTooLong(label: i, maximumDots: limits.maximumLengthDots, actualDots: length)
            }
        }

        let pages = Array(repeatElement(labels, count: options.copies).joined())
        var out: [UInt8] = []

        // (1) Initialization commands, once per job (§2.1).
        out.append(contentsOf: repeatElement(0x00, count: quirks.invalidateByteCount)) // NULL Invalidate
        out.append(contentsOf: [0x1B, 0x40]) // ESC @ Initialize

        for (index, page) in pages.enumerated() {
            appendControlCodes(to: &out, page: page, index: index, media: media, options: options, marginDots: marginDots)
            appendRaster(to: &out, page: page, media: media, compression: options.compression)
            // (4) Print command (§4 "FF", "Control-Z").
            let isLast = index == pages.count - 1
            out.append(isLast && options.feedAfterLastLabel ? 0x1A : 0x0C)
        }
        return out
    }

    // (2) Control codes, sent at the start of every page (§2.1).
    private func appendControlCodes(
        to out: inout [UInt8], page: LabelBitmap, index: Int, media: Media, options: PrintOptions, marginDots: Int
    ) {
        // ESC i a 01h: switch to raster mode.
        out.append(contentsOf: [0x1B, 0x69, 0x61, 0x01])

        // ESC i z: print information.
        let piKind: UInt8 = 0x02, piWidth: UInt8 = 0x04, piRecover: UInt8 = 0x80
        let rasterCount = UInt32(page.width)
        out.append(contentsOf: [0x1B, 0x69, 0x7A])
        out.append(contentsOf: [
            piRecover | piWidth | piKind,
            quirks.sendsMediaKindInPrintInformation ? media.kind.rawValue : 0x00,
            media.widthByte,
            0x00, // n4 media length: 00h for continuous tape
            UInt8(truncatingIfNeeded: rasterCount),
            UInt8(truncatingIfNeeded: rasterCount >> 8),
            UInt8(truncatingIfNeeded: rasterCount >> 16),
            UInt8(truncatingIfNeeded: rasterCount >> 24),
            index > 0 && quirks.marksFollowingPages ? 0x01 : 0x00, // n9 starting page
            0x00, // n10 fixed
        ])

        // ESC i M: various mode settings.
        var mode: UInt8 = 0
        if options.autoCut { mode |= 0x40 }
        if options.mirror { mode |= 0x80 }
        out.append(contentsOf: [0x1B, 0x69, 0x4D, mode])

        // ESC i A: cut each N labels, only meaningful with auto cut (§2.1).
        // Not supported on the P710BT (§3).
        if options.autoCut, quirks.sendsCutEachLabel || model.supportsCutEachNLabels {
            out.append(contentsOf: [0x1B, 0x69, 0x41, 0x01])
        }

        // ESC i K: advanced mode settings.
        var advanced: UInt8 = 0
        if !options.chainPrinting { advanced |= 0x08 }
        if options.specialTape { advanced |= 0x10 }
        if options.resolution == .high { advanced |= 0x40 }
        out.append(contentsOf: [0x1B, 0x69, 0x4B, advanced])

        // ESC i d: margin in dots, little-endian.
        out.append(contentsOf: [0x1B, 0x69, 0x64, UInt8(marginDots & 0xFF), UInt8(marginDots >> 8)])

        // M: compression mode.
        out.append(contentsOf: [0x4D, options.compression.rawValue])
    }

    // (3) Raster data (§2.3.5, §4 "G", "Z").
    private func appendRaster(to out: inout [UInt8], page: LabelBitmap, media: Media, compression: Compression) {
        let lineBytes = model.bytesPerRasterLine
        var line = [UInt8](repeating: 0, count: lineBytes)
        for x in 0..<page.width {
            for i in 0..<lineBytes { line[i] = 0 }
            var blank = true
            for y in 0..<page.height where page[x, y] {
                let pin = media.leftMarginPins + y
                line[pin / 8] |= 0x80 >> UInt8(pin % 8)
                blank = false
            }

            switch compression {
            case .none:
                out.append(contentsOf: [0x47, UInt8(lineBytes & 0xFF), UInt8(lineBytes >> 8)])
                out.append(contentsOf: line)
            case .tiff:
                if blank {
                    out.append(0x5A)
                    continue
                }
                var data = PackBits.encode(line)
                if quirks.capsCompressedLines, data.count > lineBytes {
                    data = [UInt8(lineBytes - 1)] + line
                }
                out.append(contentsOf: [0x47, UInt8(data.count & 0xFF), UInt8(data.count >> 8)])
                out.append(contentsOf: data)
            }
        }
    }
}
