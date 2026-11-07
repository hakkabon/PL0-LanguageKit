// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "PL0-LanguageKit",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "PL0Language", targets: ["PL0Language"]),
        .library(name: "PL0Conformance", targets: ["PL0Conformance"]),
        .library(name: "PL0FrontendConformance", targets: ["PL0FrontendConformance"]),
        .library(
            name: "LanguageExperimentProtocol",
            targets: ["LanguageExperimentProtocol"]),
    ],
    dependencies: [
        .package(path: "../Grammar"),
        .package(path: "../Parser"),
        .package(path: "../Lexer"),
        .package(path: "../Incremental-Parsing"),
        .package(path: "../Language-Tooling"),
        .package(path: "../Earley-Parser"),
        .package(path: "../CYK-Parser"),
        .package(path: "../RNGLR-Parser"),
        .package(path: "../LR-Parsing"),
        .package(path: "../LL-Parsing"),
        .package(path: "../Earley-TableParser"),
        .package(path: "../Compiler"),
    ],
    targets: [
        .target(name: "LanguageExperimentProtocol"),
        .target(
            name: "CompilerBridge",
            dependencies: [
                .product(name: "Compiler", package: "Compiler"),
            ]),
        .target(
            name: "PL0Language",
            dependencies: [
                "LanguageExperimentProtocol",
                "CompilerBridge",
                .product(name: "Grammar", package: "Grammar"),
                .product(name: "Parser", package: "Parser"),
                .product(name: "Lexer", package: "Lexer"),
                .product(name: "IncrementalParsing", package: "Incremental-Parsing"),
                .product(name: "LanguageTooling", package: "Language-Tooling"),
                .product(
                    name: "LanguageToolingFormatting",
                    package: "Language-Tooling"),
                .product(name: "Earley-Parser", package: "Earley-Parser"),
                .product(name: "CYK-Parser", package: "CYK-Parser"),
                .product(name: "RNGLR-Parser", package: "RNGLR-Parser"),
                .product(name: "LR-Parsing", package: "LR-Parsing"),
                .product(name: "LL-Parsing", package: "LL-Parsing"),
                .product(name: "Earley-TableParser", package: "Earley-TableParser"),
            ],
            resources: [.process("Resources")]),
        .target(name: "PL0Conformance"),
        .target(
            name: "PL0FrontendConformance",
            dependencies: [
                "PL0Language", "PL0Conformance",
                .product(
                    name: "IncrementalParsing",
                    package: "Incremental-Parsing"),
            ]),
        .testTarget(
            name: "PL0LanguageTests",
            dependencies: [
                "PL0Language", "PL0Conformance",
                .product(name: "IncrementalParsing", package: "Incremental-Parsing"),
                .product(name: "LanguageTooling", package: "Language-Tooling"),
                .product(
                    name: "LanguageToolingTesting",
                    package: "Language-Tooling"),
            ]),
        .testTarget(
            name: "LanguageExperimentProtocolTests",
            dependencies: ["LanguageExperimentProtocol"]),
        .testTarget(
            name: "PL0FrontendConformanceTests",
            dependencies: [
                "PL0FrontendConformance",
                .product(
                    name: "IncrementalParsing",
                    package: "Incremental-Parsing"),
            ]),
    ]
)
