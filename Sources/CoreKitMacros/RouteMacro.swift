import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@GET`, `@POST`, ...: registers a top-level handler function as an `Endpoint` with OpenAPI metadata.
///
/// Parameters bind by shape: a name matching a `:name` path segment is a path parameter, `body` is the JSON
/// body, `form` is a `multipart/form-data` body, `query` is the URL query, `Request` is the raw request, and anything
/// else is `RequestResolvable`.
///
/// The expansion stores a `RouteRecord` in the binary's `corekit_routes` section, where `OpenAPIDocument` finds it.
public struct RouteMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let function = declaration.as(FunctionDeclSyntax.self), context.lexicalContext.isEmpty else {
            throw MacroError("@\(node.attributeName.trimmedDescription) must be applied to a top-level function")
        }
        let name = function.name.text
        let registration = try registration(for: function, attribute: node)
        let record: DeclSyntax = """
            #if objectFormat(MachO)
            @used @section("__DATA_CONST,__corekit_routes")
            let __route_\(raw: name): CoreKitHummingbird.RouteRecord = { CoreKitHummingbird.RouteRegistration.write(__endpoint_\(raw: name)(), to: $0) }
            #elseif objectFormat(ELF)
            @used @section("corekit_routes")
            let __route_\(raw: name): CoreKitHummingbird.RouteRecord = { CoreKitHummingbird.RouteRegistration.write(__endpoint_\(raw: name)(), to: $0) }
            #else
            #error("Route discovery supports Mach-O and ELF binaries only")
            #endif
            """
        return [
            """
            private func __endpoint_\(raw: name)() -> CoreKitHummingbird.RouteRegistration {
                \(raw: indented(registration, by: 4))
            }
            """,
            record,
        ]
    }

    private static func registration(for function: FunctionDeclSyntax, attribute: AttributeSyntax) throws -> String {
        let method = attribute.attributeName.trimmedDescription.split(separator: ".").last.map(String.init) ?? ""
        let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) ?? []
        let unlabeled = arguments.filter { $0.label == nil }.map(\.expression)
        guard unlabeled.count == 2, let path = literalValue(of: unlabeled[1]) else {
            throw MacroError("@\(method) needs a router and a string literal path, e.g. @\(method)(orderRouter, \"/\")")
        }
        let router = unlabeled[0].trimmedDescription
        let maxBodySize = arguments.first { $0.label?.text == "maxBodySize" }?.expression
        // `ByteCount` reads the literal on every request and traps on text it can't read, so it's checked here.
        if let maxBodySize, let size = literalValue(of: maxBodySize), byteCount(size) == nil {
            throw MacroError(
                "maxBodySize \"\(size)\" isn't a byte count: write a whole number with an optional b, kb, mb or gb, e.g. \"10mb\""
            )
        }
        // Only passed when given, so plain routes stay short.
        let bodyLimit = maxBodySize.map { ", maxBodySize: \($0.trimmedDescription)" } ?? ""
        let headOption = arguments.first { $0.label?.text == "head" }.map { "\n        head: \($0.expression.trimmedDescription)," } ?? ""
        let pathParameterNames = path.split(separator: "/").filter { $0.hasPrefix(":") }.map { String($0.dropFirst()) }

        var callArguments: [String] = []
        var pathParameters: [String] = []
        var boundPathParameterNames: Set<String> = []
        var query = "nil"
        var body = "nil"
        var form: String?
        var security: [String] = []
        for parameter in function.signature.parameterClause.parameters {
            let label = parameter.firstName.text
            let name = label == "_" ? (parameter.secondName?.text ?? label) : label
            let type = parameter.type.trimmedDescription
            let value: String
            if pathParameterNames.contains(name) {
                boundPathParameterNames.insert(name)
                pathParameters.append(".init(\(stringLiteral(name)), \(type).self)")
                value =
                    "CoreKitHummingbird.RouteBinding.pathParameter(\(stringLiteral(name)), as: \(type).self, in: request, context: context)"
            } else if name == "body" {
                body = "\(type).self"
                value = "CoreKitHummingbird.RouteBinding.body(\(type).self, in: request, context: context\(bodyLimit))"
            } else if name == "form" {
                form = "\(type).self"
                value = "CoreKitHummingbird.RouteBinding.form(\(type).self, in: request, context: context\(bodyLimit))"
            } else if name == "query" {
                query = "\(type).self"
                value = "CoreKitHummingbird.RouteBinding.query(\(type).self, in: request, context: context)"
            } else if ["Request", "Hummingbird.Request"].contains(type) {
                value = "request"
            } else {
                security.append("\(type).openAPISecurity")
                value = "\(type).resolve(from: request)"
            }
            callArguments.append(label == "_" ? value : "\(label): \(value)")
        }
        if let missing = pathParameterNames.first(where: { !boundPathParameterNames.contains($0) }) {
            throw MacroError("Path parameter ':\(missing)' has no matching function parameter named '\(missing)'")
        }
        if body != "nil" && form != nil {
            throw MacroError("A handler takes either a JSON 'body' or a multipart 'form', not both")
        }
        let formOption = form.map { "\n        form: \($0)," } ?? ""

        let functionName = function.name.text
        let (response, binding) = responseKind(of: function.signature.returnClause?.type)
        return """
            CoreKitHummingbird.RouteRegistration(
                router: \(router),
                endpoint: CoreKitHummingbird.Endpoint(
                    method: .\(method.lowercased()),\(headOption)
                    path: \(stringLiteral(path)),
                    operationID: \(stringLiteral(Naming.snakeCase(functionName))),
                    summary: \(optionalStringLiteral(function.leadingTrivia.documentation)),
                    pathParameters: [\(pathParameters.joined(separator: ", "))],
                    query: \(query),
                    body: \(body),\(formOption)
                    security: [\(security.joined(separator: ", "))],
                    response: \(response)
                ) { request, context in
                    try await CoreKitHummingbird.RouteBinding.\(binding)(
                        \(functionName)(\(callArguments.joined(separator: ", "))), for: request, context: context)
                }
            )
            """
    }

    /// The bytes `ByteCount(stringLiteral:)` reads from `text`, or `nil` for text it can't read or a size beyond `Int`.
    private static func byteCount(_ text: String) -> Int? {
        let units: [(suffix: String, factor: Int)] = [("gb", 1 << 30), ("mb", 1 << 20), ("kb", 1 << 10), ("b", 1)]
        let lowercased = text.lowercased()
        let (number, factor) =
            units.first { lowercased.hasSuffix($0.suffix) }.map { (lowercased.dropLast($0.suffix.count), $0.factor) }
            ?? (Substring(lowercased), 1)
        guard let count = Int(number) else { return nil }
        let (bytes, overflow) = count.multipliedReportingOverflow(by: factor)
        return overflow ? nil : bytes
    }

    /// The `Endpoint.ResponseKind` and the `RouteBinding` function that turns the handler's result into a response.
    private static func responseKind(of returnType: TypeSyntax?) -> (response: String, binding: String) {
        let type = returnType?.trimmedDescription ?? "Void"
        switch type {
        case "Void", "()": return (".noContent", "noContent")
        case "Response", "Hummingbird.Response": return (".raw", "raw")
        default: return (".json(\(type).self)", "json")
        }
    }
}
