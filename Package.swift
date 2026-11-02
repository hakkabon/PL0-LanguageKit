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
        .package(url: "https://github.com/hakkabon/Grammar.git", .upToNextMinor(from: "0.3.0")),
        .package(path: "../Parser"),
        .package(path: "../Lexer"),
        .package(path: "../Incremental-Parsing"),
        .package(url: "https://github.com/hakkabon/Earley-Parser.git", .upToNextMinor(from: "0.2.0")),
        .package(url: "https://github.com/hakkabon/CYK-Parser.git", .upToNextMinor(from: "0.2.0")),
        .package(url: "https://github.com/hakkabon/RNGLR-Parser.git", .upToNextMinor(from: "0.2.1")),
        .package(url: "https://github.com/hakkabon/LR-Parsing.git", .upToNextMinor(from: "0.2.3")),
        .package(path: "../LL-Parsing"),
        .package(url: "https://github.com/hakkabon/Earley-TableParser.git", .upToNextMinor(from: "0.1.0")),
        .package(url: "https://github.com/hakkabon/Compiler.git", .upToNextMinor(from: "0.3.0")),
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
            dependencies: ["PL0Language", "PL0Conformance"]),
        .testTarget(
            name: "PL0LanguageTests",
            dependencies: [
                "PL0Language", "PL0Conformance",
                .product(name: "IncrementalParsing", package: "Incremental-Parsing"),
            ]),
        .testTarget(
            name: "LanguageExperimentProtocolTests",
            dependencies: ["LanguageExperimentProtocol"]),
        .testTarget(
            name: "PL0FrontendConformanceTests",
            dependencies: ["PL0FrontendConformance"]),
    ]
)
