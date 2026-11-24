import CoreKit
import Testing

@Test func secretsAreRedactedWhereverTheyArePrinted() {
    let secret = Secret("sk-live-123")
    var dumped = ""
    dump(secret, to: &dumped)

    #expect(secret.exposedValue == "sk-live-123")
    for text in ["\(secret)", String(describing: secret), String(reflecting: secret), "\([secret])", dumped] {
        #expect(!text.contains("sk-live-123"))
        #expect(text.contains("<redacted>"))
    }
}
