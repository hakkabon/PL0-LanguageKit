import XCTest
import IncrementalParsing
@testable import PL0Language

final class IncrementalContractBridgeTests: XCTestCase {
    func testSingleEditTransitionPreservesLegacyIncrementalHint() throws {
        let shared = IncrementalParsing.SourceSnapshot(
            text: "begin end.", revision: .init(7))
        let change = try IncrementalParsing.SourceEdit(
            baseRevision: .init(7),
            range: IncrementalParsing.SourceRange(6, 6),
            replacement: "call p; "
        ).applying(to: shared)

        let snapshot = PL0Language.SourceSnapshot(change)

        XCTAssertEqual(snapshot.version, 8)
        XCTAssertEqual(snapshot.text, "begin call p; end.")
        XCTAssertEqual(snapshot.edit?.baseVersion, 7)
        XCTAssertEqual(snapshot.edit?.replacedRange, .init(location: 6, length: 0))
    }

    func testBatchTransitionFallsBackWithoutInventingSingleEditEvidence() throws {
        let shared = IncrementalParsing.SourceSnapshot(text: "abc")
        let change = try SourceEditBatch(
            baseRevision: .init(0),
            replacements: [
                .init(range: IncrementalParsing.SourceRange(0, 1), replacement: "A"),
                .init(range: IncrementalParsing.SourceRange(1, 2), replacement: "B"),
            ]
        ).applying(to: shared)

        let snapshot = PL0Language.SourceSnapshot(change)

        XCTAssertEqual(snapshot.text, "ABc")
        XCTAssertNil(snapshot.edit)
    }

    func testReuseMetricsProjectIntoSharedOperationalEvidence() {
        let metrics = ParserReuseMetrics(
            reusedNodeCount: 3, reusedTokenCount: 4,
            parsedNodeCount: 2, incremental: true)
        let evidence = metrics.incrementalEvidence(totalTokenCount: 7)

        XCTAssertEqual(evidence.strategy, .incremental)
        XCTAssertEqual(evidence.measurements.first { $0.dimension == .tokens }?.rebuilt, 3)
        XCTAssertEqual(evidence.measurements.first { $0.dimension == .syntaxNodes }?.reused, 3)
    }

    func testPL0TokenizerConsumesSharedTransitionAndFallsBackForBatch() throws {
        var tokenizer = PL0IncrementalTokenizer()
        let first = IncrementalParsing.SourceSnapshot(
            text: "begin call p end.", revision: .init(1))
        _ = tokenizer.tokenize(first)

        let single = try IncrementalParsing.SourceEdit(
            baseRevision: .init(1),
            range: IncrementalParsing.SourceRange(13, 13),
            replacement: ";"
        ).applying(to: first)
        XCTAssertTrue(tokenizer.tokenize(
            single.after, change: single).metrics.incremental)

        let batch = try SourceEditBatch(
            baseRevision: .init(2),
            replacements: [
                .init(range: IncrementalParsing.SourceRange(0, 0), replacement: " "),
                .init(range: IncrementalParsing.SourceRange(1, 2), replacement: ""),
            ]
        ).applying(to: single.after)
        XCTAssertFalse(tokenizer.tokenize(
            batch.after, change: batch).metrics.incremental)
    }
}
