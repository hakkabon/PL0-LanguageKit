import Foundation
import Lexer

struct PL0LexicalProjection: GrammarLexicalProjection {
    func token(_ token: GrammarLexicalToken) -> PL0Token { mapToken(token) }
    func element(_ element: GrammarLexicalElement) -> PL0LosslessToken? {
        mapElement(element)
    }
    func diagnostic(
        _ diagnostic: GrammarLexicalDiagnostic
    ) -> ParseDiagnostic {
        mapDiagnostic(diagnostic)
    }
}

public struct LexResult: Sendable {
    public let tokens: [PL0Token]
    public let losslessTokens: [PL0LosslessToken]
    public let diagnostics: [ParseDiagnostic]

    public init(tokens: [PL0Token], losslessTokens: [PL0LosslessToken] = [],
                diagnostics: [ParseDiagnostic]) {
        self.tokens = tokens
        self.losslessTokens = losslessTokens
        self.diagnostics = diagnostics
    }
}

struct ScannerOutput {
    var tokens: [PL0Token]
    var losslessTokens: [PL0LosslessToken]
    var diagnostics: [ParseDiagnostic]
    var scannedEnd: Int
    var stoppedForConvergence: Bool
}

/// PL/0 compatibility facade over Lexer's artifact-driven scanner. The rules,
/// trivia channels, and comment behavior all come from the bundled grammar.
public struct PL0Lexer: Sendable {
    public let languageKit: PL0LanguageKit

    public init(languageKit: PL0LanguageKit = .bundled) {
        self.languageKit = languageKit
    }

    public func tokenize(_ snapshot: SourceSnapshot) -> LexResult {
        let output = scan(
            snapshot.text as NSString,
            from: SourceLocation(offset: 0, line: 1, column: 1),
            version: snapshot.version)
        return LexResult(
            tokens: output.tokens, losslessTokens: output.losslessTokens,
            diagnostics: output.diagnostics)
    }

    func scan(_ text: NSString, from initial: SourceLocation, version: UInt64,
              shouldConverge: ((PL0Token) -> Bool)? = nil) -> ScannerOutput {
        let scanner: GrammarDrivenLexer
        do {
            scanner = try GrammarDrivenLexer(
                specification: languageKit.artifact.lexicalSpecification)
        } catch {
            preconditionFailure("Invalid compiled PL/0 lexical artifact: \(error)")
        }
        let output = scanner.scan(
            text: text as String,
            from: LexicalPosition(
                offset: initial.offset, line: initial.line, column: initial.column),
            revision: version,
            shouldStopBefore: { token in
                shouldConverge?(mapToken(token)) ?? false
            })
        return ScannerOutput(
            tokens: output.tokens.map(mapToken),
            losslessTokens: output.elements.compactMap(mapElement),
            diagnostics: output.diagnostics.map(mapDiagnostic),
            scannedEnd: output.scannedEnd,
            stoppedForConvergence: output.stoppedForConvergence)
    }
}

func mapDiagnostic(_ diagnostic: GrammarLexicalDiagnostic) -> ParseDiagnostic {
    let message = diagnostic.message == "Unterminated BLOCK_COMMENT"
        ? "Unterminated block comment" : diagnostic.message
    return ParseDiagnostic(
        severity: .error, message: message,
        range: SourceRange(
            location: diagnostic.range.lowerBound,
            length: diagnostic.range.count))
}

func mapToken(_ token: GrammarLexicalToken) -> PL0Token {
    let kind: PL0TokenKind
    if token.isEndOfInput {
        kind = .endOfFile
    } else if token.kind == "$INVALID" {
        kind = .invalid
    } else {
        guard let mapped = PL0TokenKind(grammarName: token.kind) else {
            preconditionFailure("Grammar emitted unbound PL/0 token \(token.kind)")
        }
        kind = mapped
    }
    return PL0Token(
        id: token.id, kind: kind, lexeme: token.lexeme,
        range: SourceRange(
            location: token.range.lowerBound, length: token.range.count),
        location: SourceLocation(
            offset: token.position.offset, line: token.position.line,
            column: token.position.column))
}

func mapElement(_ element: GrammarLexicalElement) -> PL0LosslessToken? {
    let kind: PL0LosslessTokenKind
    switch element.kind {
    case .token(let name):
        guard let tokenKind = PL0TokenKind(grammarName: name) else { return nil }
        kind = .token(tokenKind)
    case .trivia(let name):
        switch name {
        case "WHITESPACE": kind = .trivia(.whitespace)
        case "LINE_COMMENT": kind = .trivia(.lineComment)
        case "BLOCK_COMMENT": kind = .trivia(.blockComment)
        default: return nil
        }
    case .invalid:
        kind = .token(.invalid)
    }
    return PL0LosslessToken(
        id: element.id, kind: kind, lexeme: element.lexeme,
        range: SourceRange(
            location: element.range.lowerBound, length: element.range.count),
        location: SourceLocation(
            offset: element.position.offset, line: element.position.line,
            column: element.position.column))
}
