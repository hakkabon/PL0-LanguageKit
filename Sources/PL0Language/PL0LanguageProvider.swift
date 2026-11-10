import IncrementalParsing
import LanguageTooling

/// Consumer-neutral provider exported by the language kit. ModEdit,
/// Grammar-REPL, and other hosts can add presentation without wrapping the
/// PL/0 parser state in an application-owned protocol.
public struct PL0Provider: LanguageToolingProvider {
    public let descriptor = LanguageProviderDescriptor(
        id: "pl0",
        displayName: "PL/0",
        fileExtensions: ["pl0"],
        distribution: .externalLanguageKit,
        capabilities: [
            .syntaxHighlighting, .incrementalAnalysis, .diagnostics, .recovery,
            .formatting, .semantics, .compilation, .execution,
        ])

    public init() {}

    public func makeToolingSession() -> any LanguageToolingSession {
        PL0ProviderSession()
    }
}

public actor PL0ProviderSession: LanguageToolingSession {
    private let session: PL0LanguageSession
    private let artifactIdentity: IncrementalArtifactIdentity
    private let keywordSpellings: [String]
    private let documentURI: String
    private var currentText: String?
    private var currentAnalysis: PL0Analysis?

    public init(engine: ParserEngine = .referenceLL,
                languageKit: PL0LanguageKit = .bundled,
                documentURI: String = "language-document://pl0") {
        session = PL0LanguageSession(engine: engine, languageKit: languageKit)
        artifactIdentity = languageKit.artifact.incrementalIdentity
        keywordSpellings = languageKit.keywordSpellings
        self.documentURI = documentURI
    }

    public func analyze(
        _ snapshot: IncrementalParsing.SourceSnapshot,
        change: IncrementalParsing.SourceChange?
    ) async throws -> LanguageProviderAnalysis {
        if let change, change.after != snapshot {
            throw LanguageProviderError.inconsistentChange
        }
        let analysis = await session.analyze(snapshot, change: change)
        currentText = snapshot.text
        currentAnalysis = analysis
        let parse = analysis.parse
        let tokens = analysis.semantics.semanticTokens.map { token in
            LanguageProviderToken(
                range: token.range.incrementalRange,
                classification: Self.classification(token.classification),
                modifiers: token.isDeclaration ? ["declaration"] : [])
        }
        var diagnostics = parse.diagnostics.map { diagnostic in
            LanguageProviderDiagnostic(
                severity: Self.severity(diagnostic.severity),
                message: diagnostic.message,
                range: diagnostic.range.incrementalRange,
                expected: diagnostic.expected.map(\.rawValue))
        }
        diagnostics.append(contentsOf: analysis.semantics.diagnostics.map {
            LanguageProviderDiagnostic(
                severity: .error,
                message: $0.message,
                range: $0.range.incrementalRange)
        })
        return LanguageProviderAnalysis(
            languageID: "pl0",
            revision: snapshot.revision,
            artifact: artifactIdentity,
            tokens: tokens,
            diagnostics: diagnostics,
            operations: [
                .init(
                    operation: "lexing",
                    evidence: parse.metrics.incrementalLexing.incrementalEvidence),
                .init(
                    operation: "parsing",
                    evidence: Self.parserEvidence(parse)),
                .init(
                    operation: "semantics",
                    evidence: analysis.semantics.reuseMetrics.incrementalEvidence),
            ])
    }

    public func completions(
        at position: ToolingPosition
    ) async throws -> [ToolingCompletionItem] {
        let (_, analysis, offset) = try toolingContext(at: position)
        let keywords = keywordSpellings.map {
            ToolingCompletionItem(
                label: $0,
                kind: .keyword,
                detail: "PL/0 keyword",
                insertText: $0)
        }
        let symbols = analysis.semantics.toolingIndex.visibleSymbols(at: offset).map {
            ToolingCompletionItem(
                label: $0.name,
                kind: Self.completionKind($0.kind),
                detail: $0.detail ?? $0.kind.rawValue,
                insertText: $0.name)
        }
        return (keywords + symbols).toolingUniquedByID().sorted {
            $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
    }

    public func definition(
        at position: ToolingPosition
    ) async throws -> ToolingLocation? {
        let (text, analysis, offset) = try toolingContext(at: position)
        guard let symbol = analysis.semantics.toolingIndex.symbol(at: offset) else {
            return nil
        }
        return ToolingLocation(
            uri: documentURI,
            range: SourceLineMap(text).toolingRange(symbol.declarationRange))
    }

    public func hover(at position: ToolingPosition) async throws -> ToolingHover? {
        let (text, analysis, offset) = try toolingContext(at: position)
        guard let symbol = analysis.semantics.toolingIndex.symbol(at: offset) else {
            return nil
        }
        return ToolingHover(
            contents: symbol.detail ?? "\(symbol.kind.rawValue) \(symbol.name)",
            range: SourceLineMap(text).toolingRange(symbol.declarationRange))
    }

    public func references(
        at position: ToolingPosition
    ) async throws -> [ToolingLocation] {
        let (text, analysis, offset) = try toolingContext(at: position)
        let index = analysis.semantics.toolingIndex
        guard let symbol = index.symbol(at: offset) else { return [] }
        let map = SourceLineMap(text)
        return index.references(to: symbol.id).map {
            ToolingLocation(uri: documentURI, range: map.toolingRange($0))
        }
    }

    public func semanticTokens() async throws -> ToolingSemanticTokensResult {
        guard let text = currentText, let analysis = currentAnalysis else {
            throw LanguageToolingError.documentNotAnalyzed
        }
        let map = SourceLineMap(text)
        let tokens = analysis.semantics.semanticTokens.compactMap { token in
            Self.semanticTokenType(token.classification).map {
                ToolingSemanticToken(
                    range: map.toolingRange(token.range.incrementalRange),
                    type: $0,
                    isDeclaration: token.isDeclaration)
            }
        }
        return SemanticTokenEncoder.encode(
            tokens,
            resultID: "pl0:\(analysis.semantics.version):"
                + analysis.semantics.grammarFingerprint)
    }

    public func format(_ snapshot: IncrementalParsing.SourceSnapshot) async throws
        -> String {
        try await session.format(PL0Language.SourceSnapshot(snapshot))
    }

    private static func parserEvidence(_ parse: ParseResult)
        -> IncrementalExecutionEvidence {
        switch parse.algorithmArtifact {
        case .lr(let artifact): artifact.incrementalEvidence
        case .earley(let artifact): artifact.incrementalEvidence
        case nil:
            parse.metrics.incrementalParsing.incrementalEvidence(
                totalTokenCount: max(0, parse.tokens.count - 1))
        }
    }

    private func toolingContext(
        at position: ToolingPosition
    ) throws -> (String, PL0Analysis, Int) {
        guard let text = currentText, let analysis = currentAnalysis else {
            throw LanguageToolingError.documentNotAnalyzed
        }
        guard let offset = SourceLineMap(text).offset(of: position) else {
            throw LanguageToolingError.invalidPosition(position)
        }
        return (text, analysis, offset)
    }

    private static func completionKind(
        _ kind: ToolingSymbolKind
    ) -> ToolingCompletionKind {
        if kind == .constant { return .constant }
        if kind == .function { return .function }
        return .variable
    }

    private static func semanticTokenType(
        _ value: PL0SemanticClassification
    ) -> ToolingSemanticTokenType? {
        switch value {
        case .keyword: .keyword
        case .number: .number
        case .operatorToken: .operatorToken
        case .symbol(.constant): .constant
        case .symbol(.variable): .variable
        case .symbol(.procedure): .function
        }
    }

    private static func classification(_ value: PL0SemanticClassification) -> String {
        switch value {
        case .keyword: "keyword"
        case .number: "number"
        case .operatorToken: "operator"
        case .symbol(let kind): "symbol.\(kind.rawValue)"
        }
    }

    private static func severity(_ value: PL0Language.DiagnosticSeverity)
        -> IncrementalParsing.DiagnosticSeverity {
        switch value {
        case .error: .error
        case .warning: .warning
        case .information: .information
        }
    }
}
