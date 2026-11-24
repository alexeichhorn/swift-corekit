import CoreKit

@PublicInit
public struct Shipment: Sendable {
    public var orderID: String
    public var carrier: String?
    public var note: String? = nil
    public var items: [String] = []
    public let onDelivered: @Sendable () -> Void
}

let shipment = Shipment(orderID: "42", carrier: nil, onDelivered: {})
// An Optional without `= nil` stays required, so a new field can't be forgotten at a call site.
let withoutCarrier = Shipment(orderID: "42", onDelivered: {})  // error: missing argument for parameter 'carrier'
