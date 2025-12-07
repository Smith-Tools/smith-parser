import XCTest
@testable import sbparser

final class SPMOutputParserTests: XCTestCase {

    // MARK: - Dump Package Tests

    func testParseDumpPackageJSON() {
        let input = """
        {
          "name" : "MyPackage",
          "path" : "/path/to/MyPackage",
          "products" : [
            {
              "name" : "MyLibrary",
              "type" : {
                "name" : "library"
              }
            }
          ],
          "dependencies" : []
        }
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.format, .spm)
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.metrics.errorCount, 0)
        XCTAssertNotNil(result.spmInfo)

        if let spmInfo = result.spmInfo {
            XCTAssertEqual(spmInfo["command"] as? String, "dump-package")
            XCTAssertEqual(spmInfo["success"] as? Bool, true)
            XCTAssertEqual(spmInfo["packageName"] as? String, "MyPackage")

            if let targets = spmInfo["targets"] as? [[String: Any]] {
                XCTAssertEqual(targets.count, 1)
                XCTAssertEqual(targets[0]["name"] as? String, "MyLibrary")
                XCTAssertEqual(targets[0]["type"] as? String, "library")
            }
        }
    }

    func testParseDumpPackageWithDependencies() {
        let input = """
        {
          "name" : "MyPackage",
          "products" : [],
          "dependencies" : [
            {
              "sourceControl" : [
                {
                  "identity" : "swift-algorithms",
                  "requirement" : {
                    "range" : [
                      {
                        "lowerBound" : "1.0.0",
                        "upperBound" : "2.0.0"
                      }
                    ]
                  },
                  "location" : {
                    "remote" : [
                      {
                        "urlString" : "https://github.com/apple/swift-algorithms.git"
                      }
                    ]
                  }
                }
              ]
            }
          ]
        }
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.format, .spm)
        XCTAssertEqual(result.status, .success)

        if let spmInfo = result.spmInfo,
           let dependencies = spmInfo["dependencies"] as? [[String: Any]] {
            XCTAssertEqual(dependencies.count, 1)
            XCTAssertEqual(dependencies[0]["name"] as? String, "swift-algorithms")
            XCTAssertEqual(dependencies[0]["version"] as? String, "1.0.0 - 2.0.0")
            XCTAssertEqual(dependencies[0]["type"] as? String, "source-control")
            XCTAssertEqual(dependencies[0]["url"] as? String, "https://github.com/apple/swift-algorithms.git")
        }
    }

    func testParseDumpPackageInvalidJSON() {
        let input = "{ invalid json }"

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.format, .spm)
        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.metrics.errorCount, 1)
        let firstMessage = result.diagnostics.first?.message ?? ""
        XCTAssertTrue(firstMessage.contains("Failed to parse"))
    }

    func testParseDumpPackageWithMultipleProducts() {
        let input = """
        {
          "name" : "MyPackage",
          "products" : [
            {
              "name" : "MyLibrary",
              "type" : { "name" : "library" }
            },
            {
              "name" : "MyExecutable",
              "type" : { "name" : "executable" }
            }
          ],
          "dependencies" : []
        }
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.status, .success)

        if let spmInfo = result.spmInfo,
           let targets = spmInfo["targets"] as? [[String: Any]] {
            XCTAssertEqual(targets.count, 2)
            XCTAssertEqual(targets[0]["name"] as? String, "MyLibrary")
            XCTAssertEqual(targets[1]["name"] as? String, "MyExecutable")
        }
    }

    // MARK: - Show Dependencies Tests

    func testParseShowDependenciesTree() {
        let input = """
        Dependencies:
        └─ MyPackage
           ├─ swift-algorithms@1.0.0
           ├─ swift-nio@2.0.0
           └─ logging
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.format, .spm)
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.metrics.targetCount, 3)
    }

    func testParseShowDependenciesWithDifferentFormats() {
        let input = """
        Dependencies:
        ├─ package-a (1.2.3)
        ├─ package-b@4.5.6
        ├─ package-c [https://github.com/example/package-c.git]
        └─ package-d<https://github.com/example/package-d.git@1.0.0>
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.metrics.targetCount, 4)
    }

    func testParseShowDependenciesWithNoDependencies() {
        let input = """
        Dependencies:
        MyPackage
        No dependencies
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.metrics.targetCount, 0)
    }

    func testParseShowDependenciesWithErrors() {
        let input = """
        Dependencies:
        ├─ package-a
        error: Could not find package
        warning: package version not specified
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.metrics.errorCount, 1)
        XCTAssertEqual(result.metrics.warningCount, 1)
    }

    func testParseDependencyLineWithVersionInParens() {
        let input = """
        Dependencies:
        swift-algorithms (1.0.0..<2.0.0)
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.metrics.targetCount, 1)
    }

    func testParseDependencyLineWithAtSymbol() {
        let input = """
        Dependencies:
        swift-nio@main
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.metrics.targetCount, 1)
    }

    func testParseDependencyLineWithBrackets() {
        let input = """
        Dependencies:
        package-a [https://github.com/example/package-a.git]
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.metrics.targetCount, 1)
    }

    func testParseDependencyLineWithAngleBrackets() {
        let input = """
        Dependencies:
        package-a<https://github.com/example/package-a.git@1.0.0>
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.metrics.targetCount, 1)
    }

    // MARK: - Resolve Tests

    func testParseResolveOutput() {
        let input = """
        Resolving https://github.com/apple/swift-algorithms.git versions
        Fetching https://github.com/apple/swift-algorithms.git
        Completed resolution in 1.23s
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.format, .spm)
        XCTAssertEqual(result.status, .success)
        XCTAssertTrue(result.metrics.infoCount > 0)
    }

    func testParseResolveWithErrors() {
        let input = """
        Resolving package dependencies
        error: Could not resolve package dependencies
        Failed to resolve dependencies
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.metrics.errorCount, 2)
    }

    func testParseResolveWithWarnings() {
        let input = """
        Resolving package dependencies
        warning: Package 'MyPackage' is not used
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.metrics.warningCount, 1)
    }

    func testParseResolveWithCloningMessages() {
        let input = """
        Cloning https://github.com/example/repo.git
        Resolving package versions
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.status, .success)
        XCTAssertTrue(result.metrics.infoCount > 0)
    }

    // MARK: - Update Tests

    func testParseUpdateOutput() {
        let input = """
        Updating GitHub.com packages
        Updated swift-algorithms@1.0.1
        Updated swift-nio@2.1.0
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.format, .spm)
        XCTAssertEqual(result.status, .success)
    }

    func testParseUpdateWithCheckingOut() {
        let input = """
        Updating package dependencies
        Checking out swift-algorithms@1.0.1
        Checking out swift-nio@2.1.0
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.status, .success)
    }

    func testParseUpdateWithNoChanges() {
        let input = """
        Updating package dependencies
        No changes
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.status, .success)
    }

    func testParseUpdateWithFailures() {
        let input = """
        Updating package dependencies
        error: Could not update package
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.metrics.errorCount, 1)
    }

    // MARK: - Describe Tests

    func testParseDescribeOutput() {
        let input = """
        Package Name: MyPackage
        Package Version: 1.0.0
        Platforms: iOS, macOS
        Products:
          - MyLibrary (library)
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.format, .spm)
        XCTAssertEqual(result.status, .success)
    }

    func testParseDescribeWithErrors() {
        let input = """
        Package Name: MyPackage
        error: Invalid package manifest
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.metrics.errorCount, 1)
    }

    func testParseDescribeWithWarnings() {
        let input = """
        Package Name: MyPackage
        warning: Package name should be lowercase
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.metrics.warningCount, 1)
    }

    // MARK: - Dependency Type Detection Tests

    func testDetectSourceControlDependency() {
        let input = """
        Dependencies:
        package-a [https://github.com/example/package-a.git]
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.metrics.targetCount, 1)
    }

    func testDetectRegistryDependency() {
        let input = """
        Dependencies:
        swift-algorithms 1.0.0
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.metrics.targetCount, 1)
    }

    func testDetectBinaryDependency() {
        let input = """
        Dependencies:
        binary-package 1.0.0
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.metrics.targetCount, 1)
    }

    // MARK: - CanParse Tests

    func testCanParseDumpPackage() {
        let input = """
        {
          "name" : "MyPackage",
          "targets" : []
        }
        """

        XCTAssertTrue(SPMOutputParser.canParse(input))
    }

    func testCanParseShowDependencies() {
        let input = """
        ├─ package-a
        └─ package-b
        """

        XCTAssertTrue(SPMOutputParser.canParse(input))
    }

    func testCanParseResolve() {
        let input = "resolving dependencies"
        XCTAssertTrue(SPMOutputParser.canParse(input))

        let input2 = "fetching package"
        XCTAssertTrue(SPMOutputParser.canParse(input2))
    }

    func testCanParseUpdate() {
        let input = "updating package dependencies"
        XCTAssertTrue(SPMOutputParser.canParse(input))
    }

    func testCanParseDescribe() {
        let input = "Package Name: MyPackage"
        XCTAssertTrue(SPMOutputParser.canParse(input))
    }

    func testCanParseCloning() {
        let input = "cloning repository"
        XCTAssertTrue(SPMOutputParser.canParse(input))
    }

    // MARK: - Edge Cases

    func testParseEmptyInput() {
        let input = ""

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.format, .spm)
        XCTAssertEqual(result.status, .unknown)
        XCTAssertEqual(result.diagnostics.count, 0)
    }

    func testParseUnknownSPMCommand() {
        let input = """
        Some random output
        that doesn't match
        any SPM pattern
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.format, .spm)
        XCTAssertEqual(result.status, .unknown)
    }

    func testParseComplexTreeStructure() {
        let input = """
        Dependencies:
        └─ RootPackage
           ├─ PackageA (1.0.0)
           ├─ PackageB
           │  ├─ SubPackageA
           │  └─ SubPackageB
           └─ PackageC
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.metrics.targetCount, 5)
    }

    func testParseWithTreeCharactersInURL() {
        let input = """
        Dependencies:
        ├─ package-a [https://github.com/example/package-a.git]
        └─ package-b <https://github.com/example/package-b.git@main>
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.metrics.targetCount, 2)
    }

    func testParseDependencyWithRevision() {
        let input = """
        Dependencies:
        package-a revision: abc1234
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.metrics.targetCount, 1)
    }

    func testParseDependencyWithBranch() {
        let input = """
        Dependencies:
        package-a branch: develop
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.metrics.targetCount, 1)
    }

    func testParseDependencyWithExactVersion() {
        let input = """
        Dependencies:
        package-a exact: 1.2.3
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.metrics.targetCount, 1)
    }

    // MARK: - Mixed Output Tests

    func testParseMixedSPMOutput() {
        let input = """
        Resolving package dependencies
        warning: Package 'OldPackage' is deprecated
        ├─ PackageA (1.0.0)
        ├─ PackageB@main
        └─ PackageC [https://github.com/example/package-c.git]
        Completed resolution
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.metrics.warningCount, 1)
        XCTAssertEqual(result.metrics.targetCount, 3)
    }

    func testParseRealWorldDependencyOutput() {
        let input = """
        swift-tools-version: 5.9
        Dependencies:
        └─ MyApp
           ├─ swift-algorithms@1.0.0..<2.0.0
           ├─ swift-nio@2.0.0..<3.0.0
           ├─ Logging (1.4.0)
           └─ ArgumentParser@main
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.metrics.targetCount, 4)
    }

    // MARK: - Multiple Targets with Dependencies

    func testParseTargetsWithDependencies() {
        let input = """
        {
          "name" : "MyPackage",
          "products" : [
            {
              "name" : "MyLibrary",
              "type" : { "name" : "library" }
            },
            {
              "name" : "MyTool",
              "type" : { "name" : "executable" },
              "dependencies" : ["MyLibrary"]
            }
          ],
          "dependencies" : [
            {
              "sourceControl" : [
                {
                  "identity" : "dependency-a",
                  "location" : { "remote" : [{ "urlString" : "https://example.com/a.git" }] }
                }
              ]
            }
          ]
        }
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        XCTAssertEqual(result.status, .success)

        if let spmInfo = result.spmInfo,
           let targets = spmInfo["targets"] as? [[String: Any]],
           let dependencies = spmInfo["dependencies"] as? [[String: Any]] {
            XCTAssertEqual(targets.count, 2)
            XCTAssertEqual(dependencies.count, 1)
        }
    }

    // MARK: - Version Extraction Tests

    func testExtractVersionFromRange() {
        let input = """
        {
          "dependencies" : [
            {
              "sourceControl" : [
                {
                  "requirement" : { "range" : ["1.0.0", "2.0.0"] }
                }
              ]
            }
          ]
        }
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        if let spmInfo = result.spmInfo,
           let dependencies = spmInfo["dependencies"] as? [[String: Any]],
           let version = dependencies.first?["version"] as? String {
            XCTAssertEqual(version, "1.0.0, 2.0.0")
        }
    }

    func testExtractVersionFromBranch() {
        let input = """
        {
          "dependencies" : [
            {
              "sourceControl" : [
                {
                  "requirement" : { "branch" : "main" }
                }
              ]
            }
          ]
        }
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        if let spmInfo = result.spmInfo,
           let dependencies = spmInfo["dependencies"] as? [[String: Any]],
           let version = dependencies.first?["version"] as? String {
            XCTAssertEqual(version, "branch: main")
        }
    }

    func testExtractVersionFromRevision() {
        let input = """
        {
          "dependencies" : [
            {
              "sourceControl" : [
                {
                  "requirement" : { "revision" : "abc123def456" }
                }
              ]
            }
          ]
        }
        """

        let parser = SPMOutputParser()
        let result = parser.parse(input)

        if let spmInfo = result.spmInfo,
           let dependencies = spmInfo["dependencies"] as? [[String: Any]],
           let version = dependencies.first?["version"] as? String {
            XCTAssertEqual(version, "revision: abc123d")
        }
    }
}
