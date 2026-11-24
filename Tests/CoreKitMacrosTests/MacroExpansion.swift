import CoreKitMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

/// `assertMacroExpansion` reporting through swift-testing.
func assertExpansion(
    _ source: String,
    expandedSource: String,
    diagnostics: [DiagnosticSpec] = [],
    macros: [String: MacroSpec],
    sourceLocation: SourceLocation = #_sourceLocation
) {
    assertMacroExpansion(source, expandedSource: expandedSource, diagnostics: diagnostics, macroSpecs: macros) { failure in
        Issue.record(Comment(rawValue: failure.message), sourceLocation: sourceLocation)
    }
}
