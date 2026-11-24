import CoreKit

struct OpenAPIDocumentError: Error, CustomStringConvertible {
    let description: String
}

extension OpenAPIDocument {
    /// The OpenAPI 3.1 document. Named schemas go to `components/schemas`.
    func json() throws -> JSONValue {
        var renderer = SchemaRenderer(mode: .components)
        var paths: [(path: String, operations: [(key: String, value: JSONValue)])] = []
        var routes: Set<String> = []
        var tags: [String] = []
        var securitySchemes: [(key: String, value: JSONValue)] = []

        for endpoint in endpoints {
            let route = "\(endpoint.method.rawValue.uppercased()) \(endpoint.path.replacing(/:\w+/, with: ":"))"
            guard routes.insert(route).inserted else {
                throw OpenAPIDocumentError(description: "Duplicate route \(route)")
            }
            let operation = (key: endpoint.method.rawValue, value: try operationJSON(endpoint, renderer: &renderer))
            let path = endpoint.path.replacing(/:(\w+)/) { "{\($0.1)}" }
            if let index = paths.firstIndex(where: { $0.path == path }) {
                paths[index].operations.append(operation)
            } else {
                paths.append((path, [operation]))
            }
            if let tag = endpoint.tag?.name, !tags.contains(tag) { tags.append(tag) }
            for scheme in endpoint.securitySchemes where !securitySchemes.contains(where: { $0.key == scheme.name }) {
                securitySchemes.append((scheme.name, scheme.definition))
            }
        }
        if let name = renderer.conflictingNames.sorted().first {
            throw OpenAPIDocumentError(description: "Different types share the schema name '\(name)'")
        }

        var components: [(key: String, value: JSONValue)] = []
        if !renderer.components.isEmpty {
            components.append(("schemas", .object(renderer.components.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })))
        }
        if !securitySchemes.isEmpty { components.append(("securitySchemes", .object(securitySchemes))) }
        return [
            "openapi": "3.1.0",
            "info": ["title": .string(title), "version": .string(version)],
            "tags": .array(tags.map { ["name": .string($0)] }),
            "paths": .object(paths.map { ($0.path, .object($0.operations)) }),
            "components": .object(components),
        ]
    }

    private func operationJSON(_ endpoint: Endpoint, renderer: inout SchemaRenderer) throws -> JSONValue {
        var operation: [(key: String, value: JSONValue)] = []
        if let tag = endpoint.tag { operation.append(("tags", [.string(tag.name)])) }
        if let summary = endpoint.summary { operation.append(("summary", .string(summary))) }
        operation.append(("operationId", .string(endpoint.operationID)))

        var parameters: [JSONValue] = endpoint.pathParameters.map { parameter in
            ["name": .string(parameter.name), "in": "path", "required": true, "schema": renderer.render(parameter.schema)]
        }
        if let querySchema = endpoint.querySchema {
            guard case .object(_, _, let properties) = querySchema else {
                throw OpenAPIDocumentError(description: "The query of \(endpoint.operationID) must be a @Schema struct")
            }
            parameters += properties.map { property in
                // An optional query parameter is simply absent, so document the non-null schema.
                let schema = if case .nullable(let wrapped) = property.schema { wrapped } else { property.schema }
                var members: [(key: String, value: JSONValue)] = [
                    ("name", .string(property.key)), ("in", "query"), ("required", .bool(property.isRequired)),
                ]
                if let description = property.description { members.append(("description", .string(description))) }
                members.append(("schema", renderer.render(schema)))
                return .object(members)
            }
        }
        if !parameters.isEmpty { operation.append(("parameters", .array(parameters))) }

        if let requestBody = endpoint.requestBody {
            let content: JSONValue = [requestBody.contentType: ["schema": renderer.render(requestBody.schema)]]
            operation.append(("requestBody", ["required": true, "content": content]))
        }

        var responses: [(key: String, value: JSONValue)] = []
        if let responseSchema = endpoint.responseSchema {
            responses.append(("200", ["description": "Successful Response", "content": jsonContent(renderer.render(responseSchema))]))
        } else {
            responses.append(
                (String(endpoint.responseStatus), ["description": endpoint.responseStatus == 204 ? "No Content" : "Successful Response"]))
        }
        if let errorSchema {
            responses.append(("default", ["description": "Error", "content": jsonContent(renderer.render(errorSchema))]))
        }
        operation.append(("responses", .object(responses)))

        if !endpoint.securitySchemes.isEmpty {
            operation.append(("security", [.object(endpoint.securitySchemes.map { ($0.name, []) })]))
        }
        return .object(operation)
    }

    private func jsonContent(_ schema: JSONValue) -> JSONValue {
        ["application/json": ["schema": schema]]
    }
}
