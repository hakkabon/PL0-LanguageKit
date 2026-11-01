/// Stable language examples shared by parser engines, editors, grammar tools,
/// and mutation campaigns. These are source fixtures, not expected parser
/// implementations, so consumers remain free to produce their native trees.
public enum PL0ConformanceCorpus {
    public static let accepted: [String] = [
        ".",
        "const a = 1, b = 2; .",
        "var x, y; x := -1 + 2 * (3 + y).",
        "procedure p; call p; call p.",
        "begin call p; if odd x then x := x + 1; while x # 0 do x := x - 1 end.",
        "begin if x <= 10 then x := 1; if x >= 2 then x := 0 end.",
    ]

    public static let rejected: [String] = [
        "var ; .",
        "begin x := end.",
        "if odd then .",
        "const x = ; .",
    ]

    /// Small valid programs chosen to expose declarations, procedures,
    /// conditions, expression nesting, and recovery boundaries under edits.
    public static let mutationSeeds: [String] = [
        ".",
        "const n = 3; var x; begin x := n end.",
        "var x; begin x := 0; while x < 4 do x := x + 1 end.",
        "var x; procedure p; begin x := x + 1 end; begin x := 0; call p end.",
        "var x; begin if odd x then x := (x + 1) * 2 end.",
    ]

    public static let mutationFragments: [String] = [
        "", "x", "0", "12", " ", "\n", ";", ":=", "+", "#",
        "begin", "end", "while", "/*", "*/", "// mutation\n", "@",
    ]

    public static let mutationSeed: UInt64 = 0xC0FFEE_5EED

    public static let representativeInsertions: [String] = [
        ";", "begin ", " end", ":=", "(", ")", "if ", " 123 ", "@",
    ]
}
