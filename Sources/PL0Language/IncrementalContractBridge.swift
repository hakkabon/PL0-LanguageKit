import IncrementalParsing
import LanguageExperimentProtocol

extension SourceRange {
    public init(_ range: IncrementalParsing.SourceRange) {
        self.init(location: range.location, length: range.length)
    }

    public var incrementalRange: IncrementalParsing.SourceRange {
        .init(location: location, length: length)
    }
}

extension SourceSnapshot {
    /// Builds the PL/0 compatibility snapshot used by existing clients. A
    /// multi-edit transition deliberately omits the legacy single-edit hint,
    /// causing the tokenizer to take its safe full-scan path.
    public init(_ snapshot: IncrementalParsing.SourceSnapshot) {
        self.init(version: snapshot.revision.rawValue, text: snapshot.text)
    }

    public init(_ change: IncrementalParsing.SourceChange) {
        let edit: SourceEdit?
        if change.replacements.count == 1, let replacement = change.replacements.first {
            edit = .init(
                baseVersion: change.before.revision.rawValue,
                replacedRange: .init(replacement.range),
                replacementLength: replacement.replacementUTF16Count)
        } else {
            edit = nil
        }
        self.init(
            version: change.after.revision.rawValue,
            text: change.after.text,
            edit: edit)
    }

    public var incrementalSnapshot: IncrementalParsing.SourceSnapshot {
        .init(text: text, revision: .init(version))
    }
}

extension PL0GrammarArtifact {
    public var incrementalIdentity: IncrementalParsing.IncrementalArtifactIdentity {
        .init(id: artifactID, revision: revision, fingerprint: fingerprint)
    }
}

extension ParserReuseMetrics {
    public func incrementalEvidence(totalTokenCount: Int)
        -> IncrementalParsing.IncrementalExecutionEvidence {
        precondition(totalTokenCount >= reusedTokenCount)
        return .init(
            strategy: incremental ? .incremental : .full,
            measurements: [
                .init(
                    dimension: .tokens,
                    reused: reusedTokenCount,
                    rebuilt: totalTokenCount - reusedTokenCount),
                .init(
                    dimension: .syntaxNodes,
                    reused: reusedNodeCount,
                    rebuilt: parsedNodeCount),
            ])
    }
}

extension IncrementalLexMetrics {
    /// Product-level evidence for the restart-and-converge tokenizer. Prefix
    /// and suffix reuse are two regions of the same token dimension and can be
    /// added without mixing unlike units.
    public var incrementalEvidence: IncrementalParsing.IncrementalExecutionEvidence {
        .init(
            strategy: incremental ? .incremental : .full,
            measurements: [
                .init(
                    dimension: .tokens,
                    reused: reusedPrefixTokenCount + reusedSuffixTokenCount,
                    rebuilt: generatedTokenCount,
                    strategy: incremental
                        ? "restart-and-converge" : "full-tokenization"),
            ])
    }
}

extension PL0SemanticReuseMetrics {
    /// Semantic bindings are kept separate from syntax and parser-state reuse.
    public var incrementalEvidence: IncrementalParsing.IncrementalExecutionEvidence {
        .init(
            strategy: incremental ? .incremental : .full,
            measurements: [
                .init(
                    dimension: .semanticNodes,
                    reused: reusedSymbolCount + reusedReferenceCount,
                    rebuilt: rebuiltSymbolCount + rebuiltReferenceCount,
                    removed: dependencyInvalidationCount,
                    strategy: incremental
                        ? "stable-binding-dependency-cache"
                        : "full-semantic-analysis"),
            ])
    }
}

extension IncrementalParsing.IncrementalExecutionEvidence {
    /// Projects shared operational evidence into the versioned experiment
    /// envelope without merging independent reuse dimensions.
    public func experimentReuseEvidence(baseRevision: UInt64?) throws
        -> ReuseEvidence {
        let values = try measurements.map { measurement in
            try LanguageExperimentProtocol.reuseMeasurement(
                dimension: measurement.dimension.rawValue,
                reused: measurement.reused,
                rebuilt: measurement.rebuilt,
                invalidated: measurement.removed,
                strategy: measurement.strategy ?? strategy.rawValue)
        }
        return try LanguageExperimentProtocol.reuseEvidence(
            incremental: baseRevision != nil,
            baseRevision: baseRevision,
            measurements: values)
    }
}
