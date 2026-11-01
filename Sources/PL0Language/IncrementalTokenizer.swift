import Foundation
import Lexer

public typealias IncrementalLexMetrics = RestartAndConvergeMetrics

public struct IncrementalLexResult: Sendable {
    public let version: UInt64
    public let lexed: LexResult
    public let metrics: IncrementalLexMetrics
}

/// PL/0 adapter over Lexer's language-neutral restart-and-converge engine.
public struct PL0IncrementalTokenizer: Sendable {
    private var tokenizer: RestartAndConvergeTokenizer<PL0RestartableScanner>

    public init(languageKit: PL0LanguageKit = .bundled) {
        tokenizer = RestartAndConvergeTokenizer(
            scanner: PL0RestartableScanner(languageKit: languageKit))
    }

    public mutating func tokenize(_ snapshot: SourceSnapshot) -> IncrementalLexResult {
        let edit = snapshot.edit.map {
            IncrementalLexerEdit(
                baseRevision: $0.baseVersion,
                replacedRange: $0.replacedRange.location..<$0.replacedRange.end,
                replacementLength: $0.replacementLength)
        }
        let result = tokenizer.tokenize(
            revision: snapshot.version, text: snapshot.text, edit: edit)
        return IncrementalLexResult(
            version: result.revision,
            lexed: LexResult(
                tokens: result.output.tokens,
                losslessTokens: result.output.elements,
                diagnostics: result.output.diagnostics),
            metrics: result.metrics)
    }

    public mutating func reset() { tokenizer.reset() }
}

private struct PL0RestartableScanner: RestartableLexer {
    let languageKit: PL0LanguageKit

    func scan(text: String, from position: LexicalPosition, revision: UInt64,
              shouldStopBefore: ((PL0Token) -> Bool)?)
        -> RestartableLexicalScan<PL0Token, PL0LosslessToken, ParseDiagnostic> {
        let output = PL0Lexer(languageKit: languageKit).scan(
            text as NSString,
            from: SourceLocation(
                offset: position.offset, line: position.line, column: position.column),
            version: revision,
            shouldConverge: shouldStopBefore)
        return RestartableLexicalScan(
            tokens: output.tokens,
            elements: output.losslessTokens,
            diagnostics: output.diagnostics,
            scannedEnd: output.scannedEnd,
            stoppedForConvergence: output.stoppedForConvergence)
    }
}

extension PL0Token: IncrementalLexicalToken {
    public var incrementalID: String { id }
    public var incrementalKind: PL0TokenKind { kind }
    public var incrementalLexeme: String { lexeme }
    public var incrementalRange: Range<Int> { range.location..<range.end }
    public var incrementalPosition: LexicalPosition {
        LexicalPosition(offset: location.offset, line: location.line,
                        column: location.column)
    }
    public var incrementalEndPosition: LexicalPosition {
        LexicalPosition(offset: range.end, line: location.line,
                        column: location.column + range.length)
    }
    public var incrementalIsEndOfInput: Bool { kind == .endOfFile }

    public func relocated(by delta: Int, from oldAnchor: PL0Token,
                          to newAnchor: PL0Token) -> PL0Token {
        let line: Int
        let column: Int
        if location.line == oldAnchor.location.line {
            line = newAnchor.location.line
            column = newAnchor.location.column
                + location.column - oldAnchor.location.column
        } else {
            line = newAnchor.location.line + location.line - oldAnchor.location.line
            column = location.column
        }
        let offset = range.location + delta
        return PL0Token(
            id: id, kind: kind, lexeme: lexeme,
            range: SourceRange(location: offset, length: range.length),
            location: SourceLocation(offset: offset, line: line, column: column))
    }
}

extension PL0LosslessToken: IncrementalLexicalElement {
    public var incrementalID: String { id }
    public var incrementalTokenID: String? {
        if case .token = kind { id } else { nil }
    }
    public var incrementalRange: Range<Int> { range.location..<range.end }

    public func relocated(by delta: Int,
                          from oldAnchor: LexicalPosition,
                          to newAnchor: LexicalPosition) -> PL0LosslessToken {
        let line: Int
        let column: Int
        if location.line == oldAnchor.line {
            line = newAnchor.line
            column = newAnchor.column + location.column - oldAnchor.column
        } else {
            line = newAnchor.line + location.line - oldAnchor.line
            column = location.column
        }
        let offset = range.location + delta
        return PL0LosslessToken(
            id: id, kind: kind, lexeme: lexeme,
            range: SourceRange(location: offset, length: range.length),
            location: SourceLocation(offset: offset, line: line, column: column))
    }
}

extension ParseDiagnostic: IncrementalLexicalDiagnostic {
    public var incrementalRange: Range<Int> { range.location..<range.end }

    public func relocated(by delta: Int) -> ParseDiagnostic {
        ParseDiagnostic(
            severity: severity, message: message,
            range: SourceRange(location: range.location + delta, length: range.length),
            expected: expected)
    }
}
