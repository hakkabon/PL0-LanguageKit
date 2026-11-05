import IncrementalParsing
import PL0FrontendConformance
import Testing

@Suite("Cross-front-end PL/0 conformance")
struct PL0FrontendConformanceTests {
    @Test func comparisonIgnoresFrontendIdentityButDetectsEvidenceChanges() {
        let observation = PL0FrontendExperimentObservation(
            caseID: "accepted-0", engineID: "reference-ll",
            grammarFingerprint: "grammar", status: "accepted",
            tokenEvidence: ["period|.|0:1|source"], diagnostics: [], recovery: [],
            syntaxFingerprint: "tree")
        let modEdit = PL0FrontendExperimentReport(frontendID: "modedit", observations: [observation])
        let repl = PL0FrontendExperimentReport(frontendID: "grammar-repl", observations: [observation])
        #expect(PL0FrontendExperimentSuite.compare([modEdit, repl]).equivalent)

        let changed = PL0FrontendExperimentObservation(
            caseID: "accepted-0", engineID: "reference-ll",
            grammarFingerprint: "grammar", status: "recovered",
            tokenEvidence: observation.tokenEvidence, diagnostics: [], recovery: [],
            syntaxFingerprint: "tree")
        let workbench = PL0FrontendExperimentReport(
            frontendID: "grammar-workbench", observations: [changed])
        let agreement = PL0FrontendExperimentSuite.compare([modEdit, workbench])
        #expect(!agreement.equivalent)
        #expect(agreement.mismatchDescriptions.count == 1)
    }

    @Test func productCampaignIsPortableEquivalentAndReleaseGated() async throws {
        let measurementProtocol = IncrementalMeasurementProtocol(
            id: "pl0-product-campaign-test",
            warmupIterations: 0,
            measurementIterations: 1)
        let environment = IncrementalMeasurementEnvironment(
            hostID: "test", operatingSystem: "test",
            architecture: "test", swiftVersion: "test")
        let first = try await PL0ProductCampaign.run(
            environment: environment,
            protocol: measurementProtocol,
            clock: { 0 })
        let second = try await PL0ProductCampaign.run(
            environment: environment,
            protocol: measurementProtocol,
            clock: { 0 })

        #expect(first.allOperationsEquivalent)
        #expect(first.evidenceFingerprint == second.evidenceFingerprint)
        #expect(first.measurementFingerprint == second.measurementFingerprint)
        #expect(Set(first.scenarios.map(\.id)) == Set(PL0ProductCampaign.scenarios.map(\.id)))
        #expect(first.summaries.first {
            $0.scenarioID == "edit.earley.disclosure"
        }?.fallbackCount == 1)

        let gate = first.evaluate(PL0ProductCampaign.releaseBudgets(
            protocol: measurementProtocol))
        #expect(gate.passed, Comment(rawValue: gate.violations.joined(separator: "\n")))

        let decoded = try IncrementalMeasurementReport.decode(first.json())
        #expect(decoded == first)
    }
}
