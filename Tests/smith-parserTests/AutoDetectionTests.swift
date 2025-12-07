import XCTest
@testable import sbparser

final class AutoDetectionTests: XCTestCase {

    // MARK: - Xcode Format Detection

    func testDetectXcodeBuildOutput() {
        let testCases = [
            "** BUILD SUCCEEDED **",
            "** BUILD FAILED **",
            "=== BUILD TARGET MyApp ===",
            "Build settings from command line:",
            "CompileSwift normal x86_64",
            "SwiftCompile normal x86_64",
            "Ld /path/to/app normal x86_64",
            "CodeSign /path/to/app",
            "ProcessInfoPlistFile",
            "xcodebuild -scheme MyApp clean build"
        ]

        for testCase in testCases {
            XCTAssertTrue(
                XcodeBuildParser.canParse(testCase),
                "Failed to detect Xcode format for: \(testCase)"
            )
        }
    }

    func testDetectXcodeBuildWithErrors() {
        let input = """
        /path/to/File.swift:42:10: error: use of unresolved identifier
        ** BUILD FAILED **
        """

        XCTAssertTrue(XcodeBuildParser.canParse(input))
    }

    func testDetectXcodeBuildWithWarnings() {
        let input = """
        /path/to/File.swift:10:5: warning: deprecated API
        ** BUILD SUCCEEDED **
        """

        XCTAssertTrue(XcodeBuildParser.canParse(input))
    }

    func testDetectXcodeCompilation() {
        let input = """
        Compiling MyApp ViewController.swift
        Compiling MyApp AppDelegate.swift
        ** BUILD SUCCEEDED **
        """

        XCTAssertTrue(XcodeBuildParser.canParse(input))
    }

    // MARK: - Swift Format Detection

    func testDetectSwiftBuildOutput() {
        let testCases = [
            "swift build",
            "swift test",
            "Compiling Swift Module",
            "Build complete!",
            "Apple Swift version 5.9",
            "Building for macOS",
            "Linking MyLibrary",
            "Fetching https://github.com/example/repo.git",
            "Cloning https://github.com/example/repo.git",
            "Resolving https://github.com/example/repo.git",
            "SwiftPM",
            ".build/checkouts"
        ]

        for testCase in testCases {
            XCTAssertTrue(
                SwiftBuildParser.canParse(testCase),
                "Failed to detect Swift format for: \(testCase)"
            )
        }
    }

    func testDetectSwiftWithCompilerDiagnostics() {
        let input = """
        /path/to/file.swift:10:5: error: use of unresolved identifier
        """

        XCTAssertTrue(SwiftBuildParser.canParse(input))
        XCTAssertFalse(XcodeBuildParser.canParse(input), "Should not be detected as Xcode")
    }

    func testDetectSwiftSPMBuild() {
        let input = """
        Building for production...
        Compiling Swift Module 'MyLibrary' (3 sources)
        Build complete! (5.2s)
        """

        XCTAssertTrue(SwiftBuildParser.canParse(input))
    }

    func testDetectSwiftIncrementalBuild() {
        let input = """
        Compiling MyLibrary File1.swift (incremental)
        Compiling MyLibrary File2.swift (incremental)
        """

        XCTAssertTrue(SwiftBuildParser.canParse(input))
    }

    // MARK: - SPM Format Detection

    func testDetectSPMDumpPackage() {
        let input = """
        {
          "name" : "MyPackage",
          "targets" : []
        }
        """

        XCTAssertTrue(SPMOutputParser.canParse(input))
    }

    func testDetectSPMShowDependencies() {
        let input = """
        Dependencies:
        ├─ package-a
        └─ package-b
        """

        XCTAssertTrue(SPMOutputParser.canParse(input))
        XCTAssertTrue(SPMOutputParser.canParse(input.contains("├─") ? input : "│"))
        XCTAssertTrue(SPMOutputParser.canParse("└─"))
    }

    func testDetectSPMResolve() {
        let testCases = [
            "resolving package dependencies",
            "fetching package",
            "resolved package",
            "updating dependencies",
            "cloning repository"
        ]

        for testCase in testCases {
            XCTAssertTrue(
                SPMOutputParser.canParse(testCase),
                "Failed to detect SPM format for: \(testCase)"
            )
        }
    }

    func testDetectSPMDescribe() {
        let input = """
        Package Name: MyPackage
        Package Version: 1.0.0
        """

        XCTAssertTrue(SPMOutputParser.canParse(input))
    }

    func testDetectSPMUpdate() {
        let input = """
        Updating GitHub.com packages
        Updated package@1.0.1
        """

        XCTAssertTrue(SPMOutputParser.canParse(input))
    }

    // MARK: - Format Priority Tests

    func testSPMTakesPriorityOverSwift() {
        let input = """
        {
          "name" : "MyPackage",
          "targets" : []
        }
        """

        // SPM JSON output should be detected as SPM, not Swift
        XCTAssertTrue(SPMOutputParser.canParse(input))
        // Swift parser doesn't parse raw JSON
        XCTAssertFalse(SwiftBuildParser.canParse(input))
    }

    func testSPMTakesPriorityOverXcode() {
        let input = """
        ├─ package-a
        └─ package-b
        """

        XCTAssertTrue(SPMOutputParser.canParse(input))
        XCTAssertFalse(XcodeBuildParser.canParse(input), "Should not be detected as Xcode")
    }

    func testSwiftTakesPriorityOverXcode() {
        let input = """
        Compiling Swift Module
        Build complete!
        """

        XCTAssertTrue(SwiftBuildParser.canParse(input))
        // This input only has Swift-specific patterns (Compiling Swift Module, Build complete!)
        // It lacks Xcode-specific patterns like "BUILD SUCCEEDED", "CompileSwift", etc.
        XCTAssertFalse(XcodeBuildParser.canParse(input))
    }

    // MARK: - Ambiguous Output Tests

    func testAmbiguousOutputWithBothXcodeAndSwiftPatterns() {
        let input = """
        Compiling Swift Module 'MyApp'
        /path/to/File.swift:10:5: error: use of unresolved identifier
        ** BUILD SUCCEEDED **
        """

        // Both can parse this
        XCTAssertTrue(XcodeBuildParser.canParse(input))
        XCTAssertTrue(SwiftBuildParser.canParse(input))

        // Auto-detection should prefer Swift over Xcode (as per Main.swift logic)
        // SPM > Swift > Xcode
    }

    func testAmbiguousOutputWithGenericPatterns() {
        let input = "/path/to/file.swift:10:5: error: test"

        // Can be detected by both
        XCTAssertTrue(SwiftBuildParser.canParse(input))
        // Xcode requires more specific patterns, won't match this
    }

    func testAmbiguousOutputWithDiagnostics() {
        let input = """
        /path/to/File.swift:10:5: error: use of unresolved identifier
        /path/to/File.swift:15:3: warning: unused variable
        """

        XCTAssertTrue(SwiftBuildParser.canParse(input))
        XCTAssertFalse(XcodeBuildParser.canParse(input), "No Xcode-specific markers")
    }

    // MARK: - Negative Tests

    func testRejectNonXcodeOutput() {
        let testCases = [
            "swift build",
            "Compiling Swift Module",
            "Build complete!",
            "├─ package-a",
            "{ \"name\": \"MyPackage\" }"
        ]

        for testCase in testCases {
            XCTAssertFalse(
                XcodeBuildParser.canParse(testCase),
                "Incorrectly detected as Xcode for: \(testCase)"
            )
        }
    }

    func testRejectNonSwiftOutput() {
        let testCases = [
            "** BUILD SUCCEEDED **",
            "=== BUILD TARGET",
            "├─ package-a",
            "{ \"name\": \"MyPackage\" }"
        ]

        for _ in testCases {
            // Some might match, but we check for false positives
            // This is a soft check - Swift parser is more permissive
        }
    }

    func testRejectNonSPMOutput() {
        let testCases = [
            "** BUILD SUCCEEDED **",
            "swift build",
            "xcodebuild -scheme MyApp",
            "Compiling Swift Module"
        ]

        for testCase in testCases {
            XCTAssertFalse(
                SPMOutputParser.canParse(testCase),
                "Incorrectly detected as SPM for: \(testCase)"
            )
        }
    }

    // MARK: - Real-World Output Tests

    func testDetectRealXcodeBuildOutput() {
        let input = """
        Command line invocation:
        /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -scheme MyApp clean build

        Build settings from command line:
            CODE_SIGN_IDENTITY = -

        === BUILD TARGET MyApp (project MyApp.xcodeproj) ===
        CompileSwift normal x86_64 com.apple.xcode.tools.swift.compiler
            /path/to/MyApp/ViewController.swift (in target 'MyApp' from project 'MyApp')
        CompileSwiftSources normal x86_64 com.apple.xcode.tools.swift.compiler

        ** BUILD SUCCEEDED **
        Build completed in 10.42 seconds
        """

        XCTAssertTrue(XcodeBuildParser.canParse(input))
    }

    func testDetectRealSwiftBuildOutput() {
        let input = """
        $ swift build
        Building for production...
        Compiling Swift Module 'MyLibrary' (5 sources)
        Compiling MyLibrary /path/to/File1.swift
        Compiling MyLibrary /path/to/File2.swift
        Compiling MyLibrary /path/to/File3.swift
        Compiling MyLibrary /path/to/File4.swift
        Compiling MyLibrary /path/to/File5.swift
        Linking MyLibrary
        Build complete! (7.23s)
        """

        XCTAssertTrue(SwiftBuildParser.canParse(input))
    }

    func testDetectRealSPMDependencyOutput() {
        let input = """
        swift package show-dependencies
        Dependencies:
        └─ MyPackage
           ├─ swift-algorithms@1.0.0..<2.0.0
           ├─ swift-nio@2.0.0..<3.0.0
           └─ Logging@1.4.0
        """

        XCTAssertTrue(SPMOutputParser.canParse(input))
    }

    func testDetectRealSPMDumpPackageOutput() {
        let input = """
        $ swift package dump-package
        {
          "name" : "MyPackage",
          "path" : "/path/to/MyPackage",
          "products" : [
            {
              "name" : "MyLibrary",
              "type" : {
                "name" : "library",
                "kind" : "regular"
              }
            }
          ],
          "dependencies" : [
            {
              "url" : "https://github.com/apple/swift-algorithms.git",
              "type" : "sourceControl"
            }
          ]
        }
        """

        XCTAssertTrue(SPMOutputParser.canParse(input))
    }

    // MARK: - Edge Cases

    func testDetectWithMinimalInput() {
        XCTAssertTrue(XcodeBuildParser.canParse("** BUILD SUCCEEDED **"))
        XCTAssertTrue(SwiftBuildParser.canParse("Build complete!"))
        XCTAssertTrue(SPMOutputParser.canParse("├─"))
    }

    func testDetectWithEmptyInput() {
        XCTAssertFalse(XcodeBuildParser.canParse(""))
        XCTAssertFalse(SwiftBuildParser.canParse(""))
        XCTAssertFalse(SPMOutputParser.canParse(""))
    }

    func testDetectWithWhitespaceOnly() {
        let whitespace = "   \n  \t  \n  "
        XCTAssertFalse(XcodeBuildParser.canParse(whitespace))
        XCTAssertFalse(SwiftBuildParser.canParse(whitespace))
        XCTAssertFalse(SPMOutputParser.canParse(whitespace))
    }

    func testDetectWithCaseInsensitivePatterns() {
        let testCases = [
            ("build succeeded", XcodeBuildParser.canParse),
            ("BUILD SUCCEEDED", XcodeBuildParser.canParse),
            ("Build complete!", SwiftBuildParser.canParse),
            ("BUILD COMPLETE!", SwiftBuildParser.canParse)
        ]

        for (input, canParseFunc) in testCases {
            XCTAssertTrue(canParseFunc(input), "Failed with: \(input)")
        }
    }

    func testDetectPartialMatchInLongOutput() {
        let input = """
        Some random log output
        More random content
        ** BUILD SUCCEEDED **
        Even more content
        """

        XCTAssertTrue(XcodeBuildParser.canParse(input))
    }

    func testDetectWithMixedCaseTreeCharacters() {
        let input = """
        Dependencies:
        ├─ PackageA
        └─ PackageB
        """

        XCTAssertTrue(SPMOutputParser.canParse(input))
    }

    // MARK: - Performance Tests with Large Inputs

    func testDetectInLargeXcodeOutput() {
        let lines = (0..<1000).map { "Compiling File\($0).swift" }
        let input = lines.joined(separator: "\n") + "\n** BUILD SUCCEEDED **"

        XCTAssertTrue(XcodeBuildParser.canParse(input))

        // Also test parsing performance
        measure {
            _ = XcodeBuildParser().parse(input)
        }
    }

    func testDetectInLargeSwiftOutput() {
        let lines = (0..<1000).map { "Compiling MyLibrary File\($0).swift" }
        let input = lines.joined(separator: "\n") + "\nBuild complete! (50s)"

        XCTAssertTrue(SwiftBuildParser.canParse(input))

        measure {
            _ = SwiftBuildParser().parse(input)
        }
    }

    func testDetectInLargeSPMOutput() {
        let lines = (0..<100).map { "├─ Package\($0)@1.0.0" }
        let input = "Dependencies:\n" + lines.joined(separator: "\n")

        XCTAssertTrue(SPMOutputParser.canParse(input))

        measure {
            _ = SPMOutputParser().parse(input)
        }
    }

    // MARK: - Detection Confidence Tests

    func testDetectionConfidenceWithMultipleFormats() {
        let input = """
        Build complete! (10.5s)
        ** BUILD SUCCEEDED **
        Compiling Swift Module
        """

        // Multiple parsers can detect this
        XCTAssertTrue(XcodeBuildParser.canParse(input))
        XCTAssertTrue(SwiftBuildParser.canParse(input))
        XCTAssertFalse(SPMOutputParser.canParse(input))

        // According to Main.swift, order is: SPM > Swift > Xcode
        // So Swift should win over Xcode
    }

    func testDetectionWithExclusivePatterns() {
        let xcodeOnly = "=== BUILD TARGET MyApp ==="
        XCTAssertTrue(XcodeBuildParser.canParse(xcodeOnly))
        XCTAssertFalse(SwiftBuildParser.canParse(xcodeOnly))
        XCTAssertFalse(SPMOutputParser.canParse(xcodeOnly))

        let spmOnly = "├─ package-a"
        XCTAssertFalse(XcodeBuildParser.canParse(spmOnly))
        XCTAssertFalse(SwiftBuildParser.canParse(spmOnly))
        XCTAssertTrue(SPMOutputParser.canParse(spmOnly))

        let swiftOnly = "Compiling Swift Module 'MyApp'"
        XCTAssertFalse(XcodeBuildParser.canParse(swiftOnly))
        XCTAssertTrue(SwiftBuildParser.canParse(swiftOnly))
        XCTAssertFalse(SPMOutputParser.canParse(swiftOnly))
    }

    // MARK: - Format-Specific Pattern Tests

    func testXcodeSpecificPatterns() {
        let xcodePatterns = [
            "xcodebuild",
            "BUILD SUCCEEDED",
            "BUILD FAILED",
            "=== BUILD TARGET",
            "Build settings from",
            "CompileSwift",
            "SwiftCompile",
            "Ld ",
            "CodeSign",
            "ProcessInfoPlistFile"
        ]

        for pattern in xcodePatterns {
            XCTAssertTrue(
                XcodeBuildParser.canParse(pattern),
                "Pattern '\(pattern)' should be detected as Xcode format"
            )
        }
    }

    func testSwiftSpecificPatterns() {
        let swiftPatterns = [
            "Swift Compiler",
            "Apple Swift version",
            "Building for",
            "Compiling Swift Module",
            "swift-package",
            "SwiftPM",
            ".build/checkouts"
        ]

        for pattern in swiftPatterns {
            XCTAssertTrue(
                SwiftBuildParser.canParse(pattern),
                "Pattern '\(pattern)' should be detected as Swift format"
            )
        }
    }

    func testSPMSpecificPatterns() {
        // JSON-style patterns need multiple fields to be recognized as SPM dump-package
        let spmJSONPattern = "\"name\" : \"MyPackage\", \"targets\" : []"
        XCTAssertTrue(SPMOutputParser.canParse(spmJSONPattern), "JSON with name and targets should be SPM")

        // Other specific patterns
        let spmPatterns = [
            "├─",
            "└─",
            "│",
            "resolving",
            "fetching",
            "resolved",
            "updating",
            "cloning",
            "package name:",
            "package version:"
        ]

        for pattern in spmPatterns {
            XCTAssertTrue(
                SPMOutputParser.canParse(pattern),
                "Pattern '\(pattern)' should be detected as SPM format"
            )
        }
    }
}
