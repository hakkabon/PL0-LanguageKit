import Foundation
import IncrementalParsing
import PL0Conformance
import PL0Language

/// The first language-kit-owned product campaign. Front ends invoke this
/// definition unchanged; they do not recreate fixtures or reinterpret reuse.
public enum PL0ProductCampaign {
    public static let campaignProtocol = IncrementalMeasurementProtocol(
        id: "pl0-product-campaign-v2",
        warmupIterations: 1,
        measurementIterations: 3)

    public static let scenarios: [IncrementalMeasurementScenario] =
        definitions.map(\.scenario)

    /// Host-independent release expectations. Timing budgets intentionally
    /// remain CI policy because timings are meaningful only on matched hosts.
    public static func releaseBudgets(
        protocol protocolValue: IncrementalMeasurementProtocol = campaignProtocol
    ) -> [IncrementalMeasurementBudget] {
        definitions.map { definition in
            var minimum: [ReuseDimension: Double] = [:]
            switch definition.target {
            case .lexer where definition.edit != nil:
                minimum[.tokens] = 0.01
            case .parser where definition.engine == .referenceLL && definition.edit != nil:
                minimum[.syntaxNodes] = 0.01
            case .parser where definition.engine == .generatedLR && definition.edit != nil:
                minimum[.parserStates] = 0.01
            case .parser where definition.engine == .earley && definition.edit != nil:
                minimum[.chartFacts] = 0.01
            case .semantic:
                minimum[.semanticNodes] = 0.01
            default:
                break
            }
            return .init(
                scenarioID: definition.scenario.id,
                requireCleanEquivalence: true,
                maximumFallbackCount: 0,
                minimumReuseRatios: minimum)
        }
    }

    public static func releaseBudgetJSON(
        protocol protocolValue: IncrementalMeasurementProtocol = campaignProtocol
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(releaseBudgets(protocol: protocolValue))
    }

    public static func run(
        environment: IncrementalMeasurementEnvironment = .pl0Current,
        protocol protocolValue: IncrementalMeasurementProtocol = campaignProtocol,
        clock: () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) async throws -> IncrementalMeasurementReport {
        let byID = Dictionary(uniqueKeysWithValues: definitions.map {
            ($0.scenario.id, $0)
        })
        return try await IncrementalMeasurementRunner.run(
            protocol: protocolValue,
            environment: environment,
            artifact: PL0LanguageKit.bundled.artifact.incrementalIdentity,
            scenarios: scenarios,
            clock: clock
        ) { scenario, _ in
            guard let definition = byID[scenario.id] else {
                throw IncrementalMeasurementError.invalidReport(
                    "unknown PL/0 campaign scenario \(scenario.id)")
            }
            let measured = try await execute(definition)
            let clean = try await cleanAnalysis(
                source: measured.source, engine: definition.engine)
            return IncrementalMeasuredOperation(
                evidence: evidence(for: measured.analysis, target: definition.target),
                equivalentToCleanRun:
                    try projection(measured.analysis, scenarioID: scenario.id)
                    == projection(clean, scenarioID: scenario.id))
        }
    }

    private enum EvidenceTarget { case lexer, parser, semantic }

    private struct Edit {
        let needle: String
        let replacement: String
    }

    private struct Definition {
        let scenario: IncrementalMeasurementScenario
        let engine: ParserEngine
        let source: String
        let edit: Edit?
        let target: EvidenceTarget
    }

    private struct Execution {
        let source: String
        let analysis: PL0Analysis
    }

    private struct Projection: Equatable {
        let status: String
        let tokens: [String]
        let diagnostics: [String]
        let recovery: [String]
        let syntaxFingerprint: String?
        let semantics: [String]
    }

    private static let definitions: [Definition] = [
        .init(
            scenario: .init(id: "accepted.lr.minimal", title: "Accepted minimal program"),
            engine: .generatedLR, source: PL0ConformanceCorpus.accepted[0],
            edit: nil, target: .parser),
        .init(
            scenario: .init(id: "accepted.lr.declarations", title: "Accepted declarations"),
            engine: .generatedLR, source: PL0ConformanceCorpus.accepted[1],
            edit: nil, target: .parser),
        .init(
            scenario: .init(id: "recovery.ll.variable", title: "Recover malformed variable declaration"),
            engine: .referenceLL, source: PL0ConformanceCorpus.rejected[0],
            edit: nil, target: .parser),
        .init(
            scenario: .init(id: "recovery.ll.expression", title: "Recover missing constant expression"),
            engine: .referenceLL, source: PL0ConformanceCorpus.rejected[3],
            edit: nil, target: .parser),
        .init(
            scenario: .init(id: "edit.lexer.expression", title: "Restart and converge after expression edit"),
            engine: .referenceLL, source: PL0ConformanceCorpus.mutationSeeds[1],
            edit: .init(needle: "x := n", replacement: "x := n + 1"),
            target: .lexer),
        .init(
            scenario: .init(id: "edit.ll.literal", title: "Reuse LL regions after literal edit"),
            engine: .referenceLL, source: PL0ConformanceCorpus.mutationSeeds[4],
            edit: .init(needle: "1", replacement: "2"), target: .parser),
        .init(
            scenario: .init(id: "edit.ll.recovery", title: "Recover after deleting then"),
            engine: .referenceLL, source: PL0ConformanceCorpus.accepted[4],
            edit: .init(needle: "then ", replacement: ""), target: .parser),
        .init(
            scenario: .init(id: "edit.lr.literal", title: "Resume native LR stack after literal edit"),
            engine: .generatedLR, source: PL0ConformanceCorpus.mutationSeeds[2],
            edit: .init(needle: "4", replacement: "40"), target: .parser),
        .init(
            scenario: .init(id: "edit.earley.chart", title: "Resume native Earley chart after literal edit"),
            engine: .earley, source: PL0ConformanceCorpus.mutationSeeds[2],
            edit: .init(needle: "4", replacement: "40"), target: .parser),
        .init(
            scenario: .init(id: "edit.semantic.constant", title: "Reuse semantic bindings after constant edit"),
            engine: .referenceLL, source: PL0ConformanceCorpus.mutationSeeds[1],
            edit: .init(needle: "3", replacement: "4"), target: .semantic),
    ]

    private static func execute(_ definition: Definition) async throws -> Execution {
        let session = PL0LanguageSession(engine: definition.engine)
        let initial = PL0Language.SourceSnapshot(version: 1, text: definition.source)
        guard let edit = definition.edit else {
            return .init(source: definition.source,
                         analysis: await session.analyze(initial))
        }
        _ = await session.analyze(initial)
        let range = (definition.source as NSString).range(of: edit.needle)
        guard range.location != NSNotFound else {
            throw IncrementalMeasurementError.invalidReport(
                "PL/0 campaign edit anchor was not found for \(definition.scenario.id)")
        }
        let changedSource = (definition.source as NSString).replacingCharacters(
            in: range, with: edit.replacement)
        let changed = PL0Language.SourceSnapshot(
            version: 2,
            text: changedSource,
            edit: .init(
                baseVersion: 1,
                replacedRange: .init(location: range.location, length: range.length),
                replacementLength: edit.replacement.utf16.count))
        return .init(source: changedSource,
                     analysis: await session.analyze(changed))
    }

    private static func cleanAnalysis(source: String, engine: ParserEngine) async throws
        -> PL0Analysis {
        let session = PL0LanguageSession(engine: engine)
        return await session.analyze(.init(version: 2, text: source))
    }

    private static func evidence(for analysis: PL0Analysis, target: EvidenceTarget)
        -> IncrementalExecutionEvidence {
        switch target {
        case .lexer:
            analysis.parse.metrics.incrementalLexing.incrementalEvidence
        case .semantic:
            analysis.semantics.reuseMetrics.incrementalEvidence
        case .parser:
            switch analysis.parse.algorithmArtifact {
            case .lr(let artifact): artifact.incrementalEvidence
            case .earley(let artifact): artifact.incrementalEvidence
            case nil:
                analysis.parse.metrics.incrementalParsing.incrementalEvidence(
                    totalTokenCount: max(0, analysis.parse.tokens.count - 1))
            }
        }
    }

    private static func projection(_ analysis: PL0Analysis, scenarioID: String) throws
        -> Projection {
        let run = try analysis.experimentRun(
            documentURI: "campaign:///\(scenarioID).pl0",
            runID: scenarioID)
        let semanticSymbols = analysis.semantics.symbols.map {
            "symbol|\($0.name.lowercased())|\($0.kind.rawValue)|\($0.declarationRange.location):\($0.declarationRange.length)|\($0.lexicalLevel)"
        }
        let symbolsByID = Dictionary(uniqueKeysWithValues:
            analysis.semantics.symbols.map { ($0.id, $0) })
        let semanticReferences = analysis.semantics.references.map {
            let symbol = symbolsByID[$0.symbolID]
            return "reference|\($0.range.location):\($0.range.length)|\(symbol?.name.lowercased() ?? "unresolved")|\(symbol?.kind.rawValue ?? "unresolved")"
        }
        return .init(
            status: run.status.rawValue,
            tokens: run.tokenSnapshot.tokens.map {
                "\($0.kind)|\($0.lexeme)|\($0.range.location):\($0.range.length)|\($0.channel.rawValue)"
            },
            diagnostics: run.diagnostics.map {
                "\($0.severity.rawValue)|\($0.range.location):\($0.range.length)|\($0.message)|\($0.expected.joined(separator: ","))"
            },
            recovery: run.recovery.edits.map {
                "\($0.sequence)|\($0.kind.rawValue)|\($0.tokenKind)|\($0.range.location):\($0.range.length)|\($0.cost)"
            },
            syntaxFingerprint: run.syntaxFingerprint,
            semantics: semanticSymbols + semanticReferences)
    }
}

public extension IncrementalMeasurementEnvironment {
    /// Shared environment identity used by all PL/0 product entry points.
    static var pl0Current: Self {
        let processInfo = ProcessInfo.processInfo
        return .init(
            hostID: processInfo.environment["PL0_MEASUREMENT_HOST_ID"]
                ?? processInfo.hostName,
            operatingSystem: processInfo.operatingSystemVersionString,
            architecture: currentArchitecture,
            swiftVersion: processInfo.environment["PL0_MEASUREMENT_SWIFT_VERSION"]
                ?? detectedSwiftVersion())
    }

    private static var currentArchitecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }

    private static func detectedSwiftVersion() -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["swift", "--version"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let value = String(decoding: data, as: UTF8.self)
                .split(whereSeparator: \.isNewline).first.map(String.init)
            return value?.isEmpty == false ? value! : "swift-unknown"
        } catch {
            return "swift-unknown"
        }
    }
}
