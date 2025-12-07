import XCTest
@testable import sbparser

final class XcodeBuildParserTests: XCTestCase {

    func testParseSuccessfulBuild() {
        let input = """
        Build settings from command line:
            CODE_SIGN_IDENTITY = -

        === BUILD TARGET MyApp (project MyProject) ===
        Compiling MyApp ViewController.swift
        Compiling MyApp AppDelegate.swift
        ** BUILD SUCCEEDED **
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.format, .xcode)
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.metrics.errorCount, 0)
        XCTAssertEqual(result.metrics.warningCount, 0)
        XCTAssertEqual(result.metrics.compiledFiles.count, 2)
        XCTAssertEqual(result.metrics.targetCount, 1)
    }

    func testParseFailedBuild() {
        let input = """
        === BUILD TARGET MyApp ===
        /path/to/File.swift:42:10: error: cannot find type 'Foo' in scope
        ** BUILD FAILED **
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.format, .xcode)
        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.metrics.errorCount, 1)
        XCTAssertEqual(result.diagnostics.count, 1)

        let diagnostic = result.diagnostics[0]
        XCTAssertEqual(diagnostic.severity, .error)
        XCTAssertEqual(diagnostic.lineNumber, 42)
        XCTAssertEqual(diagnostic.column, 10)
        XCTAssertEqual(diagnostic.filePath, "/path/to/File.swift")
        XCTAssertTrue(diagnostic.message.contains("cannot find type"))
    }

    func testParseWarnings() {
        let input = """
        /path/to/File.swift:10:5: warning: deprecated API
        /path/to/Other.swift:20:1: warning: unused variable
        ** BUILD SUCCEEDED **
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.metrics.warningCount, 2)
        XCTAssertEqual(result.warnings.count, 2)
    }

    func testCanParseDetection() {
        XCTAssertTrue(XcodeBuildParser.canParse("xcodebuild -scheme MyApp"))
        XCTAssertTrue(XcodeBuildParser.canParse("** BUILD SUCCEEDED **"))
        XCTAssertTrue(XcodeBuildParser.canParse("=== BUILD TARGET MyApp ==="))
        XCTAssertTrue(XcodeBuildParser.canParse("CompileSwift normal x86_64"))
        XCTAssertFalse(XcodeBuildParser.canParse("swift build"))
    }

    func testParseNotes() {
        let input = """
        /path/to/File.swift:5:1: note: consider using 'nonisolated'
        ** BUILD SUCCEEDED **
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.metrics.infoCount, 1)
        XCTAssertEqual(result.diagnostics.first?.severity, .info)
    }

    // MARK: - Timing Tests

    func testParseBuildTiming() {
        let input = """
        Build completed in 10.5 seconds
        ** BUILD SUCCEEDED **
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.timing.totalDuration, 10.5, accuracy: 0.01)
    }

    func testParseTimingInParentheses() {
        let input = """
        Build completed in (5.75 seconds)
        ** BUILD SUCCEEDED **
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.timing.totalDuration, 5.75, accuracy: 0.01)
    }

    func testParseBuildStartTime() {
        let input = """
        BUILD START
        Compiling MyApp AppDelegate.swift
        ** BUILD SUCCEEDED **
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        XCTAssertNotNil(result.timing.startTime)
        XCTAssertNotNil(result.timing.endTime)
    }

    func testParseMultipleTimings() {
        let input = """
        Build completed in 2.5s
        (3.2 seconds)
        ** BUILD SUCCEEDED **
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        // Should capture one of the timings
        XCTAssertGreaterThan(result.timing.totalDuration, 0)
    }

    // MARK: - File Compilation Tests

    func testParseCompiledFiles() {
        let input = """
        Compiling MyApp ViewController.swift
        Compiling MyApp AppDelegate.swift
        Compiling MyApp Models.swift
        ** BUILD SUCCEEDED **
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.metrics.compiledFiles.count, 3)
        XCTAssertTrue(result.metrics.compiledFiles.contains("ViewController.swift"))
        XCTAssertTrue(result.metrics.compiledFiles.contains("AppDelegate.swift"))
        XCTAssertTrue(result.metrics.compiledFiles.contains("Models.swift"))
    }

    func testParseCompileSwiftPattern() {
        let input = """
        CompileSwift normal x86_64 /path/to/File.swift
        ** BUILD SUCCEEDED **
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        XCTAssertTrue(result.metrics.compiledFiles.contains("File.swift"))
    }

    func testParseSwiftCompilePattern() {
        let input = """
        SwiftCompile normal x86_64 /path/to/Source.swift
        ** BUILD SUCCEEDED **
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        XCTAssertTrue(result.metrics.compiledFiles.contains("Source.swift"))
    }

    func testParseFileWithFullPath() {
        let input = """
        Compiling MyApp /Users/dev/Projects/MyApp/Sources/AppDelegate.swift
        ** BUILD SUCCEEDED **
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        // Should extract just the filename
        XCTAssertTrue(result.metrics.compiledFiles.contains("AppDelegate.swift"))
        XCTAssertFalse(result.metrics.compiledFiles.contains("/Users/dev"))
    }

    func testParseMultipleCompilationPatterns() {
        let input = """
        CompileSwift normal x86_64 File1.swift
        Compiling MyApp File2.swift
        SwiftCompile normal x86_64 File3.swift
        ** BUILD SUCCEEDED **
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.metrics.compiledFiles.count, 3)
    }

    // MARK: - Target Count Tests

    func testParseTargetCount() {
        let input = """
        === BUILD TARGET MyApp ===
        === BUILD TARGET MyAppTests ===
        ** BUILD SUCCEEDED **
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.metrics.targetCount, 2)
    }

    func testParseBuildTargetPattern() {
        let input = """
        Build target MyApp
        ** BUILD SUCCEEDED **
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.metrics.targetCount, 1)
    }

    // MARK: - Complex Error Scenarios

    func testParseMultipleErrors() {
        let input = """
        /path/to/File1.swift:10:5: error: use of unresolved identifier
        /path/to/File2.swift:15:8: error: value of optional type not unwrapped
        /path/to/File3.swift:20:1: error: cannot find type 'MyClass'
        ** BUILD FAILED **
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.metrics.errorCount, 3)
        XCTAssertEqual(result.diagnostics.count, 3)
        XCTAssertEqual(result.status, .failed)
    }

    func testParseErrorsWithDifferentLineFormats() {
        let input = """
        /path/to/File.swift:42:10: error: test error
        ** BUILD FAILED **
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        let error = result.diagnostics.first
        XCTAssertEqual(error?.lineNumber, 42)
        XCTAssertEqual(error?.column, 10)
        XCTAssertEqual(error?.filePath, "/path/to/File.swift")
    }

    func testParseErrorsWithoutColumn() {
        let input = """
        /path/to/File.swift:42: error: test error
        ** BUILD FAILED **
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        let error = result.diagnostics.first
        XCTAssertEqual(error?.lineNumber, 42)
        XCTAssertNil(error?.column)
    }

    func testParseErrorsWithWhitespace() {
        let input = """
          /path/to/File.swift:42:10:  error:  spacing issue
        ** BUILD FAILED **
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        let error = result.diagnostics.first
        XCTAssertEqual(error?.lineNumber, 42)
        XCTAssertTrue(error?.message.contains("spacing issue") ?? false)
    }

    // MARK: - Build Status Variations

    func testParseBuildStatusVariations() {
        let testCases = [
            "BUILD SUCCEEDED",
            "** BUILD SUCCEEDED **",
            "Build succeeded"
        ]

        for testCase in testCases {
            let input = testCase
            let parser = XcodeBuildParser()
            let result = parser.parse(input)

            XCTAssertEqual(result.status, .success, "Failed for: \(testCase)")
        }
    }

    func testParseBuildFailedVariations() {
        let testCases = [
            "BUILD FAILED",
            "** BUILD FAILED **",
            "Build failed"
        ]

        for testCase in testCases {
            let input = testCase
            let parser = XcodeBuildParser()
            let result = parser.parse(input)

            XCTAssertEqual(result.status, .failed, "Failed for: \(testCase)")
        }
    }

    // MARK: - Edge Cases

    func testParseEmptyLines() {
        let input = """

        Compiling MyApp AppDelegate.swift

        ** BUILD SUCCEEDED **

        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.metrics.errorCount, 0)
    }

    func testParseUnknownStatusWithoutErrors() {
        let input = """
        Compiling MyApp AppDelegate.swift
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        // Should default to success when no errors
        XCTAssertEqual(result.status, .success)
    }

    func testParseUnknownStatusWithErrors() {
        let input = """
        /path/to/File.swift:10:5: error: test
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        // Should default to failed when errors exist
        XCTAssertEqual(result.status, .failed)
    }

    func testParseXcodeBuildCommand() {
        let input = """
        xcodebuild -scheme MyApp clean build
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.status, .success)
        XCTAssertNotNil(result.timing.startTime)
    }

    func testParseWithSpecialCharactersInPath() {
        let input = """
        /path/to/File with spaces.swift:42:10: error: test
        ** BUILD FAILED **
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        let error = result.diagnostics.first
        XCTAssertEqual(error?.filePath, "/path/to/File with spaces.swift")
        XCTAssertEqual(error?.lineNumber, 42)
    }

    func testParseWithWindowsStylePath() {
        let input = """
        C:\\Projects\\MyApp\\File.swift:42:10: error: test
        ** BUILD FAILED **
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        let error = result.diagnostics.first
        XCTAssertEqual(error?.filePath, "C:\\Projects\\MyApp\\File.swift")
    }

    // MARK: - Mixed Diagnostic Types

    func testParseMixOfErrorsWarningsAndNotes() {
        let input = """
        /path/to/File1.swift:10:5: error: unresolved identifier
        /path/to/File1.swift:12:1: warning: unused variable
        /path/to/File2.swift:15:3: note: did you mean 'foo'?
        /path/to/File2.swift:20:8: error: cannot convert type
        ** BUILD FAILED **
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.metrics.errorCount, 2)
        XCTAssertEqual(result.metrics.warningCount, 1)
        XCTAssertEqual(result.metrics.infoCount, 1)
        XCTAssertEqual(result.diagnostics.count, 4)
    }

    // MARK: - Real-World Xcode Output

    func testParseRealWorldXcodeOutput() {
        let input = """
        Command line invocation:
        /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -scheme MyApp -configuration Debug clean build

        Build settings from command line:
            CODE_SIGN_IDENTITY = -

        === BUILD TARGET MyApp (project MyApp.xcodeproj) ===
        ProcessInfoPlistFile MyApp/Info.plist (in target 'MyApp' from project 'MyApp')
        CompileSwift normal x86_64 (in target 'MyApp' from project 'MyApp')
            /path/to/MyApp/AppDelegate.swift (in target 'MyApp' from project 'MyApp')
            /path/to/MyApp/ViewController.swift (in target 'MyApp' from project 'MyApp')
        Ld /path/to/MyApp.app normal x86_64 (in target 'MyApp' from project 'MyApp')
        CodeSign /path/to/MyApp.app (in target 'MyApp' from project 'MyApp')
        ProcessInfoPlistFile /path/to/MyApp.app/Contents/Info.plist (in target 'MyApp' from project 'MyApp')

        ** BUILD SUCCEEDED **
        Build completed in 8.42 seconds
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.format, .xcode)
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.metrics.targetCount, 1)
        XCTAssertGreaterThanOrEqual(result.metrics.compiledFiles.count, 2)
        XCTAssertEqual(result.timing.totalDuration, 8.42, accuracy: 0.01)
    }

    func testParseXcodeBuildWithIncrementalCompile() {
        let input = """
        CompileSwift normal x86_64 (in target 'MyApp' from project 'MyApp')
            /path/to/MyApp/ViewController.swift (in target 'MyApp' from project 'MyApp')
        CompileSwift normal x86_64 (in target 'MyApp' from project 'MyApp')
            /path/to/MyApp/AppDelegate.swift (in target 'MyApp' from project 'MyApp')
        ** BUILD SUCCEEDED **
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.metrics.compiledFiles.count, 2)
    }

    // MARK: - CanParse Tests - Additional Coverage

    func testCanParseWithXcodeSpecificMarkers() {
        XCTAssertTrue(XcodeBuildParser.canParse("ProcessInfoPlistFile"))
        XCTAssertTrue(XcodeBuildParser.canParse("Ld "))
        XCTAssertTrue(XcodeBuildParser.canParse("CodeSign"))
        XCTAssertTrue(XcodeBuildParser.canParse("Build settings from"))
    }

    func testCanParseNotConfusedWithSwift() {
        XCTAssertFalse(XcodeBuildParser.canParse("swift build"))
        XCTAssertFalse(XcodeBuildParser.canParse("Build complete!"))
        XCTAssertFalse(XcodeBuildParser.canParse("Compiling Swift Module"))
        XCTAssertFalse(XcodeBuildParser.canParse("Linking "))
    }

    func testCanParseWithPartialMatches() {
        XCTAssertTrue(XcodeBuildParser.canParse("xcodebuild"))
        XCTAssertTrue(XcodeBuildParser.canParse("BUILD SUCCEEDED"))
        XCTAssertTrue(XcodeBuildParser.canParse("=== BUILD TARGET"))
        XCTAssertTrue(XcodeBuildParser.canParse("CompileSwift"))
    }

    // MARK: - Duration Extraction Tests

    func testExtractDurationPatterns() {
        let testCases = [
            ("completed in 12.34s", 12.34),
            ("(5.67 seconds)", 5.67),
            ("Build Completed in 8.90 seconds", 8.90)
        ]

        for (input, expected) in testCases {
            let parser = XcodeBuildParser()
            let result = parser.parse(input)

            XCTAssertEqual(result.timing.totalDuration, expected, accuracy: 0.01, "Failed for: \(input)")
        }
    }

    func testParseZeroDuration() {
        let input = """
        Build completed in 0s
        ** BUILD SUCCEEDED **
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.timing.totalDuration, 0.0, accuracy: 0.01)
    }

    func testParseVeryLongDuration() {
        let input = """
        Build completed in 999.99 seconds
        ** BUILD SUCCEEDED **
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.timing.totalDuration, 999.99, accuracy: 0.01)
    }

    // MARK: - Location Parsing Tests

    func testParseLocationWithFullPath() {
        let input = """
        /Users/dev/Projects/MyApp/Sources/File.swift:42:10: error: test
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        let error = result.diagnostics.first
        XCTAssertEqual(error?.filePath, "/Users/dev/Projects/MyApp/Sources/File.swift")
        XCTAssertEqual(error?.location, "/Users/dev/Projects/MyApp/Sources/File.swift:42:10")
    }

    func testParseLocationWithRelativePath() {
        let input = """
        Sources/File.swift:10:5: error: test
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        let error = result.diagnostics.first
        XCTAssertEqual(error?.filePath, "Sources/File.swift")
        XCTAssertEqual(error?.location, "Sources/File.swift:10:5")
    }

    func testParseLocationWithoutLineNumber() {
        let input = """
        /path/to/File.swift: error: test
        """

        let parser = XcodeBuildParser()
        let result = parser.parse(input)

        let error = result.diagnostics.first
        XCTAssertEqual(error?.filePath, "/path/to/File.swift")
        XCTAssertNil(error?.lineNumber)
    }
}
