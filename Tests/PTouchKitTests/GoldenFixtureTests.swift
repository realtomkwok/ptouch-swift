import Testing
@testable import PTouchKit

@Suite("Golden fixtures load")
struct GoldenFixtureTests {
    @Test func indexIsNotEmpty() throws {
        #expect(try GoldenFixture.all().count >= 20)
    }

    @Test("Bitmaps match the media's print area", arguments: GoldenFixture.cases)
    func bitmapsFitMedia(fixture: GoldenFixture) throws {
        let media = try #require(PrinterModel.ptP710BT.supportedMedia.first { $0.id == fixture.mediaID })
        for bitmap in try fixture.labelBitmaps() {
            #expect(bitmap.height == media.printAreaPins)
            #expect(bitmap.width > 0)
        }
        #expect(try !fixture.expectedBytes().isEmpty)
    }
}
