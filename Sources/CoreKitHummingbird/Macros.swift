// Route macros attach a top-level handler function to a router: `@GET(orderRouter, "/:orderID")`. Parameters bind by
// shape (see `RouteMacro`), and every handler is registered by `OpenAPIDocument.register(on:)` without being listed.
//
// `maxBodySize` replaces the body size limit (Hummingbird's 2mb by default) for the route's `body:` or `form:`, e.g.
// `"10mb"`; larger requests get 413.
//
// `head: true` makes a `GET` route answer `HEAD` too, with the same status and headers and no body, e.g. for a health
// check that an uptime monitor probes with `HEAD`. The OpenAPI document lists the `GET` only.

@attached(peer, names: prefixed(__endpoint_), prefixed(__route_))
public macro GET(_ router: APIRouter, _ path: String, head: Bool = false) =
    #externalMacro(module: "CoreKitMacros", type: "RouteMacro")
@attached(peer, names: prefixed(__endpoint_), prefixed(__route_))
public macro POST(_ router: APIRouter, _ path: String, maxBodySize: ByteCount? = nil) =
    #externalMacro(module: "CoreKitMacros", type: "RouteMacro")
@attached(peer, names: prefixed(__endpoint_), prefixed(__route_))
public macro PUT(_ router: APIRouter, _ path: String, maxBodySize: ByteCount? = nil) =
    #externalMacro(module: "CoreKitMacros", type: "RouteMacro")
@attached(peer, names: prefixed(__endpoint_), prefixed(__route_))
public macro PATCH(_ router: APIRouter, _ path: String, maxBodySize: ByteCount? = nil) =
    #externalMacro(module: "CoreKitMacros", type: "RouteMacro")
@attached(peer, names: prefixed(__endpoint_), prefixed(__route_))
public macro DELETE(_ router: APIRouter, _ path: String) = #externalMacro(module: "CoreKitMacros", type: "RouteMacro")
