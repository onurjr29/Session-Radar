import Testing
@testable import RadarCore


@Test func wrappedLineCountWrapsByWords() {
    #expect(wrappedLineCount("", charsPerLine: 10) == 1)
    #expect(wrappedLineCount("aaaa bbbb", charsPerLine: 9) == 1)
    #expect(wrappedLineCount("aaaa bbbb", charsPerLine: 8) == 2)
    #expect(wrappedLineCount(String(repeating: "x", count: 25), charsPerLine: 10) == 3)   // uzun kelime bölünür
}
@Test func infoRowsHeightCountsWrappedLines() {
    #expect(infoRowsHeight([], charsPerLine: 30) == 0)
    #expect(infoRowsHeight([CardRowSpec("kısa")], charsPerLine: 30) == 32)   // eski 13 + 19
    let long = CardRowSpec(String(repeating: "kelime ", count: 20))
    #expect(infoRowsHeight([long], charsPerLine: 30) > infoRowsHeight([CardRowSpec("kısa")], charsPerLine: 30) + 45)
    #expect(infoRowsHeight([CardRowSpec(long.text, maxLines: 1)], charsPerLine: 30) == 32)
    #expect(charsPerLine(cardWidth: 240) > charsPerLine(cardWidth: 190))
}
