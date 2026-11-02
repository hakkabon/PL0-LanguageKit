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
}
