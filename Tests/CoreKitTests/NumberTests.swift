import CoreKit
import Testing

@Test func integersRoundUpWhenDividedAndToAMultiple() {
    #expect(7.dividedRoundingUp(by: 2) == 4)
    #expect(8.dividedRoundingUp(by: 2) == 4)
    #expect(0.dividedRoundingUp(by: 2) == 0)
    #expect((-7).dividedRoundingUp(by: 2) == -3)
    #expect(UInt64.max.dividedRoundingUp(by: 2) == 1 << 63)

    #expect(18.roundedUp(toMultipleOf: 16) == 32)
    #expect(32.roundedUp(toMultipleOf: 16) == 32)
    #expect(0.roundedUp(toMultipleOf: 16) == 0)
}

@Test func durationMillisecondsAreWhole() {
    #expect(Duration.seconds(2).milliseconds == 2000)
    #expect(Duration.milliseconds(1500).milliseconds == 1500)
    #expect(Duration.microseconds(1999).milliseconds == 1)
    #expect(Duration.zero.milliseconds == 0)
}
