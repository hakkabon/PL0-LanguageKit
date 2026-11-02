import Foundation
import PL0Conformance
import PL0Language

public struct PL0FrontendExperimentObservation: Codable, Hashable, Sendable {
    public let caseID: String
    public let engineID: String
    public let grammarFingerprint: String
    public let status: String
    public let tokenEvidence: [String]
    public let diagnostics: [String]
    public let recovery: [String]
    public let syntaxFingerprint: String?

    public init(caseID: String, engineID: String, grammarFingerprint: String,
                status: String, tokenEvidence: [String], diagnostics: [String],
                recovery: [String], syntaxFingerprint: String?) {
        self.caseID = caseID; self.engineID = engineID
        self.grammarFingerprint = grammarFingerprint; self.status = status
        self.tokenEvidence = tokenEvidence; self.diagnostics = diagnostics
        self.recovery = recovery; self.syntaxFingerprint = syntaxFingerprint
    }
}

public struct PL0FrontendExperimentReport: Codable, Hashable, Sendable {
    public static let schemaVersion = 1
    public let schemaVersion: Int
    public let frontendID: String
    public let observations: [PL0FrontendExperimentObservation]

    public init(frontendID: String, observations: [PL0FrontendExperimentObservation]) {
        schemaVersion = Self.schemaVersion
        self.frontendID = frontendID
        self.observations = observations
    }

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> Self {
        try JSONDecoder().decode(Self.self, from: data)
    }
}

public struct PL0CrossFrontendAgreement: Codable, Hashable, Sendable {
    public let equivalent: Bool
    public let frontends: [String]
    public let mismatchDescriptions: [String]
}

public enum PL0FrontendExperimentSuite {
    public static func run(frontendID: String) async throws -> PL0FrontendExperimentReport {
        let cases = PL0ConformanceCorpus.accepted.enumerated().map {
            ("accepted-\($0.offset)", $0.element)
        } + PL0ConformanceCorpus.rejected.enumerated().map {
            ("recovery-\($0.offset)", $0.element)
        }
        var observations: [PL0FrontendExperimentObservation] = []
        for engine in ParserEngine.allCases {
            let session = PL0LanguageSession(engine: engine)
            for (index, fixture) in cases.enumerated() {
                let snapshot = SourceSnapshot(version: UInt64(index + 1), text: fixture.1)
                let analysis = await session.analyze(snapshot)
                let engineID = analysis.parse.parser.id
                let run = try analysis.experimentRun(
                    documentURI: "conformance:///\(fixture.0).pl0", runID: "\(fixture.0):\(engineID)")
                observations.append(.init(
                    caseID: fixture.0,
                    engineID: engineID,
                    grammarFingerprint: run.grammar.fingerprint,
                    status: run.status.rawValue,
                    tokenEvidence: run.tokenSnapshot.tokens.map {
                        "\($0.kind)|\($0.lexeme)|\($0.range.location):\($0.range.length)|\($0.channel.rawValue)"
                    },
                    diagnostics: run.diagnostics.map {
                        "\($0.severity.rawValue)|\($0.range.location):\($0.range.length)|\($0.message)|\($0.expected.joined(separator: ","))"
                    },
                    recovery: run.recovery.edits.map {
                        "\($0.sequence)|\($0.kind.rawValue)|\($0.tokenKind)|\($0.range.location):\($0.range.length)|\($0.cost)"
                    },
                    syntaxFingerprint: run.syntaxFingerprint))
            }
        }
        return .init(frontendID: frontendID, observations: observations)
    }

    public static func compare(_ reports: [PL0FrontendExperimentReport]) -> PL0CrossFrontendAgreement {
        guard let baseline = reports.first else {
            return .init(equivalent: false, frontends: [], mismatchDescriptions: ["No reports supplied."])
        }
        var mismatches: [String] = []
        for report in reports.dropFirst() where report.observations != baseline.observations {
            let count = max(baseline.observations.count, report.observations.count)
            for index in 0..<count {
                let expected = baseline.observations.indices.contains(index) ? baseline.observations[index] : nil
                let actual = report.observations.indices.contains(index) ? report.observations[index] : nil
                if expected != actual {
                    mismatches.append("\(report.frontendID) differs from \(baseline.frontendID) at observation \(index) (\(expected?.caseID ?? "missing")/\(expected?.engineID ?? "missing")).")
                }
            }
        }
        return .init(equivalent: mismatches.isEmpty,
                     frontends: reports.map(\.frontendID), mismatchDescriptions: mismatches)
    }
}
