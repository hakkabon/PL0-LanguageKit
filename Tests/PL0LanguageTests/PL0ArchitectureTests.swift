import Foundation
import Testing

@Suite("PL/0 language-kit ownership")
struct PL0ArchitectureTests {
    @Test func implementationFilesDeclareTheirLanguageOwnership() throws {
        let tests = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = tests
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/PL0Language")
        let files = try FileManager.default.contentsOfDirectory(
            at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .map(\.lastPathComponent)

        #expect(!files.isEmpty)
        #expect(files.allSatisfy { $0.hasPrefix("PL0") })
    }
}
