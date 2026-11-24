import CoreKitMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let macros = [
    "GET": MacroSpec(type: RouteMacro.self),
    "POST": MacroSpec(type: RouteMacro.self),
    "DELETE": MacroSpec(type: RouteMacro.self),
]

@Test func routesBindParametersByShapeAndRegisterInTheRouteSection() {
    assertExpansion(
        """
        /// Creates a order.
        @POST(orderRouter, "/", maxBodySize: "1mb")
        func createOrder(user: AuthUser, body: CreateOrderInput) async throws -> OrderResponse { fatalError() }

        @DELETE(orderRouter, "/:orderID")
        func deleteOrder(request: Request, orderID: Int64, query: DeleteOrderQuery) async throws {}
        """,
        expandedSource: """
            /// Creates a order.
            func createOrder(user: AuthUser, body: CreateOrderInput) async throws -> OrderResponse { fatalError() }

            private func __endpoint_createOrder() -> CoreKitHummingbird.RouteRegistration {
                CoreKitHummingbird.RouteRegistration(
                    router: orderRouter,
                    endpoint: CoreKitHummingbird.Endpoint(
                        method: .post,
                        path: "/",
                        operationID: "create_order",
                        summary: "Creates a order.",
                        pathParameters: [],
                        query: nil,
                        body: CreateOrderInput.self,
                        security: [AuthUser.openAPISecurity],
                        response: .json(OrderResponse.self)
                    ) { request, context in
                        try await CoreKitHummingbird.RouteBinding.json(
                            createOrder(user: AuthUser.resolve(from: request), body: CoreKitHummingbird.RouteBinding.body(CreateOrderInput.self, in: request, context: context, maxBodySize: "1mb")), for: request, context: context)
                    }
                )
            }

            #if objectFormat(MachO)
            @used @section("__DATA_CONST,__corekit_routes")
            let __route_createOrder: CoreKitHummingbird.RouteRecord = {
                CoreKitHummingbird.RouteRegistration.write(__endpoint_createOrder(), to: $0)
            }
            #elseif objectFormat(ELF)
            @used @section("corekit_routes")
            let __route_createOrder: CoreKitHummingbird.RouteRecord = {
                CoreKitHummingbird.RouteRegistration.write(__endpoint_createOrder(), to: $0)
            }
            #else
            #error("Route discovery supports Mach-O and ELF binaries only")
            #endif
            func deleteOrder(request: Request, orderID: Int64, query: DeleteOrderQuery) async throws {}

            private func __endpoint_deleteOrder() -> CoreKitHummingbird.RouteRegistration {
                CoreKitHummingbird.RouteRegistration(
                    router: orderRouter,
                    endpoint: CoreKitHummingbird.Endpoint(
                        method: .delete,
                        path: "/:orderID",
                        operationID: "delete_order",
                        summary: nil,
                        pathParameters: [.init("orderID", Int64.self)],
                        query: DeleteOrderQuery.self,
                        body: nil,
                        security: [],
                        response: .noContent
                    ) { request, context in
                        try await CoreKitHummingbird.RouteBinding.noContent(
                            deleteOrder(request: request, orderID: CoreKitHummingbird.RouteBinding.pathParameter("orderID", as: Int64.self, in: request, context: context), query: CoreKitHummingbird.RouteBinding.query(DeleteOrderQuery.self, in: request, context: context)), for: request, context: context)
                    }
                )
            }

            #if objectFormat(MachO)
            @used @section("__DATA_CONST,__corekit_routes")
            let __route_deleteOrder: CoreKitHummingbird.RouteRecord = {
                CoreKitHummingbird.RouteRegistration.write(__endpoint_deleteOrder(), to: $0)
            }
            #elseif objectFormat(ELF)
            @used @section("corekit_routes")
            let __route_deleteOrder: CoreKitHummingbird.RouteRecord = {
                CoreKitHummingbird.RouteRegistration.write(__endpoint_deleteOrder(), to: $0)
            }
            #else
            #error("Route discovery supports Mach-O and ELF binaries only")
            #endif
            """,
        macros: macros
    )
}

@Test func routesRejectUnboundPathParameters() {
    assertExpansion(
        """
        @GET(orderRouter, "/:orderID")
        func showOrder(id: Int64) async throws -> OrderResponse { fatalError() }
        """,
        expandedSource: """
            func showOrder(id: Int64) async throws -> OrderResponse { fatalError() }
            """,
        diagnostics: [
            DiagnosticSpec(message: "Path parameter ':orderID' has no matching function parameter named 'orderID'", line: 1, column: 1)
        ],
        macros: macros
    )
}

@Test func routesRejectBodySizesThatAreNotByteCounts() {
    assertExpansion(
        """
        @POST(orderRouter, "/", maxBodySize: "10 mb")
        func createOrder(body: CreateOrderInput) async throws {}

        @POST(orderRouter, "/", maxBodySize: "1.5mb")
        func createOrder(body: CreateOrderInput) async throws {}

        @POST(orderRouter, "/", maxBodySize: "9999999999gb")
        func createOrder(body: CreateOrderInput) async throws {}
        """,
        expandedSource: """
            func createOrder(body: CreateOrderInput) async throws {}
            func createOrder(body: CreateOrderInput) async throws {}
            func createOrder(body: CreateOrderInput) async throws {}
            """,
        diagnostics: ["10 mb", "1.5mb", "9999999999gb"].enumerated().map { index, size in
            DiagnosticSpec(
                message: "maxBodySize \"\(size)\" isn't a byte count: write a whole number with an optional b, kb, mb or gb, e.g. \"10mb\"",
                line: 1 + 3 * index,
                column: 1
            )
        },
        macros: macros
    )
}

/// The check reads the literal as Swift does, so escapes spell the same byte count.
@Test func routesReadEscapesInBodySizes() {
    assertExpansion(
        #"""
        @POST(orderRouter, "/", maxBodySize: "\u{31}0mb")
        func createOrder(body: CreateOrderInput) async throws {}
        """#,
        expandedSource: #"""
            func createOrder(body: CreateOrderInput) async throws {}

            private func __endpoint_createOrder() -> CoreKitHummingbird.RouteRegistration {
                CoreKitHummingbird.RouteRegistration(
                    router: orderRouter,
                    endpoint: CoreKitHummingbird.Endpoint(
                        method: .post,
                        path: "/",
                        operationID: "create_order",
                        summary: nil,
                        pathParameters: [],
                        query: nil,
                        body: CreateOrderInput.self,
                        security: [],
                        response: .noContent
                    ) { request, context in
                        try await CoreKitHummingbird.RouteBinding.noContent(
                            createOrder(body: CoreKitHummingbird.RouteBinding.body(CreateOrderInput.self, in: request, context: context, maxBodySize: "\u{31}0mb")), for: request, context: context)
                    }
                )
            }

            #if objectFormat(MachO)
            @used @section("__DATA_CONST,__corekit_routes")
            let __route_createOrder: CoreKitHummingbird.RouteRecord = {
                CoreKitHummingbird.RouteRegistration.write(__endpoint_createOrder(), to: $0)
            }
            #elseif objectFormat(ELF)
            @used @section("corekit_routes")
            let __route_createOrder: CoreKitHummingbird.RouteRecord = {
                CoreKitHummingbird.RouteRegistration.write(__endpoint_createOrder(), to: $0)
            }
            #else
            #error("Route discovery supports Mach-O and ELF binaries only")
            #endif
            """#,
        macros: macros
    )
}
