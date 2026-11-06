import Foundation
import IncrementalParsing
import Lexer

public typealias IncrementalLexMetrics = RestartAndConvergeMetrics

public struct IncrementalLexResult: Sendable {
    public let version: UInt64
    public let lexed: LexResult
    public let metrics: IncrementalLexMetrics
}

/// Thin typed projection over Lexer's grammar-driven incremental tokenizer.
/// PL/0 owns no scanner rules and no restart/convergence conformances.
public struct PL0IncrementalTokenizer: Sendable {
    private var tokenizer: GrammarIncrementalTokenizer

    public init(languageKit: PL0LanguageKit = .bundled) {
        do {
            tokenizer = RestartAndConvergeTokenizer(
                scanner: try GrammarDrivenLexer(
                    specification: languageKit.artifact.lexicalSpecification))
        } catch {
            preconditionFailure("Invalid compiled PL/0 lexical artifact: \(error)")
        }
    }

    public mutating func tokenize(_ snapshot: SourceSnapshot) -> IncrementalLexResult {
        let edit = snapshot.edit.map {
            IncrementalLexerEdit(
                baseRevision: $0.baseVersion,
                replacedRange: $0.replacedRange.location..<$0.replacedRange.end,
                replacementLength: $0.replacementLength)
        }
        return project(tokenizer.tokenize(
            revision: snapshot.version, text: snapshot.text, edit: edit))
    }

    public mutating func tokenize(
        _ snapshot: IncrementalParsing.SourceSnapshot,
        change: IncrementalParsing.SourceChange? = nil
    ) -> IncrementalLexResult {
        project(tokenizer.tokenize(snapshot: snapshot, change: change))
    }

    public mutating func reset() { tokenizer.reset() }

    private func project(
        _ result: RestartAndConvergeResult<GrammarLexicalToken,
                                          GrammarLexicalElement,
                                          GrammarLexicalDiagnostic>
    ) -> IncrementalLexResult {
        IncrementalLexResult(
            version: result.revision,
            lexed: LexResult(
                tokens: result.output.tokens.map(mapToken),
                losslessTokens: result.output.elements.compactMap(mapElement),
                diagnostics: result.output.diagnostics.map(mapDiagnostic)),
            metrics: result.metrics)
    }
}
