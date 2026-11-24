import CoreKit
import Testing

@Test func sortedByAPropertyIsAscendingUnlessDescendingIsSet() {
    #expect(["pear", "fig", "banana"].sorted(by: \.count) == ["fig", "pear", "banana"])
    #expect(["pear", "fig", "banana"].sorted(by: \.count, descending: true) == ["banana", "pear", "fig"])
}

@Test func uniquedKeepsTheFirstElementOfEachKeyInOrder() {
    #expect(["pear", "fig", "plum", "kiwi", "apple"].uniqued(on: \.count) == ["pear", "fig", "apple"])
}

@Test func safeSubscriptIsNilOutsideTheCollection() {
    #expect(["fig", "pear"][safe: 1] == "pear")
    #expect(["fig", "pear"][safe: 2] == nil)
    #expect(["fig", "pear"][safe: -1] == nil)
}
