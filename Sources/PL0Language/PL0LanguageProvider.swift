import IncrementalParsing

/// Consumer-neutral provider exported by the language kit. ModEdit,
/// Grammar-REPL, and other hosts can add presentation without wrapping the
/// PL/0 parser state in an application-owned protocol.
public struct PL0Provider: LanguageProvider {
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

    public func makeSession() -> any LanguageProviderSession {
        PL0ProviderSession()
    }
}

public actor PL0ProviderSession: LanguageProviderSession {
    private let session: PL0LanguageSession
    private let artifactIdentity: IncrementalArtifactIdentity

    public init(engine: ParserEngine = .referenceLL,
                languageKit: PL0LanguageKit = .bundled) {
        session = PL0LanguageSession(engine: engine, languageKit: languageKit)
        artifactIdentity = languageKit.artifact.incrementalIdentity
    }

    public func analyze(
        _ snapshot: IncrementalParsing.SourceSnapshot,
        change: IncrementalParsing.SourceChange?
    ) async throws -> LanguageProviderAnalysis {
        if let change, change.after != snapshot {
            throw LanguageProviderError.inconsistentChange
        }
        let input = change.map(PL0Language.SourceSnapshot.init)
            ?? PL0Language.SourceSnapshot(snapshot)
        let analysis = await session.analyze(input)
        let parse = analysis.parse
        let tokens = analysis.semantics.semanticTokens.map { token in
            LanguageProviderToken(
                range: token.range.incrementalRange,
                classification: Self.classification(token.classification),
                modifiers: token.isDeclaration ? ["declaration"] : [])
        }
        let diagnostics = parse.diagnostics.map { diagnostic in
            LanguageProviderDiagnostic(
                severity: Self.severity(diagnostic.severity),
                message: diagnostic.message,
                range: diagnostic.range.incrementalRange,
                expected: diagnostic.expected.map(\.rawValue))
        }
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
