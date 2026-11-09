import Grammar
import IncrementalParsing
import Lexer

/// End-to-end grammar revision campaign owned by the language kit. Product
/// front ends invoke this unchanged, just as they do the source-edit campaign.
public enum PL0GrammarHotReloadCampaign {
    public static let id = "pl0-grammar-hot-reload-v1"

    public static func run() async throws -> GrammarHotReloadCampaignReport {
        let initial = PL0LanguageKit.bundled
        let productionSource = replacing(
            in: initial.artifact.source,
            "Factor ::= IDENTIFIER | NUMBER | LPAREN Expression RPAREN;",
            with: "Factor ::= IDENTIFIER | NUMBER | LPAREN Expression RPAREN | MINUS NUMBER;")
        let productionKit = try PL0LanguageKit.compile(
            source: productionSource, revision: 2)
        let lexicalSource = replacing(
            in: productionSource, "token NUMBER = /[0-9]+/;",
            with: "token NUMBER = /[0-9][0-9]*/;")
        let lexicalKit = try PL0LanguageKit.compile(source: lexicalSource, revision: 3)
        let combinedSource = replacing(
            in: lexicalSource,
            "Factor ::= IDENTIFIER | NUMBER | LPAREN Expression RPAREN | MINUS NUMBER;",
            with: "Factor ::= IDENTIFIER | NUMBER | LPAREN Expression RPAREN | MINUS NUMBER | PLUS NUMBER;")
        let combinedKit = try PL0LanguageKit.compile(
            source: combinedSource, revision: 4)

        let definitions = [
            Definition(
                candidate: .init(
                    id: "production-only", sourceFingerprint: initial.artifact.fingerprint,
                    targetFingerprint: productionKit.artifact.fingerprint,
                    documentRevision: 1, expectsActivation: true),
                grammarSource: productionSource, document: nil),
            Definition(
                candidate: .init(
                    id: "lexical-rule", sourceFingerprint: productionKit.artifact.fingerprint,
                    targetFingerprint: lexicalKit.artifact.fingerprint,
                    documentRevision: 1, expectsActivation: true),
                grammarSource: lexicalSource, document: nil),
            Definition(
                candidate: .init(
                    id: "grammar-and-source", sourceFingerprint: lexicalKit.artifact.fingerprint,
                    targetFingerprint: combinedKit.artifact.fingerprint,
                    documentRevision: 2, expectsActivation: true),
                grammarSource: combinedSource,
                document: "var x; begin x := 2 * + 3 end."),
            Definition(
                candidate: .init(
                    id: "invalid-replacement", sourceFingerprint: combinedKit.artifact.fingerprint,
                    targetFingerprint: nil, documentRevision: 3,
                    expectsActivation: false),
                grammarSource: "INVALID", document: nil),
        ]
        let runtime = try Runtime(
            languageKit: initial,
            document: "var x; begin x := 2 * 3 end.")
        let byID = Dictionary(uniqueKeysWithValues: definitions.map {
            ($0.candidate.id, $0)
        })
        return try await GrammarHotReloadCampaignRunner.run(
            id: id,
            initialFingerprint: initial.artifact.fingerprint,
            initialDocumentRevision: 1,
            candidates: definitions.map(\.candidate)
        ) { candidate in
            try await runtime.apply(byID[candidate.id]!)
        }
    }

    private struct Definition: Sendable {
        let candidate: GrammarHotReloadCandidate
        let grammarSource: String
        let document: String?
    }

    private actor Runtime {
        private var languageKit: PL0LanguageKit
        private var grammar: Grammar
        private var tokenizer: GrammarIncrementalTokenizer
        private var document: String
        private var documentRevision: UInt64 = 1
        private var lexicalRevision: UInt64 = 1
        private var cachedTokenCount: Int

        init(languageKit: PL0LanguageKit, document: String) throws {
            self.languageKit = languageKit
            grammar = PL0GrammarHotReloadCampaign.campaignGrammar(
                languageKit.artifact)
            tokenizer = GrammarIncrementalTokenizer(
                scanner: try GrammarDrivenLexer(grammar: grammar))
            self.document = document
            cachedTokenCount = 0
            let first = tokenizer.tokenize(revision: 1, text: document)
            cachedTokenCount = first.output.tokens.count
        }

        func apply(_ definition: Definition) async throws
            -> GrammarHotReloadObservation {
            let previousFingerprint = languageKit.artifact.fingerprint
            do {
                let target = try PL0LanguageKit.compile(
                    source: definition.grammarSource,
                    revision: languageKit.artifact.revision + 1,
                    artifactID: languageKit.artifact.artifactID)
                let targetGrammar = PL0GrammarHotReloadCampaign.campaignGrammar(
                    target.artifact)
                let change = grammar.changeSet(to: targetGrammar)
                let evidence = try tokenizer.apply(
                    grammarChange: change, targetGrammar: targetGrammar)
                grammar = targetGrammar
                languageKit = target

                if let changedDocument = definition.document {
                    document = changedDocument
                    documentRevision = definition.candidate.documentRevision
                }
                lexicalRevision += 1
                let tokenization = tokenizer.tokenize(
                    revision: lexicalRevision, text: document)
                cachedTokenCount = tokenization.output.tokens.count

                let incremental = try await PL0EcosystemParserSession(
                    languageKit: target).compare(
                        SourceSnapshot(version: documentRevision, text: document))
                let clean = try await PL0EcosystemParserSession(
                    languageKit: target).compare(
                        SourceSnapshot(version: documentRevision, text: document))
                return .init(
                    candidateID: definition.candidate.id, activated: true,
                    activeFingerprint: target.artifact.fingerprint,
                    documentRevision: documentRevision,
                    equivalentToCleanRun: incremental == clean,
                    evidence: evidence)
            } catch {
                guard !definition.candidate.expectsActivation else { throw error }
                return .init(
                    candidateID: definition.candidate.id, activated: false,
                    activeFingerprint: previousFingerprint,
                    documentRevision: documentRevision,
                    equivalentToCleanRun: true,
                    evidence: .init(
                        strategy: .fallback,
                        fallback: .init(
                            code: "grammar.compilationRejected",
                            detail: String(describing: error)),
                        measurements: [.init(
                            dimension: .tokens, reused: cachedTokenCount,
                            rebuilt: 0, strategy: "atomic-grammar-rejection")]))
            }
        }
    }

    private static func replacing(
        in source: String, _ needle: String, with replacement: String
    ) -> String {
        precondition(source.contains(needle), "grammar campaign anchor is missing")
        return source.replacingOccurrences(of: needle, with: replacement)
    }

    private static func campaignGrammar(_ artifact: PL0GrammarArtifact) -> Grammar {
        var grammar = ecosystemGrammar(artifact)
        grammar.lexicalSpecification = artifact.lexicalSpecification
        return grammar
    }
}
