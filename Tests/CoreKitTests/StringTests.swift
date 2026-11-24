import CoreKit
import Foundation
import Testing

@Test func bytePrefixStopsAtAWholeCharacter() {
    #expect("abcdef".prefix(bytes: 4) == "abcd")
    #expect("abc".prefix(bytes: 4) == "abc")
    // `é` is two bytes and `語` three; neither is cut in half.
    #expect("aéé".prefix(bytes: 3) == "aé")
    #expect("aéé".prefix(bytes: 2) == "a")
    #expect("語語".prefix(bytes: 5) == "語")
    #expect("語".prefix(bytes: 0) == "")
}

@Test func rfc3339WritesAFractionOnlyWhenTheDateHasOne() {
    #expect(Date(timeIntervalSince1970: 1_794_659_696).rfc3339 == "2026-11-14T12:34:56+00:00")
    #expect(Date(timeIntervalSince1970: 1_794_659_696.789).rfc3339 == "2026-11-14T12:34:56.789+00:00")
    #expect(Date(timeIntervalSince1970: 1_794_659_696.789123).rfc3339 == "2026-11-14T12:34:56.789123+00:00")
    #expect(Date(timeIntervalSince1970: -0.5).rfc3339 == "1969-12-31T23:59:59.500+00:00")
}

@Test func trimmingWhitespaceFollowsTheWhiteSpaceProperty() {
    #expect("  \t\n text  with  gaps \r\n".trimmingWhitespace() == "text  with  gaps")
    // A no-break space and an ideographic space are whitespace; a zero-width space is not.
    #expect("\u{a0}\u{3000}a\u{2028}".trimmingWhitespace() == "a")
    #expect("\u{200b}a\u{200b}".trimmingWhitespace() == "\u{200b}a\u{200b}")
    #expect(" \n ".trimmingWhitespace() == "")
}

@Test func hexWritesTwoLowercaseDigitsPerByte() {
    #expect([0x00, 0x0f, 0xa0, 0xff].hex == "000fa0ff")
}

@Test func hexWorksOnAnySequenceOfBytes() {
    #expect(Data([0xde, 0xad, 0xbe, 0xef]).hex == "deadbeef")
    #expect("Hi".utf8.hex == "4869")
    #expect([UInt8]().hex == "")
}
