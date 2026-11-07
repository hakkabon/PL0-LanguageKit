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
classification policy, formatting decisions, and transport adapter, while its
native semantic model projects into the shared tooling graph.

Generated LR analysis consumes LR-Parsing's native resumable stack checkpoints
and publishes engine-owned parser-state evidence. Earley currently discloses a
full-chart fallback rather than treating an unchanged token prefix as reuse.

## Products

- `PL0Language` — grammar-backed lexer, parser front ends, recovery model,
  formatter, semantic analysis, compiler, VM, LSP adapter, and the shared
  `PL0Provider` language-provider entry point.
- `PL0Conformance` — accepted, rejected, and mutation corpora shared by
  independent front ends.
- `PL0FrontendConformance` — cross-product conformance plus the versioned
  `PL0ProductCampaign` measurement and release gate.
- `LanguageExperimentProtocol` — transport-neutral experiment and reuse
  evidence values. This remains a separate module so it can move lower in the
  package graph later without changing PL/0 APIs.

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
