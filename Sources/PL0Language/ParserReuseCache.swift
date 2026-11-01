import LL_Parsing

enum ReferenceParserRule: String, Sendable, Hashable {
    case block
    case statement
    case condition
    case expression
    case term
    case factor
}

typealias ReferenceParserCache = LLRegionCache<
    ReferenceParserRule,
    PL0Token,
    SyntaxNode,
    ParseDiagnostic,
    RecoveryAction,
    ParseExpectation>

typealias ReferenceParserMemoizer = LLRegionMemoizer<
    ReferenceParserRule,
    PL0Token,
    SyntaxNode,
    ParseDiagnostic,
    RecoveryAction,
    ParseExpectation>

struct ReferenceParserRun {
    let output: ParserOutput
    let cache: ReferenceParserCache
}

extension PL0Token: LLRegionToken {
    public var regionTokenID: String { id }
    public var regionSourceOffset: Int { range.location }
}

extension SyntaxNode: LLRegionRelocatable {}
extension ParseDiagnostic: LLRegionRelocatable {}

extension ParseExpectation: LLRegionRelocatable {
    public func relocated(by delta: Int) -> ParseExpectation {
        ParseExpectation(offset: offset + delta, kinds: kinds)
    }
}

extension RecoveryAction: LLRegionRecovery {
    public func relocated(by delta: Int,
                          currentTokens: [String: PL0Token]) -> RecoveryAction {
        switch self {
        case let .insert(kind, offset):
            .insert(kind: kind, at: offset + delta)
        case let .delete(token):
            .delete(token: currentTokens[token.id] ?? PL0Token(
                id: token.id, kind: token.kind, lexeme: token.lexeme,
                range: SourceRange(location: token.range.location + delta,
                                   length: token.range.length),
                location: SourceLocation(
                    offset: token.location.offset + delta,
                    line: token.location.line,
                    column: token.location.column)))
        }
    }
}
