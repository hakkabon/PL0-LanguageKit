import Foundation
import IncrementalParsing
import LanguageToolingTesting
import Testing
@testable import PL0Language

@Suite("PL/0 shared semantics, compiler, and provider")
struct SemanticsCompilerLSPTests {
    @Test func semanticModelOwnsScopesSlotsAndResolution() async {
        let source = "const limit = 3; var x; procedure p; var local; begin local := x end; begin x := limit; call p end."
        let analysis = await PL0LanguageSession().analyze(
            PL0Language.SourceSnapshot(version: 7, text: source))

        let limit = analysis.semantics.symbols.first { $0.name == "limit" }
        let x = analysis.semantics.symbols.first { $0.name == "x" }
        let local = analysis.semantics.symbols.first { $0.name == "local" }
        let procedure = analysis.semantics.symbols.first { $0.name == "p" }

        #expect(limit?.kind == .constant)
        #expect(limit?.constantValue == 3)
        #expect(x?.slot == 0)
        #expect(x?.lexicalLevel == 0)
        #expect(local?.slot == 0)
        #expect(local?.lexicalLevel == 1)
        #expect(procedure?.kind == .procedure)
        #expect(analysis.semantics.scopes.count == 2)
        #expect(analysis.semantics.references.count == 5)
        #expect(analysis.semantics.diagnostics.isEmpty)
    }

    @Test func semanticModelPublishesConformingSharedToolingGraph() async throws {
        let source = "const limit = 3; var x; begin x := limit end."
        let analysis = await PL0LanguageSession().analyze(
            PL0Language.SourceSnapshot(version: 8, text: source))

        try ToolingConformance.validate(
            index: analysis.semantics.toolingIndex,
            utf16Length: source.utf16.count)
        #expect(analysis.semantics.toolingIndex.symbols.count
            == analysis.semantics.symbols.count)
    }

    @Test func semanticDiagnosticsAreSharedByCompilerAndProvider() async throws {
        let source = "const c = 1; var x, x; procedure p; ; begin c := p; call x; y := 1 end."
        let analysis = await PL0LanguageSession().analyze(
            PL0Language.SourceSnapshot(version: 1, text: source))
        let provider = PL0ProviderSession()
        let providerAnalysis = try await provider.analyze(
            IncrementalParsing.SourceSnapshot(
                text: source, revision: .init(1)), change: nil)

        #expect(analysis.semantics.diagnostics.contains {
            $0.message.contains("Duplicate declaration")
        })
        #expect(analysis.semantics.diagnostics.contains {
            $0.message.contains("not a variable")
        })
        #expect(analysis.semantics.diagnostics.contains {
            $0.message.contains("Unknown identifier 'y'")
        })
        for diagnostic in analysis.semantics.diagnostics {
            #expect(providerAnalysis.diagnostics.contains {
                $0.message == diagnostic.message
            })
        }
        #expect(throws: PL0CompilationError.self) {
            _ = try PL0Compiler().compile(analysis)
        }
    }

    @Test func compilationPublishesCompilerSyntaxBoundary() async throws {
        let source = "var x; begin x := 2 + 3 end."
        let analysis = await PL0LanguageSession().analyze(
            PL0Language.SourceSnapshot(version: 1, text: source))
        let artifacts = try PL0Compiler().compileArtifacts(analysis)
        let execution = try PL0VirtualMachine().run(artifacts.program)

        #expect(artifacts.compilerSyntax.rule == "PL0Document")
        #expect(artifacts.compilerSyntax.children.last?.rule == "ConcreteTerminals")
        #expect(artifacts.compilerSyntax.children.last?.children.count
                == analysis.parse.syntaxTree.terminals.count)
        #expect(execution.globals.first { $0.name == "x" }?.value == 5)
    }
}
