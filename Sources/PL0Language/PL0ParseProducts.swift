import IncrementalParsing
import LanguageExperimentProtocol
import Parser

// PL/0 specializes the parser platform's language-neutral products. These
// aliases deliberately preserve the kit's public spelling while ownership and
// implementation remain in Incremental-Parsing and Parser.
public typealias SourceSnapshot = IncrementalInputSnapshot
public typealias SourceEdit = IncrementalInputEdit
public typealias SourceRange = IncrementalParsing.SourceRange
public typealias SourceLocation = SourcePosition

public typealias SyntaxOrigin = LanguageSyntaxOrigin
public typealias SyntaxNode = LanguageSyntaxNode<String>
public typealias CSTTerminalDisposition = ConcreteTerminalDisposition
public typealias CSTTerminal = ConcreteSyntaxTerminal<PL0TokenKind, String>
public typealias ConcreteSyntaxTree =
    LanguageConcreteSyntaxTree<String, PL0TokenKind, String>

public typealias DiagnosticSeverity = IncrementalParsing.DiagnosticSeverity
public typealias ParseDiagnostic = LanguageParseDiagnostic<PL0TokenKind>
public typealias RecoveryAction =
    LanguageRecoveryAction<PL0TokenKind, PL0Token>
public typealias RecoveryEvent =
    LanguageRecoveryEvent<PL0TokenKind, PL0Token>
public typealias RecoveryModel =
    LanguageRecoveryModel<PL0TokenKind, PL0Token>

public typealias ParserCapabilities = LanguageParserCapabilities
public typealias ParserDescriptor = LanguageParserDescriptor
public typealias ParseExpectation = LanguageParseExpectation<PL0TokenKind>
public typealias ParserReuseMetrics = LanguageParserReuseMetrics
public typealias ParserInput =
    LanguageParserInput<PL0Token, ParseDiagnostic>
public typealias ParserOutput =
    LanguageParserOutput<ConcreteSyntaxTree, ParseDiagnostic, RecoveryModel>

public protocol PL0ParserProtocol: LanguageParserProtocol
where Input == ParserInput, Output == ParserOutput {}

extension PL0Token: ConcreteSyntaxToken {
    public var concreteIdentity: String { id }
    public var concreteKind: PL0TokenKind { kind }
    public var concreteLexeme: String { lexeme }
    public var concreteRange: SourceRange { range }
    public var concretePosition: SourcePosition { location }
    public var isEndOfInput: Bool { kind == .endOfFile }
}

public extension ConcreteSyntaxTree {
    init(root: SyntaxNode, sourceTokens: [PL0Token],
         recoveryActions: [RecoveryAction] = []) {
        let deletedIDs = Set(recoveryActions.compactMap { action -> String? in
            if case let .delete(token) = action { return token.id }
            return nil
        })
        var positioned = sourceTokens
            .filter { !$0.isEndOfInput }
            .enumerated()
            .map { index, token in
                (
                    CSTTerminal(
                        id: token.id, kind: token.kind, lexeme: token.lexeme,
                        range: token.range, position: token.location,
                        disposition: deletedIDs.contains(token.id)
                            ? .skipped : .source),
                    index * 2 + 1
                )
            }
        for (index, action) in recoveryActions.enumerated() {
            guard case let .insert(kind, offset) = action else { continue }
            let position = Self.insertionPosition(at: offset, tokens: sourceTokens)
            positioned.append((
                CSTTerminal(
                    id: "missing:\(index):\(kind.rawValue):\(offset)",
                    kind: kind, lexeme: "",
                    range: SourceRange(location: offset, length: 0),
                    position: position, disposition: .missing),
                index * 2
            ))
        }
        self.init(
            root: root,
            terminals: positioned.sorted { lhs, rhs in
                if lhs.0.range.location != rhs.0.range.location {
                    return lhs.0.range.location < rhs.0.range.location
                }
                if lhs.0.disposition != rhs.0.disposition {
                    return lhs.0.disposition == .missing
                }
                return lhs.1 < rhs.1
            }.map(\.0))
    }

    func outline() -> String {
        let terminalLines = terminals.map { terminal in
            let marker = switch terminal.disposition {
            case .source: ""
            case .missing: " [missing]"
            case .skipped: " [skipped]"
            }
            let spelling = terminal.lexeme.isEmpty
                ? terminal.kind.displayName
                : "\"\(terminal.lexeme.replacingOccurrences(of: "\n", with: "\\n"))\""
            return "  \(terminal.kind.rawValue) \(spelling) @\(terminal.range.location)..<\(terminal.range.end)\(marker)"
        }
        return ([root.outline(), "Terminals"] + terminalLines)
            .joined(separator: "\n")
    }

    private static func insertionPosition(
        at offset: Int, tokens: [PL0Token]
    ) -> SourcePosition {
        if let following = tokens.first(where: { $0.range.location >= offset }) {
            return SourcePosition(offset: offset, line: following.location.line,
                                  column: following.location.column)
        }
        guard let last = tokens.last else {
            return SourcePosition(offset: offset, line: 1, column: 1)
        }
        return SourcePosition(offset: offset, line: last.location.line,
                              column: last.location.column)
    }
}

public extension RecoveryAction {
    var summary: String {
        switch self {
        case let .insert(kind, offset):
            "insert \(kind.displayName) at \(offset)"
        case let .delete(token):
            "delete '\(token.lexeme)' at \(token.range.location)"
        }
    }

    var range: SourceRange {
        switch self {
        case let .insert(_, offset):
            SourceRange(location: offset, length: 0)
        case let .delete(token):
            token.range
        }
    }

    var cost: Int { 1 }
}

public extension RecoveryModel {
    init(actions: [RecoveryAction], expectations: [ParseExpectation],
         diagnostics: [ParseDiagnostic]) {
        self.init(
            events: actions.enumerated().map { sequence, action in
                let offset = action.range.location
                var expected = expectations
                    .filter { $0.offset == offset }
                    .flatMap(\.kinds)
                if case let .insert(kind, _) = action,
                   !expected.contains(kind) {
                    expected.append(kind)
                }
                return RecoveryEvent(
                    id: "\(sequence):\(offset):\(action.summary)",
                    sequence: sequence, action: action, expected: expected,
                    diagnosticIDs: diagnostics.filter {
                        $0.range.location == offset
                    }.map(\.id),
                    cost: action.cost)
            },
            expectations: expectations)
    }
}

public extension ParserOutput {
    var root: SyntaxNode { syntaxTree.root }
    var recoveryActions: [RecoveryAction] { recovery.actions }
    var expectations: [ParseExpectation] { recovery.expectations }
}

public struct PL0ParseMetrics: Sendable, Equatable {
    public let sourceLength: Int
    public let tokenCount: Int
    public let lexingNanoseconds: UInt64
    public let parsingNanoseconds: UInt64
    public let recoveryCount: Int
    public let incrementalLexing: IncrementalLexMetrics
    public let incrementalParsing: ParserReuseMetrics

    public init(sourceLength: Int, tokenCount: Int, lexingNanoseconds: UInt64,
                parsingNanoseconds: UInt64, recoveryCount: Int,
                incrementalLexing: IncrementalLexMetrics,
                incrementalParsing: ParserReuseMetrics) {
        self.sourceLength = sourceLength
        self.tokenCount = tokenCount
        self.lexingNanoseconds = lexingNanoseconds
        self.parsingNanoseconds = parsingNanoseconds
        self.recoveryCount = recoveryCount
        self.incrementalLexing = incrementalLexing
        self.incrementalParsing = incrementalParsing
    }
}

public typealias ParseMetrics = PL0ParseMetrics

/// PL/0's aggregate result contains language-specific token and grammar
/// artifacts while its syntax, diagnostics, recovery and reuse values are
/// specializations of shared parser products.
public struct PL0ParseResult: Sendable, Equatable {
    public let version: UInt64
    public let parser: ParserDescriptor
    public let grammarArtifact: GrammarArtifactIdentity
    public let tokens: [PL0Token]
    public let losslessTokens: [PL0LosslessToken]
    public let syntaxTree: ConcreteSyntaxTree
    public let diagnostics: [ParseDiagnostic]
    public let recovery: RecoveryModel
    public let metrics: ParseMetrics
    public let algorithmArtifact: ParserAlgorithmArtifact?

    public var root: SyntaxNode { syntaxTree.root }
    public var recoveryActions: [RecoveryAction] { recovery.actions }
    public var expectations: [ParseExpectation] { recovery.expectations }

    public init(
        version: UInt64, parser: ParserDescriptor,
        grammarArtifact: GrammarArtifactIdentity =
            PL0LanguageKit.bundled.artifact.grammarIdentity,
        tokens: [PL0Token], losslessTokens: [PL0LosslessToken] = [],
        syntaxTree: ConcreteSyntaxTree, diagnostics: [ParseDiagnostic],
        recovery: RecoveryModel, metrics: ParseMetrics,
        algorithmArtifact: ParserAlgorithmArtifact? = nil
    ) {
        self.version = version
        self.parser = parser
        self.grammarArtifact = grammarArtifact
        self.tokens = tokens
        self.losslessTokens = losslessTokens
        self.syntaxTree = syntaxTree
        self.diagnostics = diagnostics
        self.recovery = recovery
        self.metrics = metrics
        self.algorithmArtifact = algorithmArtifact
    }
}

public typealias ParseResult = PL0ParseResult
