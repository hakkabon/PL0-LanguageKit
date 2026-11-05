import Foundation
import IncrementalParsing
import PL0Language
import Testing

@Suite("PL/0 unified language provider")
struct PL0LanguageProviderTests {
    @Test func descriptorPublishesExternalKitCapabilities() {
        let descriptor = PL0Provider().descriptor
        #expect(descriptor.id == "pl0")
        #expect(descriptor.distribution == .externalLanguageKit)
        #expect(descriptor.capabilities.contains(.incrementalAnalysis))
        #expect(descriptor.capabilities.contains(.recovery))
        #expect(descriptor.capabilities.contains(.semantics))
    }

    @Test func sessionPublishesIndependentIncrementalEvidence() async throws {
        let provider = PL0Provider()
        let session = provider.makeSession()
        let original = IncrementalParsing.SourceSnapshot(
            text: "var x; begin x := 1 end.", revision: .init(1))
        let first = try await session.analyze(original)
        let location = (original.text as NSString).range(of: "1").location
        let change = try IncrementalParsing.SourceEdit(
            baseRevision: original.revision,
            range: .init(location: location, length: 1),
            replacement: "2").applying(to: original)
        let second = try await session.analyze(change.after, change: change)

        #expect(first.languageID == "pl0")
        #expect(second.revision == change.after.revision)
        #expect(second.operations.map { $0.operation }
                == ["lexing", "parsing", "semantics"])
        #expect(second.evidence(for: "lexing")?.strategy == .incremental)
        #expect(second.evidence(for: "parsing")?.strategy == .incremental)
        #expect(second.evidence(for: "semantics")?.strategy == .incremental)
        #expect(second.tokens.contains { $0.classification == "number" })
    }

    @Test func sessionRejectsAChangeForAnotherSnapshot() async throws {
        let session = PL0Provider().makeSession()
        let original = IncrementalParsing.SourceSnapshot(text: ".", revision: .init(1))
        let change = try IncrementalParsing.SourceEdit(
            baseRevision: original.revision,
            range: .init(location: 0, length: 0), replacement: " ")
            .applying(to: original)
        let unrelated = IncrementalParsing.SourceSnapshot(
            text: "var x; .", revision: change.after.revision)

        await #expect(throws: LanguageProviderError.inconsistentChange) {
            try await session.analyze(unrelated, change: change)
        }
    }
}
