import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct CoreKitMacrosPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [
        SchemaMacro.self,
        PublicInitMacro.self,
        ConstraintMacro.self,
        UnionCaseMacro.self,
        RetryMacro.self,
        TimeoutMacro.self,
    ]
}

struct MacroError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
