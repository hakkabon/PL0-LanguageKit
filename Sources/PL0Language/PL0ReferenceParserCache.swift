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

extension PL0Token: LLRegionRelocatingToken {
    public var regionTokenID: String { id }
    public var regionSourceOffset: Int { range.location }

    public func relocatedRegionToken(by delta: Int) -> PL0Token {
        PL0Token(
            id: id, kind: kind, lexeme: lexeme,
            range: SourceRange(location: range.location + delta,
                               length: range.length),
            location: SourceLocation(
                offset: location.offset + delta,
                line: location.line, column: location.column))
    }
}
