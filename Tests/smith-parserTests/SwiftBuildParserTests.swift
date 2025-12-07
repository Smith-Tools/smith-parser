import XCTest
@testable import sbparser

final class SwiftBuildParserTests: XCTestCase {

    // MARK: - Build Status Tests

    func testParseSuccessfulBuild() {
        let input = """
        Building for production...
        Compiling Swift Module 'MyApp' (1 source)
        Compiling MyApp AppDelegate.swift
        Compiling MyApp ViewController.swift
        Linking MyApp
        Build complete! (2.34s)
        """

        let parser = SwiftBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.format, .swift)
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.metrics.errorCount, 0)
        XCTAssertEqual(result.metrics.warningCount, 0)
        XCTAssertEqual(result.metrics.compiledFiles.count, 2)
        XCTAssertEqual(result.metrics.targetCount, 1)
        XCTAssertEqual(result.timing.totalDuration, 2.34, accuracy: 0.01)
    }

    func testParseFailedBuildWithErrors() {
        let input = """
        Building for production...
        Compiling Swift Module 'MyApp' (2 sources)
        /path/to/File.swift:10:5: error: use of unresolved identifier 'foo'
        /path/to/File.swift:15:8: error: value of optional type 'String?' not unwrapped
        Build failed with 2 errors in 0.5s
        """

        let parser = SwiftBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.format, .swift)
        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.metrics.errorCount, 2)
        XCTAssertEqual(result.diagnostics.count, 2)

        // Test first error
        let error1 = result.diagnostics[0]
        XCTAssertEqual(error1.severity, .error)
        XCTAssertEqual(error1.lineNumber, 10)
        XCTAssertEqual(error1.column, 5)
        XCTAssertEqual(error1.filePath, "/path/to/File.swift")
        XCTAssertTrue(error1.message.contains("unresolved identifier"))

        // Test second error
        let error2 = result.diagnostics[1]
        XCTAssertEqual(error2.lineNumber, 15)
        XCTAssertEqual(error2.column, 8)
    }

    func testParseBuildCompleteWithDuration() {
        let input = """
        Compiling Swift Module 'MyLibrary' (5 sources)
        Build complete! (15.42s)
        """

        let parser = SwiftBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.timing.totalDuration, 15.42, accuracy: 0.01)
    }

    // MARK: - Warning Tests

    func testParseWarnings() {
        let input = """
        /path/to/File.swift:20:1: warning: variable 'count' was never used
        /path/to/Utils.swift:5:15: warning: 'openURL(_:)' is deprecated
        Compiling Swift Module 'MyApp'
        """

        let parser = SwiftBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.metrics.warningCount, 2)
        XCTAssertEqual(result.warnings.count, 2)

        let warning1 = result.warnings[0]
        XCTAssertEqual(warning1.severity, .warning)
        XCTAssertEqual(warning1.lineNumber, 20)
        XCTAssertEqual(warning1.filePath, "/path/to/File.swift")
    }

    func testParseMultipleWarningsAndErrors() {
        let input = """
        /path/to/File.swift:10:5: error: use of unresolved identifier
        /path/to/File.swift:12:1: warning: variable 'x' was never used
        /path/to/File.swift:15:8: error: cannot convert value
        /path/to/Other.swift:5:10: warning: deprecated API usage
        """

        let parser = SwiftBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.metrics.errorCount, 2)
        XCTAssertEqual(result.metrics.warningCount, 2)
        XCTAssertEqual(result.diagnostics.count, 4)
    }

    // MARK: - Note Tests

    func testParseNotes() {
        let input = """
        /path/to/File.swift:10:5: error: use of unresolved identifier
        /path/to/File.swift:10:5: note: did you mean 'foo'?
        """

        let parser = SwiftBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.metrics.errorCount, 1)
        XCTAssertEqual(result.metrics.infoCount, 1)

        let info = result.diagnostics.first { $0.severity == .info }
        XCTAssertNotNil(info)
        XCTAssertTrue(info?.message.contains("did you mean") ?? false)
    }

    // MARK: - File Compilation Tests

    func testParseCompiledFiles() {
        let input = """
        Compiling Swift Module 'MyApp' (3 sources)
        Compiling MyApp AppDelegate.swift
        Compiling MyApp ViewController.swift
        Compiling MyApp Models.swift
        Linking MyApp
        """

        let parser = SwiftBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.metrics.compiledFiles.count, 3)
        XCTAssertTrue(result.metrics.compiledFiles.contains("AppDelegate.swift"))
        XCTAssertTrue(result.metrics.compiledFiles.contains("ViewController.swift"))
        XCTAssertTrue(result.metrics.compiledFiles.contains("Models.swift"))
    }

    func testParseFileCompilationWithFullPath() {
        let input = """
        Compiling Swift Module 'MyApp' (2 sources)
        Compiling MyApp /Users/dev/Projects/MyApp/Sources/AppDelegate.swift
        Compiling MyApp /Users/dev/Projects/MyApp/Sources/ViewController.swift
        """

        let parser = SwiftBuildParser()
        let result = parser.parse(input)

        // Should extract just the filename
        XCTAssertTrue(result.metrics.compiledFiles.contains("AppDelegate.swift"))
        XCTAssertTrue(result.metrics.compiledFiles.contains("ViewController.swift"))
        XCTAssertFalse(result.metrics.compiledFiles.contains("/Users/dev"))
    }

    // MARK: - Timing Tests

    func testParseBuildTiming() {
        let input = """
        Compiling Swift Module 'MyApp'
        Build complete! (10.5s)
        """

        let parser = SwiftBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.timing.totalDuration, 10.5, accuracy: 0.01)
    }

    func testParseTimingInParentheses() {
        let input = """
        Build complete! (3.14159s)
        """

        let parser = SwiftBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.timing.totalDuration, 3.14159, accuracy: 0.0001)
    }

    func testParseMultipleTimings() {
        let input = """
        Compiling File1.swift
        [0.5s] Compiling File1.swift
        Compiling File2.swift
        Build complete! (2.5s)
        """

        let parser = SwiftBuildParser()
        let result = parser.parse(input)

        // Should use the maximum duration found
        XCTAssertEqual(result.timing.totalDuration, 2.5, accuracy: 0.01)
    }

    func testParseTimingWithoutParens() {
        let input = """
        Build completed in 8.75s
        """

        let parser = SwiftBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.timing.totalDuration, 8.75, accuracy: 0.01)
    }

    // MARK: - Target Count Tests

    func testParseTargetCountFromCompiling() {
        let input = """
        Compiling ModuleName File1.swift
        Linking MyApp
        """

        let parser = SwiftBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.metrics.targetCount, 1)
    }

    func testParseMultipleTargets() {
        let input = """
        Compiling Module1 File1.swift
        Linking Module1
        Compiling Module2 File2.swift
        Linking Module2
        """

        let parser = SwiftBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.metrics.targetCount, 2)
    }

    // MARK: - Category Tests

    func testParseLinkerErrors() {
        let input = """
        /path/to/File.swift:10:5: error: linker command failed with exit code 1
        """

        let parser = SwiftBuildParser()
        let result = parser.parse(input)

        let error = result.diagnostics.first
        XCTAssertEqual(error?.category, .linking)
    }

    func testParseDependencyErrors() {
        let input = """
        error: package dependency 'MyPackage' not found
        """

        let parser = SwiftBuildParser()
        let result = parser.parse(input)

        let error = result.diagnostics.first
        XCTAssertEqual(error?.category, .dependency)
    }

    func testParseCompilationErrors() {
        let input = """
        /path/to/File.swift:10:5: error: use of unresolved identifier
        """

        let parser = SwiftBuildParser()
        let result = parser.parse(input)

        let error = result.diagnostics.first
        XCTAssertEqual(error?.category, .compilation)
    }

    // MARK: - Edge Cases

    func testParseEmptyLines() {
        let input = """

        Compiling Swift Module 'MyApp'

        Build complete!

        """

        let parser = SwiftBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.metrics.errorCount, 0)
    }

    func testParseUnknownStatusWithoutErrors() {
        let input = """
        Compiling Swift Module 'MyApp'
        """

        let parser = SwiftBuildParser()
        let result = parser.parse(input)

        // Should default to success when no errors
        XCTAssertEqual(result.status, .success)
    }

    func testParseUnknownStatusWithErrors() {
        let input = """
        /path/to/File.swift:10:5: error: unresolved identifier
        """

        let parser = SwiftBuildParser()
        let result = parser.parse(input)

        // Should default to failed when errors exist
        XCTAssertEqual(result.status, .failed)
    }

    func testParseVeryLongDuration() {
        let input = """
        Build complete! (1234.56s)
        """

        let parser = SwiftBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.timing.totalDuration, 1234.56, accuracy: 0.01)
    }

    func testParseZeroDuration() {
        let input = """
        Build complete! (0s)
        """

        let parser = SwiftBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.timing.totalDuration, 0.0, accuracy: 0.01)
    }

    func testParseBuildStatusVariations() {
        let testCases = [
            "Build complete!",
            "build complete",
            "BUILD SUCCEEDED"
        ]

        for testCase in testCases {
            let input = testCase
            let parser = SwiftBuildParser()
            let result = parser.parse(input)

            XCTAssertEqual(result.status, .success, "Failed for: \(testCase)")
        }
    }

    func testParseBuildFailedStatus() {
        let testCases = [
            "build failed",
            "BUILD FAILED",
            "error: build failed"
        ]

        for testCase in testCases {
            let input = testCase
            let parser = SwiftBuildParser()
            let result = parser.parse(input)

            XCTAssertEqual(result.status, .failed, "Failed for: \(testCase)")
        }
    }

    // MARK: - CanParse Tests

    func testCanParseSwiftBuild() {
        XCTAssertTrue(SwiftBuildParser.canParse("swift build"))
        XCTAssertTrue(SwiftBuildParser.canParse("swift test"))
        XCTAssertTrue(SwiftBuildParser.canParse("Compiling Swift Module"))
        XCTAssertTrue(SwiftBuildParser.canParse("Build complete!"))
        XCTAssertTrue(SwiftBuildParser.canParse("Apple Swift version"))
        XCTAssertTrue(SwiftBuildParser.canParse("Building for"))
        XCTAssertTrue(SwiftBuildParser.canParse("Linking "))
        XCTAssertTrue(SwiftBuildParser.canParse("Fetching https://"))
        XCTAssertTrue(SwiftBuildParser.canParse("Cloning https://"))
        XCTAssertTrue(SwiftBuildParser.canParse("Resolving https://"))
    }

    func testCanParseNotConfusedWithXcode() {
        XCTAssertFalse(SwiftBuildParser.canParse("** BUILD SUCCEEDED **"))
        XCTAssertFalse(SwiftBuildParser.canParse("=== BUILD TARGET"))
        XCTAssertFalse(SwiftBuildParser.canParse("CodeSign"))
    }

    func testCanParseWithDiagnostics() {
        let input = "/path/to/file.swift:10:5: error: test"
        XCTAssertTrue(SwiftBuildParser.canParse(input))

        let input2 = "/path/to/file.swift:15:3: warning: test"
        XCTAssertTrue(SwiftBuildParser.canParse(input2))
    }

    // MARK: - SPM Specific Tests

    func testParseSPMBuildOutput() {
        let input = """
        $ swift build
        Building for production...
        Compiling Swift Module 'MyLibrary' (3 sources)
        Compiling MyLibrary File1.swift
        Compiling MyLibrary File2.swift
        Compiling MyLibrary File3.swift
        Linking MyLibrary
        Build complete! (5.2s)
        """

        let parser = SwiftBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.format, .swift)
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.metrics.compiledFiles.count, 3)
        XCTAssertEqual(result.timing.totalDuration, 5.2, accuracy: 0.01)
    }

    func testParseSPMIncrementalBuild() {
        let input = """
        Building for production...
        Compiling MyLibrary File1.swift (incremental)
        Compiling MyLibrary File2.swift (incremental)
        Linking MyLibrary
        Build complete! (1.5s)
        """

        let parser = SwiftBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.metrics.compiledFiles.count, 2)
    }

    // MARK: - Complex Real-World Scenarios

    func testParseComplexBuildWithMultipleIssues() {
        let input = """
        Building for production...
        Compiling Swift Module 'MyApp' (10 sources)
        /path/to/NetworkManager.swift:45:12: error: use of unresolved identifier 'URLSession'
        /path/to/NetworkManager.swift:67:8: warning: 'try?' has no effect on 'async' call
        /path/to/UserViewController.swift:23:15: error: value of optional type 'User?' not unwrapped
        /path/to/UserViewController.swift:30:5: note: did you mean to use 'try!'?
        /path/to/DataModel.swift:10:1: warning: result of call to 'save()' is unused
        Compiling MyApp AppDelegate.swift
        Compiling MyApp SceneDelegate.swift
        Linking MyApp
        Build complete! (8.7s)
        """

        let parser = SwiftBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.metrics.errorCount, 2)
        XCTAssertEqual(result.metrics.warningCount, 2)
        XCTAssertEqual(result.metrics.infoCount, 1)
        // compiledFiles counts files from "Compiling ModuleName file.swift" lines
        XCTAssertEqual(result.metrics.compiledFiles.count, 2)
        XCTAssertEqual(result.timing.totalDuration, 8.7, accuracy: 0.01)

        // Verify error details
        let errors = result.errors
        XCTAssertTrue(errors[0].message.contains("unresolved identifier"))
        XCTAssertTrue(errors[1].message.contains("optional"))
    }

    func testParseWithAbsolutePathLocations() {
        let input = """
        /Users/dev/Projects/MyApp/Sources/AppDelegate.swift:15:8: error: missing argument label
        /System/Volumes/Data/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS17.0.sdk/usr/include/module.modulemap:45:20: note: expanded from macro
        """

        let parser = SwiftBuildParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.metrics.errorCount, 1)
        XCTAssertEqual(result.metrics.infoCount, 1)

        let error = result.errors.first
        XCTAssertEqual(error?.filePath, "/Users/dev/Projects/MyApp/Sources/AppDelegate.swift")
        XCTAssertEqual(error?.lineNumber, 15)
        XCTAssertEqual(error?.column, 8)
    }
}
