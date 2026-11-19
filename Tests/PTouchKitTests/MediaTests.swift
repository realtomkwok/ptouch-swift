import Testing
@testable import PTouchKit

@Suite("Media and model tables")
struct MediaTests {
    @Test("Every medium fills the 128-pin head", arguments: PrinterModel.ptP710BT.supportedMedia)
    func pinsSumToHead(media: Media) {
        #expect(media.totalPins == PrinterModel.ptP710BT.headPins)
    }

    @Test func bytesPerLine() {
        #expect(PrinterModel.ptP710BT.bytesPerRasterLine == 16)
    }

    @Test func mediaIDsAreUnique() {
        let ids = PrinterModel.ptP710BT.supportedMedia.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("2 mm is 14 dots at 180 dpi (§2.1 margin example)")
    func twoMillimetreMargin() {
        #expect(dots(fromMillimetres: 2, dpi: 180) == 14)
        #expect(dots(fromMillimetres: 2, dpi: 360) == 28)
    }

    @Test("Spec print-area widths match §2.3.2 dot counts")
    func printAreaMatchesPageSize() {
        #expect(Media.tze24mm.printAreaPins == 128)
        #expect(Media.tze12mm.printAreaPins == 70)
        #expect(Media.tze3_5mm.widthByte == 4)
    }
}
