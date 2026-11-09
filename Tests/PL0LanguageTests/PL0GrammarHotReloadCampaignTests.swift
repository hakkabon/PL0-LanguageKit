import IncrementalParsing
import Testing
@testable import PL0Language

@Suite("PL/0 grammar hot-reload campaign")
struct PL0GrammarHotReloadCampaignTests {
    @Test func campaignActivatesValidRevisionsAndRejectsInvalidAtomically() async throws {
        let report = try await PL0GrammarHotReloadCampaign.run()
        #expect(report.id == "pl0-grammar-hot-reload-v1")
        #expect(report.observations.map(\.candidateID) == [
            "production-only", "lexical-rule", "grammar-and-source",
            "invalid-replacement",
        ])
        #expect(report.observations.map(\.activated) == [true, true, true, false])
        #expect(report.observations.dropLast().allSatisfy {
            $0.equivalentToCleanRun
        })

        let production = report.observations[0].evidence
        #expect(production.strategy == .incremental)
        #expect(production.measurements.first { $0.dimension == .tokens }?.reused ?? 0 > 0)
        #expect(production.measurements.first {
            $0.dimension == .grammarProductions
        }?.reused ?? 0 > 0)

        let lexical = report.observations[1].evidence
        #expect(lexical.strategy == .fallback)
        #expect(lexical.fallback?.code == "lexer.grammarChange")

        let rejected = try #require(report.observations.last)
        #expect(rejected.evidence.fallback?.code == "grammar.compilationRejected")
        #expect(rejected.activeFingerprint == report.observations[2].activeFingerprint)
        #expect(rejected.documentRevision == report.observations[2].documentRevision)
    }
}
