# PL0-LanguageKit

A standalone PL/0 language package and conformance fixture for parser,
incrementality, recovery, compiler, and tooling experiments.

The package was extracted from ModEdit so no parser or language functionality
depends on an editor application. ModEdit is now one client alongside grammar
and parser workbenches.

Grammar, lexical rules, trivia, and comment forms are compiled from the same
BNF resource by `GrammarParser`. Batch scanning is supplied by Lexer's
`GrammarDrivenLexer`, and incremental tokenization by
`GrammarIncrementalTokenizer`. PL/0 retains only a typed projection for its
public token API; it owns no grammar parser, scanner rules, or
restart/convergence conformances.

Reference-parser region reuse and recovery replay are supplied by
LL-Parsing's `LLRegionMemoizer`; PL/0 provides its rule keys and relocation
conformances without owning the cache algorithm.

Editor-neutral coordinates, completion values, semantic graph queries,
semantic-token encoding, formatting mechanics, and tooling conformance checks
are supplied by `Language-Tooling`. PL/0 retains its binding rules, semantic
classification policy and formatting decisions, while its
native semantic model projects into the shared tooling graph.

Phase 32 removed the legacy PL/0-specific LSP session. Consumers now use
`PL0ProviderSession`, the same `LanguageToolingSession` boundary used by Pascal
and product hosts. Semantic diagnostics are included directly in provider
analysis, so deleting the parallel adapter does not discard diagnostics.

Generated LR analysis consumes LR-Parsing's native resumable stack checkpoints
and publishes engine-owned parser-state evidence. Earley consumes the native
live chart session, retains safe prefix columns and BSR contributions, and
publishes dependency-indexed chart-fact evidence.

`PL0GrammarHotReloadCampaign` now exercises production-only, lexical,
simultaneous grammar/source, and rejected grammar revisions. It preserves the
retained document atomically, validates every activated artifact against clean
ecosystem execution, and publishes Lexer's native grammar-transition evidence.

## Products

- `PL0Language` — grammar-backed lexer, parser front ends, recovery model,
  formatter, semantic analysis, compiler, VM, and the shared
  `PL0Provider` language-provider entry point.
- `PL0Conformance` — accepted, rejected, and mutation corpora shared by
  independent front ends.
- `PL0FrontendConformance` — cross-product conformance plus the versioned
  `PL0ProductCampaign` measurement, grammar hot-reload campaign, and release
  gate.

Transport-neutral experiment and reuse evidence now belongs to
Language-Tooling's `LanguageExperimentProtocol` product. Product-specific
Grammar-Workbench process and hot-reload transport code is no longer part of
this language kit.

## Human-scale reading path

For a quick understanding of the language, read only:

1. `Resources/PL0.grammar`;
2. `PL0LanguageKit.swift` and `Token.swift`;
3. `PL0Parser.swift`, `ConcreteSyntaxTree.swift`, and `SyntaxNode.swift`;
4. `PL0Semantics.swift`;
5. `PL0VirtualMachine.swift`; and
6. `PL0LanguageProvider.swift`.

The remaining engine and campaign files are integration evidence, not a second
definition of the PL/0 language.

The canonical grammar is bundled at
`Sources/PL0Language/Resources/PL0.grammar`. Every supported parser engine is
validated against the same grammar identity and conformance corpus.

## Development

```sh
swift build
swift test
```

Swift 6.1 and macOS 13 or newer are required.

The detailed design notes live in [`Docs/`](Docs/), and the opt-in optimized
parser benchmark is available through `scripts/benchmark-pl0.sh`.
