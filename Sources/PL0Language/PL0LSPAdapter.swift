import Foundation
import LanguageTooling

// MARK: - Transport-neutral LSP values

public typealias LSPPosition = ToolingPosition
public typealias LSPRange = ToolingRange

public struct LSPDiagnostic: Sendable, Equatable, Identifiable {
    public let range: LSPRange
    public let severity: DiagnosticSeverity
    public let message: String
    public let source: String
    public var id: String { "\(range):\(message)" }
}

public typealias LSPCompletionKind = ToolingCompletionKind
public typealias LSPCompletionItem = ToolingCompletionItem
public typealias LSPLocation = ToolingLocation
public typealias LSPHover = ToolingHover
public typealias LSPSemanticTokenType = ToolingSemanticTokenType
public typealias LSPSemanticToken = ToolingSemanticToken
public typealias LSPSemanticTokensResult = ToolingSemanticTokensResult
public typealias LSPTextChange = ToolingTextChange

public enum PL0LSPError: Error, Sendable, Equatable, CustomStringConvertible {
    case documentNotOpen(String)
    case staleVersion(current: UInt64, received: UInt64)
    case invalidRange(LSPRange)

    public var description: String {
        switch self {
        case let .documentNotOpen(uri): "Document is not open: \(uri)"
        case let .staleVersion(current, received):
            "Document version \(received) is not newer than \(current)"
        case let .invalidRange(range): "Invalid LSP range: \(range)"
        }
    }
}

public typealias LSPLineMap = LanguageTooling.SourceLineMap

public extension LanguageTooling.SourceLineMap {
    func lspRange(_ range: SourceRange) -> LSPRange {
        toolingRange(range.incrementalRange)
    }
}

// MARK: - Versioned adapter

/// An actor suitable for direct editor use or for wrapping in JSON-RPC. It
/// deliberately contains no AppKit or transport code.
public actor PL0LSPAdapter {
    private struct Document: Sendable {
        var version: UInt64
        var text: String
        var analysis: PL0Analysis
        let session: PL0LanguageSession
    }

    private var documents: [String: Document] = [:]
    private let frontend: PL0Frontend

    public init() {
        frontend = PL0Frontend()
    }

    public init(frontend: PL0Frontend) {
        self.frontend = frontend
    }

    @discardableResult
    public func open(uri: String, version: UInt64,
                     text: String) async -> [LSPDiagnostic] {
        let session = PL0LanguageSession(
            engine: frontend.engine, languageKit: frontend.languageKit)
        let snapshot = SourceSnapshot(version: version, text: text)
        let document = Document(
            version: version, text: text,
            analysis: await session.analyze(snapshot), session: session)
        documents[uri] = document
        return diagnostics(for: document)
    }

    @discardableResult
    public func change(uri: String, version: UInt64,
                       changes: [LSPTextChange]) async throws -> [LSPDiagnostic] {
        guard var document = documents[uri] else { throw PL0LSPError.documentNotOpen(uri) }
        guard version > document.version else {
            throw PL0LSPError.staleVersion(current: document.version, received: version)
        }
        var sourceEdit: SourceEdit?
        for (changeIndex, change) in changes.enumerated() {
            let oldText = document.text
            if let range = change.range {
                let map = LSPLineMap(document.text)
                guard let start = map.offset(of: range.start),
                      let end = map.offset(of: range.end), end >= start else {
                    throw PL0LSPError.invalidRange(range)
                }
                document.text = (document.text as NSString).replacingCharacters(
                    in: NSRange(location: start, length: end - start), with: change.text)
                if changes.count == 1, changeIndex == 0 {
                    sourceEdit = SourceEdit(
                        baseVersion: document.version,
                        replacedRange: SourceRange(location: start, length: end - start),
                        replacementLength: change.text.utf16.count)
                }
            } else {
                document.text = change.text
                if changes.count == 1, changeIndex == 0 {
                    sourceEdit = SourceEdit(
                        baseVersion: document.version,
                        replacedRange: SourceRange(
                            location: 0, length: oldText.utf16.count),
                        replacementLength: change.text.utf16.count)
                }
            }
        }
        document.version = version
        document.analysis = await document.session.analyze(SourceSnapshot(
            version: version, text: document.text, edit: sourceEdit))
        documents[uri] = document
        return diagnostics(for: document)
    }

    public func close(uri: String) { documents.removeValue(forKey: uri) }

    public func diagnostics(uri: String) throws -> [LSPDiagnostic] {
        guard let document = documents[uri] else { throw PL0LSPError.documentNotOpen(uri) }
        return diagnostics(for: document)
    }

    public func completions(uri: String, at position: LSPPosition) throws -> [LSPCompletionItem] {
        guard let document = documents[uri] else { throw PL0LSPError.documentNotOpen(uri) }
        guard let offset = LSPLineMap(document.text).offset(of: position) else {
            throw PL0LSPError.invalidRange(LSPRange(start: position, end: position))
        }
        let keywords = frontend.languageKit.keywordSpellings.map {
            LSPCompletionItem(label: $0, kind: .keyword,
                              detail: "PL/0 keyword", insertText: $0)
        }
        return (keywords + document.analysis.semantics.toolingIndex
            .visibleSymbols(at: offset).map { symbol in
            LSPCompletionItem(label: symbol.name, kind: completionKind(symbol.kind),
                              detail: symbol.detail ?? symbol.kind.rawValue,
                              insertText: symbol.name)
        }).toolingUniquedByID().sorted {
            $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
    }

    public func definition(uri: String, at position: LSPPosition) throws -> LSPLocation? {
        guard let document = documents[uri] else { throw PL0LSPError.documentNotOpen(uri) }
        let map = LSPLineMap(document.text)
        guard let offset = map.offset(of: position) else {
            throw PL0LSPError.invalidRange(LSPRange(start: position, end: position))
        }
        guard let declaration = document.analysis.semantics.toolingIndex
            .symbol(at: offset) else { return nil }
        return LSPLocation(uri: uri,
                           range: map.toolingRange(declaration.declarationRange))
    }

    public func hover(uri: String, at position: LSPPosition) throws -> LSPHover? {
        guard let document = documents[uri] else { throw PL0LSPError.documentNotOpen(uri) }
        let map = LSPLineMap(document.text)
        guard let offset = map.offset(of: position) else {
            throw PL0LSPError.invalidRange(LSPRange(start: position, end: position))
        }
        let semantics = document.analysis.semantics.toolingIndex
        let symbol = semantics.symbol(at: offset)
        guard let symbol else { return nil }
        return LSPHover(
            contents: symbol.detail ?? "\(symbol.kind.rawValue) \(symbol.name)",
            range: map.toolingRange(symbol.declarationRange))
    }

    public func references(uri: String, at position: LSPPosition,
                           includeDeclaration: Bool = true) throws -> [LSPLocation] {
        guard let document = documents[uri] else { throw PL0LSPError.documentNotOpen(uri) }
        let map = LSPLineMap(document.text)
        guard let offset = map.offset(of: position) else {
            throw PL0LSPError.invalidRange(LSPRange(start: position, end: position))
        }
        let semantics = document.analysis.semantics.toolingIndex
        let symbol = semantics.symbol(at: offset)
        guard let symbol else { return [] }
        return semantics.references(
            to: symbol.id,
            includeDeclaration: includeDeclaration
        ).map { LSPLocation(uri: uri, range: map.toolingRange($0)) }
    }

    public func semanticTokens(uri: String) throws -> [LSPSemanticToken] {
        guard let document = documents[uri] else { throw PL0LSPError.documentNotOpen(uri) }
        let map = LSPLineMap(document.text)
        return document.analysis.semantics.semanticTokens.compactMap {
            guard let type = semanticTokenType($0.classification) else { return nil }
            return LSPSemanticToken(range: map.lspRange($0.range), type: type,
                             isDeclaration: $0.isDeclaration)
        }
    }

    public func semanticTokenData(uri: String) throws -> LSPSemanticTokensResult {
        guard let document = documents[uri] else { throw PL0LSPError.documentNotOpen(uri) }
        return SemanticTokenEncoder.encode(
            try semanticTokens(uri: uri),
            resultID: "\(document.version):\(document.analysis.semantics.grammarFingerprint)",
            legend: [.keyword, .number, .operatorToken, .variable, .constant, .function])
    }

    public func snapshot(uri: String) throws -> SourceSnapshot {
        guard let document = documents[uri] else { throw PL0LSPError.documentNotOpen(uri) }
        return SourceSnapshot(version: document.version, text: document.text)
    }

    public func analysis(uri: String) throws -> PL0Analysis {
        guard let document = documents[uri] else {
            throw PL0LSPError.documentNotOpen(uri)
        }
        return document.analysis
    }

    private func diagnostics(for document: Document) -> [LSPDiagnostic] {
        let map = LSPLineMap(document.text)
        var result = document.analysis.parse.diagnostics.map {
            LSPDiagnostic(range: map.lspRange($0.range), severity: $0.severity,
                          message: $0.message, source: "pl0-parser")
        }
        result.append(contentsOf: document.analysis.semantics.diagnostics.map {
            LSPDiagnostic(range: map.lspRange($0.range), severity: .error,
                          message: $0.message, source: "pl0-semantics")
        })
        return result.toolingUniquedByID()
    }

    private func completionKind(_ kind: ToolingSymbolKind) -> LSPCompletionKind {
        if kind == .constant { return .constant }
        if kind == .function { return .function }
        return .variable
    }

    private func semanticTokenType(
        _ classification: PL0SemanticClassification
    ) -> LSPSemanticTokenType? {
        switch classification {
        case .keyword: .keyword
        case .number: .number
        case .operatorToken: .operatorToken
        case .symbol(.constant): .constant
        case .symbol(.variable): .variable
        case .symbol(.procedure): .function
        }
    }
}
