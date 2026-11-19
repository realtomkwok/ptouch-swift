/// Something stopping the printer from printing, in words a person can act on.
///
/// The text is English. Apps that localise can switch on the case instead.
public enum PrinterProblem: Sendable, Hashable, CaseIterable {
    /// No tape, or the cover is open: the P710BT reports both as "no media".
    case noTape
    case cutterJam
    case weakBatteries
    case wrongPowerAdapter
    case wrongTape
    case coverOpen
    case overheating
    case unsupportedTape

    /// A short headline, e.g. for an alert title.
    public var title: String {
        switch self {
        case .noTape: "No tape detected"
        case .cutterJam: "The cutter is jammed"
        case .weakBatteries: "The battery is low"
        case .wrongPowerAdapter: "Wrong power adapter"
        case .wrongTape: "Wrong tape loaded"
        case .coverOpen: "The cover is open"
        case .overheating: "The printer is too hot"
        case .unsupportedTape: "This tape isn't supported"
        }
    }

    /// What to do about it.
    public var recovery: String {
        switch self {
        case .noTape: "Check that a tape cassette is in the printer and the cover is closed."
        case .cutterJam: "Turn the printer off, open the cover and clear any tape caught in the cutter."
        case .weakBatteries: "Charge the printer or plug in its power adapter."
        case .wrongPowerAdapter: "Use the power adapter that came with the printer."
        case .wrongTape: "Load the tape this label was made for, or change the label to match the loaded tape. Then press the printer's power button to clear the error."
        case .coverOpen: "Close the tape cassette cover."
        case .overheating: "Let the printer cool down for a few minutes, then print again."
        case .unsupportedTape: "Use a Brother TZe tape or heat-shrink tube the printer supports."
        }
    }
}

public extension PrinterStatus {
    /// Problems the printer reports, most urgent first. Empty when it can print.
    var problems: [PrinterProblem] {
        var result: [PrinterProblem] = []
        if errors.contains(.coverOpen) { result.append(.coverOpen) }
        if errors.contains(.noMedia) { result.append(.noTape) }
        if errors.contains(.cutterJam) { result.append(.cutterJam) }
        if errors.contains(.overheating) { result.append(.overheating) }
        if errors.contains(.highVoltageAdapter) { result.append(.wrongPowerAdapter) }
        if errors.contains(.wrongMedia) { result.append(.wrongTape) }
        if errors.contains(.weakBatteries) { result.append(.weakBatteries) }
        if !errors.contains(.noMedia) {
            switch mediaKind {
            case .incompatible?, nil:
                result.append(.unsupportedTape)
            case .some(.none):
                result.append(.noTape)
            default:
                if loadedMedia() == nil { result.append(.unsupportedTape) }
            }
        }
        return result
    }

    /// Whether the loaded tape suits a label made for `media`. Returns
    /// `.wrongTape` on a mismatch; other problems come from `problems`.
    func problem(printing media: Media, on model: PrinterModel = .ptP710BT) -> PrinterProblem? {
        if let first = problems.first { return first }
        return loadedMedia(for: model) == media ? nil : .wrongTape
    }
}
