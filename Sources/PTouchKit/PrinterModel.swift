// Spec: Raster Command Reference PT-E550W/P750W/P710BT v1.02.

/// A printer model's fixed capabilities.
public struct PrinterModel: Sendable, Hashable {
    public let name: String
    /// USB vendor ID (Appendix A).
    public let usbVendorID: UInt16
    /// USB product ID (Appendix A).
    public let usbProductID: UInt16
    /// Pins on the print head (§2.3.5: 128).
    public let headPins: Int
    /// Base resolution in dots per inch, both directions (§2.3.1).
    public let dpi: Int
    /// 180 × 360 dpi printing via "ESC i K" bit 6 (§2.3.1, §4).
    public let supportsHighResolution: Bool
    /// Half cut via "ESC i K" bit 2. Not used on the P710BT (§4).
    public let supportsHalfCut: Bool
    /// "ESC i A" cut-each-N-labels. Not supported on the P710BT (§3).
    public let supportsCutEachNLabels: Bool
    /// "ESC i !" automatic status notification. Not supported on the E550W/P750W (§2.1).
    public let supportsAutoStatusNotification: Bool
    /// "ESC i S" status request. Not supported on the E550W/P750W (§3).
    public let supportsStatusRequest: Bool
    public let supportedMedia: [Media]

    /// Bytes per raster line: head pins / 8 (§4 "G": n = 16 uncompressed).
    public var bytesPerRasterLine: Int { headPins / 8 }
}

public extension PrinterModel {
    static let ptP710BT = PrinterModel(
        name: "PT-P710BT",
        usbVendorID: 0x04F9,
        usbProductID: 0x20AF,
        headPins: 128,
        dpi: 180,
        supportsHighResolution: true,
        supportsHalfCut: false,
        supportsCutEachNLabels: false,
        supportsAutoStatusNotification: true,
        supportsStatusRequest: true,
        supportedMedia: Media.allTZe + Media.allHeatShrink
    )
}
