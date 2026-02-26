import XCTest
@testable import Codex_iOS

final class QuickChoiceParserTests: XCTestCase {
    func testDirectoryBulletsBecomeCdCommands() {
        let content = """
Choose a directory:
- src/
- ../
- /Users/aryanrogye/Code/Projects/
"""

        let options = QuickChoiceParser.options(from: content)

        XCTAssertEqual(
            options.map(\.label),
            ["src/", "../", "/Users/aryanrogye/Code/Projects/"]
        )
        XCTAssertEqual(
            options.map(\.insertionText),
            ["cd src/", "cd ../", "cd /Users/aryanrogye/Code/Projects/"]
        )
    }

    func testOrderedDirectoryChoicesAreSupported() {
        let content = """
1. ./Codex_iOS/
2) cd ../
3. ~/Code/
"""

        let options = QuickChoiceParser.options(from: content)

        XCTAssertEqual(
            options.map(\.label),
            ["./Codex_iOS/", "cd ../", "~/Code/"]
        )
        XCTAssertEqual(
            options.map(\.insertionText),
            ["cd ./Codex_iOS/", "cd ../", "cd ~/Code/"]
        )
    }

    func testNonBrowsingLongListsRemainSuppressed() {
        let content = """
- alpha
- beta
- gamma
- delta
- epsilon
"""

        let options = QuickChoiceParser.options(from: content)
        XCTAssertTrue(options.isEmpty)
    }

    func testDirectorySuffixAnnotationConvertsToCdPath() {
        let content = """
- src (directory)
- docs (dir)
"""

        let options = QuickChoiceParser.options(from: content)

        XCTAssertEqual(
            options.map(\.label),
            ["src/", "docs/"]
        )
        XCTAssertEqual(
            options.map(\.insertionText),
            ["cd src/", "cd docs/"]
        )
    }

    func testYesNoFallbackStillWorks() {
        let options = QuickChoiceParser.options(from: "Please respond with yes or no.")

        XCTAssertEqual(
            options,
            [
                QuickChoiceOption(label: "Yes", insertionText: "Yes"),
                QuickChoiceOption(label: "No", insertionText: "No"),
            ]
        )
    }
}
