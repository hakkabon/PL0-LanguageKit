# PL0-LanguageKit

A standalone PL/0 language package and conformance fixture for parser,
incrementality, recovery, compiler, and tooling experiments.

The package was extracted from ModEdit so no parser or language functionality
depends on an editor application. ModEdit is now one client alongside grammar
and parser workbenches.

Incremental tokenization is supplied by Lexer's generic
`RestartAndConvergeTokenizer`; this package provides only the PL/0 scanner and
the conformances that describe its tokens, trivia, and diagnostics.

Reference-parser region reuse and recovery replay are supplied by
LL-Parsing's `LLRegionMemoizer`; PL/0 provides its rule keys and relocation
conformances without owning the cache algorithm.

## Products

- `PL0Language` — grammar-backed lexer, parser front ends, recovery model,
  formatter, semantic analysis, compiler, VM, and LSP adapter.
- `PL0Conformance` — accepted, rejected, and mutation corpora shared by
  independent front ends.
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
