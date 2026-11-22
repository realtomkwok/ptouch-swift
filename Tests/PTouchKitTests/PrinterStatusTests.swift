import Testing
@testable import PTouchKit

/// Builds a status reply from the §4 "ESC i S" layout.
func reply(
    model: UInt8 = 0x66,
    error1: UInt8 = 0, error2: UInt8 = 0,
    width: UInt8 = 24, kind: UInt8 = 0x01,
    mode: UInt8 = 0,
    statusType: UInt8 = 0, phaseType: UInt8 = 0, phase: UInt16 = 0,
    notification: UInt8 = 0, tapeColor: UInt8 = 0x01, textColor: UInt8 = 0x08
) -> [UInt8] {
    var b = [UInt8](repeating: 0, count: 32)
    b[0] = 0x80; b[1] = 0x20; b[2] = 0x42; b[3] = 0x30; b[4] = model; b[5] = 0x30
    b[8] = error1; b[9] = error2; b[10] = width; b[11] = kind; b[15] = mode
    b[18] = statusType; b[19] = phaseType; b[20] = UInt8(phase >> 8); b[21] = UInt8(phase & 0xFF)
    b[22] = notification; b[24] = tapeColor; b[25] = textColor
    return b
}

@Suite("Printer status")
struct PrinterStatusTests {
    @Test func requestCommand() {
        #expect(statusRequestCommand == [0x1B, 0x69, 0x53])
    }

    @Test("Ready with 24 mm white/black laminated tape")
    func ready() throws {
        let s = try PrinterStatus(bytes: reply())
        #expect(s.errors.isEmpty)
        #expect(s.statusType == .replyToRequest)
        #expect(s.phase == .receiving)
        #expect(s.loadedMedia() == .tze24mm)
        #expect(s.isReadyToPrint)
        #expect(TapeColor.names[s.tapeColorID] == "White")
        #expect(TextColor.names[s.textColorID] == "Black")
    }

    @Test("3.5 mm tape is reported as width 4")
    func narrowTape() throws {
        #expect(try PrinterStatus(bytes: reply(width: 4)).loadedMedia() == .tze3_5mm)
    }

    @Test("Non-laminated tape uses the laminated pin layout")
    func nonLaminated() throws {
        let s = try PrinterStatus(bytes: reply(width: 12, kind: 0x03))
        #expect(s.mediaKind == .nonLaminatedTape)
        #expect(s.loadedMedia() == .tze12mm)
    }

    @Test("No tape")
    func noTape() throws {
        let s = try PrinterStatus(bytes: reply(error1: 0x01, width: 0, kind: 0x00, statusType: 0x02))
        #expect(s.errors == .noMedia)
        #expect(s.statusType == .errorOccurred)
        #expect(s.loadedMedia() == nil)
        #expect(!s.isReadyToPrint)
    }

    @Test("Error bits from tables (1) and (2)")
    func errorBits() throws {
        let s = try PrinterStatus(bytes: reply(error1: 0x04 | 0x08 | 0x40, error2: 0x01 | 0x10 | 0x20))
        #expect(s.errors == [.cutterJam, .weakBatteries, .highVoltageAdapter, .wrongMedia, .coverOpen, .overheating])
        #expect(s.errors.description == "[cutterJam, weakBatteries, highVoltageAdapter, wrongMedia, coverOpen, overheating]")
    }

    @Test("Phases from table (6)", arguments: [
        (UInt8(0), UInt16(0), PrinterStatus.Phase.receiving),
        (0, 1, .feeding),
        (1, 0, .printing),
        (1, 20, .coverOpenWhileReceiving),
        (1, 10, .other(type: 1, number: 10)),
    ])
    func phases(type: UInt8, number: UInt16, expected: PrinterStatus.Phase) throws {
        #expect(try PrinterStatus(bytes: reply(phaseType: type, phase: number)).phase == expected)
    }

    @Test("Printing completed, then phase change back to receiving")
    func printFlow() throws {
        #expect(try PrinterStatus(bytes: reply(statusType: 0x01, phaseType: 1)).statusType == .printingCompleted)
        let back = try PrinterStatus(bytes: reply(statusType: 0x06))
        #expect(back.statusType == .phaseChange)
        #expect(back.phase == .receiving)
    }

    @Test("Cover notifications from table (7)")
    func notifications() throws {
        #expect(try PrinterStatus(bytes: reply(statusType: 5, notification: 1)).notification == .coverOpened)
        #expect(try PrinterStatus(bytes: reply(statusType: 5, notification: 2)).notification == .coverClosed)
    }

    @Test("Incompatible tape")
    func incompatible() throws {
        let s = try PrinterStatus(bytes: reply(kind: 0xFF, tapeColor: 0xFF))
        #expect(s.mediaKind == .incompatible)
        #expect(s.loadedMedia() == nil)
    }

    @Test func rejectsBadInput() {
        #expect(throws: PrinterStatus.ParseError.wrongLength(31)) { try PrinterStatus(bytes: reply().prefix(31)) }
        var bad = reply()
        bad[2] = 0x41
        #expect(throws: PrinterStatus.ParseError.badHeader) { try PrinterStatus(bytes: bad) }
    }
}

@Suite("Printer problems")
struct PrinterProblemTests {
    @Test func noneWhenReady() throws {
        #expect(try PrinterStatus(bytes: reply()).problems.isEmpty)
    }

    @Test("Every error flag maps to a problem")
    func everyFlag() throws {
        let s = try PrinterStatus(bytes: reply(error1: 0x01 | 0x04 | 0x08 | 0x40, error2: 0x01 | 0x10 | 0x20, width: 0, kind: 0))
        #expect(s.problems == [.coverOpen, .noTape, .cutterJam, .overheating, .wrongPowerAdapter, .wrongTape, .weakBatteries])
    }

    @Test("No tape without an error flag still reads as no tape")
    func emptyMediaKind() throws {
        #expect(try PrinterStatus(bytes: reply(width: 0, kind: 0)).problems == [.noTape])
    }

    @Test("Empty cassette bay reads as no tape, with the load-a-tape advice")
    func emptyBay() throws {
        let s = try PrinterStatus(bytes: reply(error1: 0x01, width: 0, kind: 0x00, statusType: 0x02))
        #expect(s.problems == [.noTape])
        #expect(PrinterProblem.noTape.recovery.contains("tape cassette is in the printer"))
    }

    @Test("No-media error that sticks after a 12 mm cassette goes in needs a restart")
    func stuckNoMedia() throws {
        let bytes: [UInt8] = [
            0x80, 0x20, 0x42, 0x30, 0x76, 0x30, 0x00, 0x00, 0x01, 0x00, 0x0C, 0x01, 0x01, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        ]
        let s = try PrinterStatus(bytes: bytes)
        #expect(s.errors == .noMedia)
        #expect(s.mediaWidthMM == 12)
        #expect(s.loadedMedia() == .tze12mm)
        #expect(s.problems == [.needsRestart])
        #expect(s.problem(printing: .tze12mm) == .needsRestart)
        #expect(PrinterProblem.needsRestart.title == "The printer needs a restart")
        #expect(PrinterProblem.needsRestart.recovery.contains("power button twice"))
        #expect(PrinterProblem.needsRestart.recovery.contains("off and on"))
    }

    @Test func incompatibleTape() throws {
        #expect(try PrinterStatus(bytes: reply(kind: 0xFF)).problems == [.unsupportedTape])
    }

    @Test("Label made for 12 mm with 24 mm loaded")
    func mismatch() throws {
        let s = try PrinterStatus(bytes: reply(width: 24))
        #expect(s.problem(printing: .tze12mm) == .wrongTape)
        #expect(s.problem(printing: .tze24mm) == nil)
    }

    @Test("Every problem has text", arguments: PrinterProblem.allCases)
    func text(problem: PrinterProblem) {
        #expect(!problem.title.isEmpty)
        #expect(problem.recovery.hasSuffix("."))
    }
}
