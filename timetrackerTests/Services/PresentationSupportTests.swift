import Foundation
import Testing
@testable import timetracker

struct PresentationSupportTests {
    @Test
    func elapsedClockStylesPreserveTheirPlatformShapes() {
        let locale = Locale(identifier: "en_US")

        #expect(ElapsedClockFormatter.padded(65) == "01:05")
        #expect(ElapsedClockFormatter.padded(3661) == "01:01:01")
        #expect(ElapsedClockFormatter.compact(65, locale: locale) == "1:05")
        #expect(ElapsedClockFormatter.compact(3661, locale: locale) == "1:01:01")
        #expect(ElapsedClockFormatter.full(65, locale: locale) == "0:01:05")
        #expect(ElapsedClockFormatter.padded(-1) == "00:00")
    }

    @Test
    func hexParserNormalizesShorthandAndProducesSRGBComponents() throws {
        #expect(HexColorParser.normalized(" #aBc ") == "AABBCC")
        let rgb = try #require(HexColorParser.components(for: "AABBCC"))
        #expect(rgb.red == Double(0xAA) / 255)
        #expect(rgb.green == Double(0xBB) / 255)
        #expect(rgb.blue == Double(0xCC) / 255)
        #expect(HexColorParser.components(for: "not-a-color") == nil)
    }
}
