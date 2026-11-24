import SwiftSyntax

extension AttributeSyntax {
    /// The attribute's name without a module qualifier: `Range` for `@CoreKit.Range(1...)`.
    var name: String {
        attributeName.trimmedDescription.split(separator: ".").last.map(String.init) ?? ""
    }
}
